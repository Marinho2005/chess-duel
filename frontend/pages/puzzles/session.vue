<script setup lang="ts">
import { Chess, type Color as ChessColor, type Square } from 'chess.js'
import type { Color, Key } from '@lichess-org/chessground/types'
import { Socket, type Channel } from 'phoenix'
import { Check, Clock3, Flame, Heart, RefreshCw, Target, X } from 'lucide-vue-next'
import { readBoardLayoutSize, writeBoardLayoutSize, type BoardLayoutSize } from '~/utils/boardLayout'
import { soundForSan } from '~/utils/gameSound'

definePageMeta({ middleware: 'auth', layout: false })

type Puzzle = { id: string; fen: string; rating: number; themes: string[]; setup_move: string; played_moves?: string[]; expected_index: number; instructions: string }
type PuzzleResponse = { puzzle: Puzzle; puzzle_rating: number }
type AttemptResult = { status: 'correct' | 'incorrect'; resolved: boolean; automatic_move?: string | null; next_index?: number; puzzle_rating?: number; rating_change?: number }
type RushState = { session_id: string; duration_seconds: number; remaining_ms: number; preparation_remaining_ms?: number; score: number; errors: number; maximum_errors: number; finished: boolean; puzzle?: Puzzle }
type RushAttempt = AttemptResult & RushState
type Mode = 'classic' | 'rush'
type Feedback = 'idle' | 'correct' | 'incorrect' | 'solved' | 'failed' | 'expired'

const auth = useAuthStore()
const { request } = useApi()
const route = useRoute()
const sounds = useGameSounds()
const mode = ref<Mode>(route.query.mode === 'rush' ? 'rush' : 'classic')
const puzzle = ref<Puzzle | null>(null)
const boardFen = ref('start')
const orientation = ref<Color>('white')
const turnColor = ref<Color>('white')
const lastMove = ref<[Key, Key] | null>(null)
const inCheck = ref(false)
const expectedIndex = ref(1)
const puzzleRating = ref(1200)
const feedback = ref<Feedback>('idle')
const loading = ref(false)
const submitting = ref(false)
const errorMessage = ref('')
const rushDuration = ref<180 | 300>(180)
const rushSessionId = ref<string | null>(null)
const rushScore = ref(0)
const rushErrors = ref(0)
const rushMaximumErrors = ref(3)
const ratingChange = ref<number | null>(null)
const rushDeadline = ref<number | null>(null)
const remainingMs = ref(0)
const rushCountdown = ref(0)
const boardLayoutSize = ref<BoardLayoutSize>('standard')
let chess: Chess | null = null
let timer: ReturnType<typeof setInterval> | null = null
let countdownTimer: ReturnType<typeof setInterval> | null = null
let rushSocket: Socket | null = null
let rushChannel: Channel | null = null

const boardDisabled = computed(() => loading.value || submitting.value || rushCountdown.value > 0 || !puzzle.value || ['solved', 'failed', 'expired'].includes(feedback.value))
const formattedTime = computed(() => {
  const seconds = Math.max(0, Math.ceil(remainingMs.value / 1000))
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
})
const instruction = computed(() => {
  if (feedback.value === 'incorrect') return 'Esse lance não resolve a posição. Próximo problema.'
  if (feedback.value === 'failed') return 'Não foi dessa vez. Revise a posição e tente outro problema.'
  if (feedback.value === 'solved') return 'Puzzle resolvido! Pronto para o próximo?'
  if (feedback.value === 'correct') return 'Boa! O adversário respondeu. Encontre a continuação.'
  if (feedback.value === 'expired') return `Tempo esgotado — você resolveu ${rushScore.value} problema${rushScore.value === 1 ? '' : 's'}.`
  return orientation.value === 'white' ? 'Encontre o melhor lance para as brancas.' : 'Encontre o melhor lance para as pretas.'
})

onMounted(async () => {
  boardLayoutSize.value = readBoardLayoutSize(localStorage)
  rushDuration.value = route.query.duration === '300' ? 300 : 180
  if (mode.value === 'rush') {
    sessionStorage.removeItem(rushStorageKey())
    remainingMs.value = rushDuration.value * 1_000
    connectRushSocket()
  } else await loadTrainingPuzzle()
})
onBeforeUnmount(() => {
  stopTimer()
  if (countdownTimer) clearInterval(countdownTimer)
  rushChannel?.leave()
  rushSocket?.disconnect()
})

async function loadTrainingPuzzle() {
  loading.value = true
  errorMessage.value = ''
  feedback.value = 'idle'
  ratingChange.value = null
  const result = await request<PuzzleResponse>('/api/puzzles/next', { headers: authorizationHeaders() })
  loading.value = false
  if (!result.data) {
    errorMessage.value = 'Não foi possível carregar um problema. Confirme se o banco foi importado.'
    return
  }
  puzzleRating.value = result.data.puzzle_rating
  preparePuzzle(result.data.puzzle)
}

async function startRush() {
  if (loading.value) return
  loading.value = true
  errorMessage.value = ''
  feedback.value = 'idle'
  stopTimer()
  const result = await request<RushState>('/api/puzzle_rush/start', {
    method: 'POST', headers: authorizationHeaders(), body: { duration_seconds: rushDuration.value }
  })
  if (!result.data) {
    loading.value = false
    errorMessage.value = 'Não foi possível iniciar a Corrida de problemas.'
    return
  }
  applyRushState(result.data, false)
  sessionStorage.setItem(rushStorageKey(), result.data.session_id)
  await joinRushChannel(result.data.session_id)
  loading.value = false
  await runRushCountdown(result.data.preparation_remaining_ms)
  syncRushClock(rushDuration.value * 1_000)
  startTimer()
}

function runRushCountdown(preparationMs = 3_000) {
  const deadline = Date.now() + Math.max(preparationMs, 1)
  rushCountdown.value = Math.max(1, Math.ceil(preparationMs / 1_000))
  return new Promise<void>((resolve) => {
    if (countdownTimer) clearInterval(countdownTimer)
    countdownTimer = setInterval(() => {
      rushCountdown.value = Math.max(0, Math.ceil((deadline - Date.now()) / 1_000))
      if (rushCountdown.value > 0) return
      if (countdownTimer) clearInterval(countdownTimer)
      countdownTimer = null
      resolve()
    }, 1_000)
  })
}

async function handleMove(move: { from: Key; to: Key; promotion?: 'q' }) {
  if (!chess || !puzzle.value || boardDisabled.value) return
  const previousFen = chess.fen()
  const previousLastMove = lastMove.value
  let playedMove: ReturnType<Chess['move']>
  try {
    playedMove = chess.move({ from: move.from as Square, to: move.to as Square, promotion: move.promotion })
  } catch {
    boardFen.value = previousFen
    return
  }
  boardFen.value = chess.fen()
  lastMove.value = [move.from, move.to]
  updateBoardState()
  sounds.play(soundForSan(playedMove.san))
  submitting.value = true
  feedback.value = 'idle'
  errorMessage.value = ''
  const path = mode.value === 'classic' ? `/api/puzzles/${puzzle.value.id}/attempt` : `/api/puzzle_rush/${rushSessionId.value}/attempt`
  const payload = { from: move.from, to: move.to, promotion: move.promotion, index: expectedIndex.value }
  const data = mode.value === 'rush' && rushChannel
    ? await pushRushAttempt(payload)
    : (await request<AttemptResult | RushAttempt>(path, {
        method: 'POST', headers: authorizationHeaders(), body: payload
      })).data
  submitting.value = false
  if (!data) {
    restorePosition(previousFen, previousLastMove)
    errorMessage.value = 'Não foi possível validar o lance. Tente novamente.'
    return
  }
  if (mode.value === 'rush') handleRushResult(data as RushAttempt, previousFen, previousLastMove)
  else handleTrainingResult(data as AttemptResult, previousFen, previousLastMove)
}

function connectRushSocket() {
  if (rushSocket || !auth.token) return
  const websocketUrl = `${useRuntimeConfig().public.api.baseURL.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  rushSocket = new Socket(websocketUrl, { params: { token: auth.token } })
  rushSocket.connect()
}

function joinRushChannel(sessionId: string) {
  if (!rushSocket) return Promise.resolve()
  rushChannel?.leave()
  rushChannel = rushSocket.channel(`puzzle_rush:${sessionId}`, {})
  return new Promise<void>((resolve) => {
    rushChannel?.join()
      .receive('ok', () => resolve())
      .receive('error', () => { rushChannel = null; resolve() })
      .receive('timeout', () => { rushChannel = null; resolve() })
  })
}

function pushRushAttempt(payload: { from: Key; to: Key; promotion?: 'q'; index: number }) {
  return new Promise<RushAttempt | null>((resolve) => {
    rushChannel?.push('attempt', payload, 4_000)
      .receive('ok', (reply: RushAttempt) => resolve(reply))
      .receive('error', () => resolve(null))
      .receive('timeout', () => resolve(null))
  })
}

function handleTrainingResult(result: AttemptResult, previousFen: string, previousLastMove: [Key, Key] | null) {
  if (result.status === 'incorrect') {
    restorePosition(previousFen, previousLastMove)
    feedback.value = 'failed'
    if (result.puzzle_rating !== undefined) puzzleRating.value = result.puzzle_rating
    ratingChange.value = result.rating_change ?? null
    return
  }
  if (result.resolved) {
    feedback.value = 'solved'
    if (result.puzzle_rating !== undefined) puzzleRating.value = result.puzzle_rating
    ratingChange.value = result.rating_change ?? null
    return
  }
  applyAutomaticMove(result.automatic_move)
  expectedIndex.value = result.next_index || expectedIndex.value + 2
  feedback.value = 'correct'
}

function handleRushResult(result: RushAttempt, previousFen: string, previousLastMove: [Key, Key] | null) {
  rushScore.value = result.score
  rushErrors.value = result.errors
  rushMaximumErrors.value = result.maximum_errors
  syncRushClock(result.remaining_ms)
  if (result.finished) {
    feedback.value = 'expired'
    stopTimer()
    sessionStorage.removeItem(rushStorageKey())
    return
  }
  if (result.status === 'incorrect') {
    if (result.puzzle) preparePuzzle(result.puzzle)
    else restorePosition(previousFen, previousLastMove)
    feedback.value = 'incorrect'
    return
  }
  if (result.resolved && result.puzzle) {
    preparePuzzle(result.puzzle)
    return
  }
  applyAutomaticMove(result.automatic_move)
  expectedIndex.value = result.next_index || expectedIndex.value + 2
  feedback.value = 'correct'
}

function applyRushState(state: RushState, runTimer = true) {
  rushSessionId.value = state.session_id
  rushScore.value = state.score
  rushErrors.value = state.errors
  rushMaximumErrors.value = state.maximum_errors
  syncRushClock(state.remaining_ms)
  if (state.puzzle) preparePuzzle(state.puzzle)
  if (runTimer) startTimer()
}

function startTimer() { stopTimer(); timer = setInterval(tickClock, 250) }

function preparePuzzle(nextPuzzle: Puzzle) {
  puzzle.value = nextPuzzle
  expectedIndex.value = nextPuzzle.expected_index
  feedback.value = 'idle'
  try {
    chess = new Chess(nextPuzzle.fen)
    const moves = nextPuzzle.played_moves?.length ? nextPuzzle.played_moves : [nextPuzzle.setup_move]
    for (const uci of moves) chess.move(parseUci(uci))
    const setup = parseUci(moves.at(-1)!)
    boardFen.value = chess.fen()
    lastMove.value = [setup.from as Key, setup.to as Key]
    orientation.value = colorName(chess.turn())
    updateBoardState()
  } catch {
    chess = null
    errorMessage.value = 'O problema recebido contém uma posição inválida.'
  }
}

function applyAutomaticMove(uci?: string | null) {
  if (!chess || !uci) return
  const move = parseUci(uci)
  const playedMove = chess.move(move)
  boardFen.value = chess.fen()
  lastMove.value = [move.from as Key, move.to as Key]
  updateBoardState()
  sounds.play(soundForSan(playedMove.san))
}

function restorePosition(fen: string, previousLastMove: [Key, Key] | null) {
  chess = new Chess(fen)
  boardFen.value = fen
  lastMove.value = previousLastMove
  updateBoardState()
}

function updateBoardState() {
  if (!chess) return
  turnColor.value = colorName(chess.turn())
  inCheck.value = chess.inCheck()
}

function parseUci(uci: string) {
  return { from: uci.slice(0, 2) as Square, to: uci.slice(2, 4) as Square, promotion: (uci.slice(4, 5) || undefined) as 'q' | 'r' | 'b' | 'n' | undefined }
}
function colorName(color: ChessColor): Color { return color === 'w' ? 'white' : 'black' }
function setBoardLayoutSize(size: BoardLayoutSize) { boardLayoutSize.value = size; writeBoardLayoutSize(localStorage, size) }
function authorizationHeaders() { return { Authorization: `Bearer ${auth.token}` } }
function rushStorageKey() { return `chessduel:puzzle-rush:${rushDuration.value}` }
function syncRushClock(serverRemainingMs: number) {
  const durationMs = rushDuration.value * 1_000
  remainingMs.value = Math.min(Math.max(serverRemainingMs, 0), durationMs)
  rushDeadline.value = Date.now() + remainingMs.value
}
function tickClock() {
  if (!rushDeadline.value) return
  remainingMs.value = Math.max(rushDeadline.value - Date.now(), 0)
  if (remainingMs.value === 0) { feedback.value = 'expired'; stopTimer() }
}
function stopTimer() { if (timer) clearInterval(timer); timer = null }
function resetSessionState() {
  puzzle.value = null; chess = null; rushSessionId.value = null; rushScore.value = 0; rushErrors.value = 0; rushDeadline.value = null
  remainingMs.value = 0; errorMessage.value = ''; feedback.value = 'idle'
}
</script>

<template>
  <NavigationAppHeader>
    <template #context-actions>
      <div class="app-header-actions">
        <fieldset class="layout-size" aria-label="Tamanho do tabuleiro">
          <legend>Tabuleiro</legend>
          <button v-for="option in [{value:'compact',label:'P'},{value:'standard',label:'M'},{value:'large',label:'G'}]" :key="option.value" type="button" :class="{ active: boardLayoutSize === option.value }" :aria-pressed="boardLayoutSize === option.value" @click="setBoardLayoutSize(option.value as BoardLayoutSize)">{{ option.label }}</button>
        </fieldset>
        <button type="button" class="sound-toggle" :aria-pressed="sounds.enabled.value" :title="sounds.enabled.value ? 'Desativar sons' : 'Ativar sons'" @click="sounds.toggle">
          {{ sounds.enabled.value ? '🔊' : '🔇' }}<span>Sons</span>
        </button>
        <NuxtLink class="back-to-lobby" to="/lobby">← Voltar ao salão</NuxtLink>
      </div>
    </template>
  </NavigationAppHeader>
  <main class="puzzles-page" :class="[`layout-${boardLayoutSize}`, `mode-${mode}`]" @pointerdown.once="sounds.unlock">
    <section v-if="mode === 'rush' && !rushSessionId && !loading" class="rush-setup">
      <div class="rush-copy"><span class="rush-icon"><Flame :size="28" aria-hidden="true" /></span><div><h2>Corra contra o relógio</h2><p>Resolva o máximo de problemas em sequência antes do tempo acabar.</p></div></div>
      <fieldset><legend>Duração</legend><label><input v-model="rushDuration" type="radio" :value="180" :disabled="loading"><span>3 minutos</span></label><label><input v-model="rushDuration" type="radio" :value="300" :disabled="loading"><span>5 minutos</span></label></fieldset>
      <button class="primary-action" :disabled="loading" @click="startRush">{{ rushCountdown ? `Começando em ${rushCountdown}…` : loading ? 'Preparando…' : 'Começar o Rush' }}</button>
      <p v-if="errorMessage" class="error-message">{{ errorMessage }}</p>
    </section>

    <section v-else class="play-layout">
      <div class="board-column">
        <div v-if="rushCountdown" class="rush-countdown" aria-live="assertive"><span>Prepare-se</span><strong>{{ rushCountdown }}</strong></div>
        <div class="board-stage" :class="{ blurred: rushCountdown > 0 }">
          <div v-if="loading" class="board-placeholder">Preparando a posição…</div>
          <GameBoard v-else-if="puzzle" :fen="boardFen" :orientation="orientation" :turn-color="turnColor" :last-move="lastMove" :check="inCheck" :disabled="boardDisabled" :animation-duration="mode === 'rush' ? 0 : 180" @move="handleMove" />
          <div v-else class="board-placeholder error">Nenhum problema carregado.</div>
        </div>
      </div>
      <aside class="puzzle-panel">
        <div v-if="mode === 'rush'" class="rush-stats">
          <div><Clock3 :size="18" aria-hidden="true" /><span>Tempo</span><strong :class="{ urgent: remainingMs <= 10_000 }">{{ formattedTime }}</strong></div>
          <div><Target :size="18" aria-hidden="true" /><span>Resolvidos</span><strong>{{ rushScore }}</strong></div>
          <div class="rush-lives"><Heart v-for="life in rushMaximumErrors" :key="life" :size="18" :fill="life <= rushMaximumErrors - rushErrors ? 'currentColor' : 'none'" :class="{ lost: life > rushMaximumErrors - rushErrors }" aria-hidden="true" /><span>{{ rushErrors }}/{{ rushMaximumErrors }} erros</span></div>
        </div>
        <div class="rating-row"><span>{{ mode === 'classic' ? 'Seu rating de problemas' : 'Problema atual' }}</span><strong>{{ mode === 'classic' ? puzzleRating : puzzle?.rating }}</strong></div>
        <p v-if="mode === 'classic' && ratingChange !== null" class="rating-change" :class="{ positive: ratingChange >= 0 }">{{ ratingChange >= 0 ? '+' : '' }}{{ ratingChange }} de rating</p>
        <div class="feedback" :class="feedback" aria-live="polite">
          <span class="feedback-icon"><Check v-if="feedback === 'correct' || feedback === 'solved'" :size="22" aria-hidden="true" /><X v-else-if="feedback === 'incorrect' || feedback === 'failed'" :size="22" aria-hidden="true" /><Clock3 v-else-if="feedback === 'expired'" :size="22" aria-hidden="true" /><Target v-else :size="22" aria-hidden="true" /></span>
          <div><small>{{ puzzle ? `Problema ${puzzle.rating}` : 'Treino tático' }}</small><strong>{{ instruction }}</strong></div>
        </div>
        <div v-if="puzzle?.themes?.length" class="themes" aria-label="Temas do puzzle"><span v-for="theme in puzzle.themes.slice(0, 5)" :key="theme">{{ theme }}</span></div>
        <p v-if="submitting" class="validation-state">Validando lance…</p>
        <p v-if="errorMessage" class="error-message">{{ errorMessage }}</p>
        <button v-if="mode === 'classic' && (feedback === 'solved' || feedback === 'failed')" class="primary-action" @click="loadTrainingPuzzle">Próximo problema <span aria-hidden="true">→</span></button>
        <button v-if="mode === 'rush' && feedback === 'expired'" class="secondary-action" @click="startRush"><RefreshCw :size="17" aria-hidden="true" /> Jogar novamente</button>
      </aside>
    </section>
  </main>
</template>

<style scoped>
.puzzles-page { --board-limit:min(680px,calc(100vh - 175px)); --content-limit:1080px; min-height:calc(100vh - 60px); padding:clamp(.75rem,1.6vw,1.35rem); color:#3c2b20; background-color:#f4eddf; background-image:radial-gradient(#bba98e35 .7px,transparent .7px); background-size:5px 5px; font-family:Inter,system-ui,sans-serif; }.puzzles-page.layout-compact { --board-limit:min(540px,calc(100vh - 175px)); --content-limit:940px; }.puzzles-page.layout-large { --board-limit:min(800px,calc(100vh - 175px)); --content-limit:1200px; }
.app-header-actions { display:flex; align-items:center; gap:.55rem; margin-left:auto; }.sound-toggle,.back-to-lobby { display:inline-flex; align-items:center; gap:.35rem; padding:.38rem .55rem; color:var(--text); background:transparent; border:1px solid var(--border); border-radius:8px; font:700 .76rem Inter,sans-serif; text-decoration:none; cursor:pointer; }.sound-toggle:hover,.back-to-lobby:hover { color:var(--accent); background:var(--surface-hover); border-color:var(--accent); }
.page-header { display:flex; max-width:var(--content-limit); align-items:center; justify-content:space-between; gap:1.5rem; margin:0 auto .45rem; }.page-header.rush-header { min-height:36px; justify-content:flex-end; }.page-header h1 { margin:.04rem 0; font:500 clamp(1.65rem,2.7vw,2.25rem)/1 Georgia,serif; }.page-header p { max-width:720px; margin:.18rem 0 0; color:#806d5d; font-size:.9rem; line-height:1.3; }.header-controls { display:flex; align-items:center; gap:.55rem; }
.layout-size { display:flex; align-items:center; gap:.12rem; margin:0; padding:.2rem; background:#eee1ce; border:1px solid #d8c5a8; border-radius:9px; }.layout-size legend { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0,0,0,0); }.layout-size button { display:grid; width:29px; height:29px; place-items:center; padding:0; color:#806d5d; background:transparent; border:0; border-radius:6px; font:800 .68rem Inter,sans-serif; cursor:pointer; }.layout-size button:hover,.layout-size button.active { color:white; background:#6f4528; }.layout-size button:focus-visible { outline:3px solid #d0a45d; outline-offset:2px; }
.mode-switch { display:flex; gap:.25rem; padding:.28rem; background:#e9dcc8; border:1px solid #d8c5a8; border-radius:12px; }.mode-switch button { display:flex; align-items:center; gap:.45rem; padding:.7rem .9rem; color:#7b6858; background:transparent; border:0; border-radius:9px; cursor:pointer; font-weight:750; }.mode-switch button.active { color:#3c2b20; background:#fffaf0; box-shadow:0 4px 12px #6f452817; }.mode-switch button:focus-visible,.primary-action:focus-visible,.secondary-action:focus-visible { outline:3px solid #d0a45d; outline-offset:2px; }
.play-layout { display:grid; width:fit-content; max-width:100%; grid-template-columns:var(--board-limit) minmax(270px,340px); align-items:start; justify-content:center; gap:clamp(1rem,2vw,1.6rem); margin:-.5rem auto 0; }.board-column { position:relative; width:var(--board-limit); max-width:100%; justify-self:end; overflow:hidden; border-radius:10px; }.board-stage { transition:filter 180ms ease,transform 180ms ease; }.board-stage.blurred { filter:blur(9px); transform:scale(.985); }.board-placeholder { display:grid; width:100%; aspect-ratio:1; place-items:center; color:#7e6957; background:#e9dcc8; border:1px solid #d3bea0; border-radius:10px; }.board-placeholder.error { color:#9c3f34; }
.mode-rush .play-layout { margin-top:.85rem; }
.puzzle-panel { display:grid; gap:1rem; padding:1.15rem; background:#fffaf0ec; border:1px solid #dfcfb8; border-radius:16px; box-shadow:0 18px 38px #6f452817; }.rating-row { display:flex; align-items:center; justify-content:space-between; padding-bottom:.9rem; color:#806d5d; border-bottom:1px solid #e3d3bd; font-size:.78rem; font-weight:750; }.rating-row strong { color:#6f4528; font:700 1.55rem Georgia,serif; }
.feedback { display:flex; align-items:flex-start; gap:.8rem; min-height:98px; padding:1rem; background:#f4eadb; border:1px solid #dfcfb8; border-radius:12px; }.feedback-icon { display:grid; width:38px; height:38px; flex:0 0 auto; place-items:center; color:#fff8e8; background:#775336; border-radius:50%; }.feedback>div { display:grid; gap:.28rem; }.feedback small { color:#8c715d; font-size:.66rem; font-weight:850; letter-spacing:.08em; text-transform:uppercase; }.feedback strong { font:600 1rem/1.4 Georgia,serif; }.feedback.correct,.feedback.solved { background:#e8f0df; border-color:#b8cba5; }.feedback.correct .feedback-icon,.feedback.solved .feedback-icon { background:#587344; }.feedback.incorrect,.feedback.failed { background:#f5e1db; border-color:#deb8ad; }.feedback.incorrect .feedback-icon,.feedback.failed .feedback-icon { background:#a44738; }.feedback.expired { background:#eee4d8; }.feedback.expired .feedback-icon { background:#694b37; }
.rating-change { margin:-.7rem 0 0; color:#a44738; font-size:.75rem; font-weight:850; text-align:right; }.rating-change.positive { color:#587344; }
.themes { display:flex; flex-wrap:wrap; gap:.4rem; }.themes span { padding:.3rem .55rem; color:#725640; background:#eee1cf; border:1px solid #ddc9ac; border-radius:999px; font-size:.66rem; font-weight:750; }.primary-action,.secondary-action { display:flex; min-height:46px; align-items:center; justify-content:center; gap:.45rem; padding:.8rem 1rem; border-radius:10px; cursor:pointer; font:750 .9rem Inter,sans-serif; }.primary-action { color:white; background:#6f4528; border:1px solid #5c371f; box-shadow:0 8px 18px #6f452824; }.primary-action:hover { background:#805131; }.primary-action:disabled { opacity:.6; cursor:wait; }.secondary-action { color:#5f402b; background:#f1e4d1; border:1px solid #d4b994; }.validation-state { margin:0; color:#826b57; font-size:.78rem; }.error-message { margin:0; color:#9f3f32; font-size:.82rem; line-height:1.4; }
.rush-setup { position:relative; display:grid; max-width:780px; grid-template-columns:1fr auto; gap:1.25rem; margin:3rem auto; padding:clamp(1.2rem,3vw,2rem); background:#fffaf0ed; border:1px solid #dfcfb8; border-radius:18px; box-shadow:0 18px 40px #6f452817; }.rush-countdown { position:absolute; z-index:3; inset:0; display:grid; place-content:center; justify-items:center; gap:.35rem; color:var(--text); background:color-mix(in srgb,var(--surface) 82%,transparent); border:1px solid var(--border); border-radius:10px; backdrop-filter:blur(3px); }.rush-countdown span { color:var(--accent); font-size:.72rem; font-weight:900; letter-spacing:.14em; text-transform:uppercase; }.rush-countdown strong { font:700 clamp(4rem,12vw,7rem)/1 Georgia,serif; }.rush-copy { display:flex; grid-column:1/-1; align-items:center; gap:1rem; }.rush-icon { display:grid; width:54px; height:54px; place-items:center; color:#ffe6a8; background:#8d4028; border-radius:14px; box-shadow:0 8px 20px #8d40282c; }.rush-copy h2 { margin:0; font:600 1.55rem Georgia,serif; }.rush-copy p { margin:.3rem 0 0; color:#806d5d; }.rush-setup fieldset { display:flex; gap:.55rem; margin:0; padding:0; border:0; }.rush-setup legend { margin-bottom:.45rem; color:#806d5d; font-size:.72rem; font-weight:850; }.rush-setup label { position:relative; }.rush-setup input { position:absolute; opacity:0; }.rush-setup label span { display:block; padding:.72rem .9rem; background:#f1e4d1; border:1px solid #d7c0a0; border-radius:9px; cursor:pointer; font-weight:700; }.rush-setup input:checked+span { color:white; background:#75492c; border-color:#75492c; }.rush-setup input:focus-visible+span { outline:3px solid #d0a45d; outline-offset:2px; }.rush-setup>.error-message { grid-column:1/-1; }
.rush-stats { display:grid; grid-template-columns:1fr 1fr; gap:.55rem; }.rush-stats>div { display:grid; grid-template-columns:auto 1fr; align-items:center; gap:.2rem .4rem; padding:.75rem; color:#72503a; background:#f1e4d2; border:1px solid #ddc7aa; border-radius:10px; }.rush-stats span { font-size:.66rem; font-weight:800; text-transform:uppercase; }.rush-stats strong { grid-column:1/-1; font:700 1.6rem Georgia,serif; }.rush-stats strong.urgent { color:#a0392e; }
.rush-stats .rush-lives { display:flex; grid-column:1/-1; align-items:center; gap:.35rem; }.rush-lives span { margin-left:auto; }.rush-lives .lost { color:#b9a792; }
@media (max-width:900px) { .puzzles-page { --board-limit:min(620px,calc(100vw - 2rem)); }.play-layout { width:100%; grid-template-columns:minmax(300px,var(--board-limit)); }.puzzle-panel { grid-template-columns:1fr 1fr; }.rating-row,.feedback,.themes,.validation-state,.error-message,.puzzle-panel>button { grid-column:1/-1; } }
@media (max-width:680px) { .puzzles-page { padding:1rem; }.page-header { align-items:stretch; flex-direction:column; }.header-controls { align-items:stretch; flex-direction:column-reverse; }.layout-size { align-self:flex-end; }.mode-switch { align-self:stretch; }.mode-switch button { flex:1; justify-content:center; }.play-layout { grid-template-columns:minmax(0,1fr); }.board-column { justify-self:center; }.puzzle-panel { grid-template-columns:1fr; }.rush-setup { grid-template-columns:1fr; margin-top:1rem; }.rush-setup>* { grid-column:1; }.rush-setup fieldset { flex-wrap:wrap; }.rush-setup label { flex:1; }.rush-setup label span { text-align:center; }.feedback,.rating-row,.themes,.validation-state,.error-message,.puzzle-panel>button { grid-column:1; } }
@media (max-width:820px) { .app-header-actions { margin-left:0; }.back-to-lobby { display:none; }.sound-toggle span { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0,0,0,0); } }
@media (min-width:901px) {
  .puzzles-page.layout-compact { --board-limit:min(510px,calc(100dvh - 155px)); --content-limit:940px; padding-top:.65rem; }
  .layout-compact .page-header { margin-bottom:.45rem; }
  .layout-compact .play-layout { width:100%; max-width:940px; grid-template-columns:minmax(420px,510px) minmax(290px,340px); gap:clamp(1.2rem,3vw,2.5rem); }
  .layout-compact .board-column { width:min(100%,510px); }
}
.puzzles-page{color:var(--text);background:var(--bg)}.rating-row strong{color:var(--accent)}.page-header h1,.feedback strong,.rush-copy h2{font-family:inherit}.page-header p,.rating-row,.validation-state,.rush-copy p,.rush-setup legend{color:var(--text-muted)}.layout-size,.mode-switch{background:var(--surface-strong);border-color:var(--border)}.layout-size button,.mode-switch button{color:var(--text-muted)}.layout-size button:hover,.layout-size button.active,.mode-switch button.active{color:var(--accent-ink);background:var(--accent)}.puzzle-panel,.rush-setup{background:var(--surface);border-color:var(--border);box-shadow:var(--shadow)}.rating-row{border-color:var(--border-subtle)}.feedback,.rush-stats>div,.rush-setup label span,.themes span,.secondary-action{color:var(--text);background:var(--surface-strong);border-color:var(--border)}.feedback.correct,.feedback.solved{background:var(--success-soft);border-color:var(--success)}.feedback.incorrect,.feedback.failed{background:var(--danger-soft);border-color:var(--danger)}.primary-action,.rush-setup input:checked+span{color:var(--accent-ink);background:var(--accent);border-color:var(--accent)}.primary-action:hover{background:var(--accent-hover)}.error-message,.rating-change{color:var(--danger)}.rating-change.positive{color:var(--success)}
</style>
