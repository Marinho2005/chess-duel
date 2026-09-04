<script setup lang="ts">
import { Chess, type Color as ChessColor, type Square } from 'chess.js'
import type { Color, Key } from '@lichess-org/chessground/types'
import { Socket, type Channel } from 'phoenix'
import { ArrowLeft, Clock3, Search, Swords, X } from 'lucide-vue-next'
import { readBoardLayoutSize, writeBoardLayoutSize, type BoardLayoutSize } from '~/utils/boardLayout'
import { soundForSan } from '~/utils/gameSound'

definePageMeta({ middleware: 'auth', layout: false })

type Puzzle = { id: string; fen: string; rating: number; themes: string[]; setup_move: string; played_moves?: string[]; expected_index: number }
type Player = { id: string; nickname: string; battle_rating: number; score: number; errors: number; puzzles_attempted: number }
type Progress = Record<string, Player>
type BattleResult = { winner_id: string | null; result: string; players: Record<string, Player & { rating_change: number; rating_after: number }> }
type BattleState = { battle_id: string; status: 'preparing' | 'in_progress' | 'finished'; started_at: string; ends_at: string; server_now: string; progress: Progress; puzzle: Puzzle | null; result: BattleResult | null }
type AttemptResult = { status: 'correct' | 'incorrect'; resolved: boolean; automatic_move?: string; next_index?: number; puzzle?: Puzzle; progress: Progress }

const route = useRoute()
const auth = useAuthStore()
const config = useRuntimeConfig()
const sounds = useGameSounds()
const duration = computed<180 | 300>(() => route.params.duration === '300' ? 300 : 180)
const phase = ref<'connecting' | 'searching' | 'preparing' | 'playing' | 'finished' | 'error'>('connecting')
const message = ref('Conectando à Batalha de problemas…')
const battleId = ref<string | null>(typeof route.query.battle === 'string' ? route.query.battle : null)
const puzzle = ref<Puzzle | null>(null)
const progress = ref<Progress>({})
const result = ref<BattleResult | null>(null)
const boardFen = ref('start')
const orientation = ref<Color>('white')
const turnColor = ref<Color>('white')
const lastMove = ref<[Key, Key] | null>(null)
const inCheck = ref(false)
const expectedIndex = ref(1)
const submitting = ref(false)
const boardLayoutSize = ref<BoardLayoutSize>('standard')
const remainingMs = ref(0)
const countdownMs = ref(0)
let chess: Chess | null = null
let socket: Socket | null = null
let queueChannel: Channel | null = null
let battleChannel: Channel | null = null
let deadline = 0
let startsAt = 0
let timer: ReturnType<typeof setInterval> | null = null

const players = computed(() => Object.values(progress.value))
const me = computed(() => progress.value[auth.user?.id || ''])
const opponent = computed(() => players.value.find(player => player.id !== auth.user?.id))
const formattedTime = computed(() => formatTime(remainingMs.value))
const boardDisabled = computed(() => phase.value !== 'playing' || submitting.value || !puzzle.value)
const resultTitle = computed(() => !result.value?.winner_id ? 'Empate!' : result.value.winner_id === auth.user?.id ? 'Você venceu!' : 'Seu oponente venceu')

onMounted(async () => {
  boardLayoutSize.value = readBoardLayoutSize(localStorage)
  auth.restoreSession()
  if (!auth.user && !(await auth.fetchCurrentUser())) return navigateTo('/')
  connect()
})

onBeforeUnmount(() => {
  if (phase.value === 'searching') queueChannel?.push('leave_queue', {})
  if (timer) clearInterval(timer)
  battleChannel?.leave(); queueChannel?.leave(); socket?.disconnect()
})

function connect() {
  const websocketUrl = `${config.public.api.baseURL.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  socket = new Socket(websocketUrl, { params: { token: auth.token } })
  socket.connect()
  if (battleId.value) joinBattle(battleId.value)
  else joinQueue()
}

function joinQueue() {
  if (!socket || !auth.user) return
  queueChannel = socket.channel(`puzzle_battle:queue:${auth.user.id}`, {})
  queueChannel.on('battle_found', ({ battle_id }: { battle_id: string }) => {
    battleId.value = battle_id
    history.replaceState({}, '', `${route.path}?battle=${battle_id}`)
    queueChannel?.leave()
    joinBattle(battle_id)
  })
  queueChannel.join().receive('ok', () => {
    phase.value = 'searching'; message.value = 'Procurando um oponente com rating próximo…'
    queueChannel?.push('join_queue', { duration_seconds: duration.value })
      .receive('error', () => fail('Não foi possível entrar na fila.'))
  }).receive('error', () => fail('Não foi possível conectar à fila.'))
}

function joinBattle(id: string) {
  if (!socket) return
  battleChannel = socket.channel(`puzzle_battle:${id}`, {})
  battleChannel.on('battle_started', (next: Progress) => { progress.value = next; phase.value = 'playing'; message.value = 'Valendo!' })
  battleChannel.on('battle_progress', (next: Progress) => { progress.value = next })
  battleChannel.on('battle_finished', (final: BattleResult) => finish(final))
  battleChannel.join().receive('ok', (state: BattleState) => applySnapshot(state)).receive('error', () => fail('Esta batalha não está mais disponível.'))
}

function applySnapshot(state: BattleState) {
  progress.value = state.progress; result.value = state.result
  syncClock(state.started_at, state.ends_at, state.server_now)
  if (state.status === 'finished' && state.result) return finish(state.result)
  phase.value = state.status === 'preparing' ? 'preparing' : 'playing'
  message.value = state.status === 'preparing' ? 'O duelo começa em instantes…' : 'Valendo!'
  if (state.puzzle) preparePuzzle(state.puzzle)
}

async function handleMove(move: { from: Key; to: Key; promotion?: 'q' }) {
  if (!chess || !battleChannel || boardDisabled.value) return
  const oldFen = chess.fen(); const oldLastMove = lastMove.value
  let playedMove: ReturnType<Chess['move']>
  try { playedMove = chess.move({ from: move.from as Square, to: move.to as Square, promotion: move.promotion }) } catch { return }
  boardFen.value = chess.fen(); lastMove.value = [move.from, move.to]; updateBoard(); sounds.play(soundForSan(playedMove.san))
  submitting.value = true
  battleChannel.push('attempt', { from: move.from, to: move.to, promotion: move.promotion, index: expectedIndex.value })
    .receive('ok', (reply: AttemptResult) => {
      submitting.value = false; progress.value = reply.progress
      if (reply.puzzle) preparePuzzle(reply.puzzle)
      else if (!reply.resolved && reply.automatic_move) { applyAutomaticMove(reply.automatic_move); expectedIndex.value = reply.next_index || expectedIndex.value + 2 }
      else if (reply.status === 'incorrect') restore(oldFen, oldLastMove)
    })
    .receive('error', () => { submitting.value = false; restore(oldFen, oldLastMove) })
}

function preparePuzzle(next: Puzzle) {
  puzzle.value = next; expectedIndex.value = next.expected_index
  chess = new Chess(next.fen); const moves = next.played_moves?.length ? next.played_moves : [next.setup_move]
  for (const uci of moves) chess.move(parseUci(uci)); const setup = parseUci(moves.at(-1)!)
  boardFen.value = chess.fen(); lastMove.value = [setup.from as Key, setup.to as Key]
  orientation.value = colorName(chess.turn()); updateBoard()
}
function applyAutomaticMove(uci: string) { if (!chess) return; const move = parseUci(uci); const playedMove = chess.move(move); boardFen.value = chess.fen(); lastMove.value = [move.from as Key, move.to as Key]; updateBoard(); sounds.play(soundForSan(playedMove.san)) }
function restore(fen: string, move: [Key, Key] | null) { chess = new Chess(fen); boardFen.value = fen; lastMove.value = move; updateBoard() }
function updateBoard() { if (chess) { turnColor.value = colorName(chess.turn()); inCheck.value = chess.inCheck() } }
function parseUci(uci: string) { return { from: uci.slice(0, 2) as Square, to: uci.slice(2, 4) as Square, promotion: (uci.slice(4, 5) || undefined) as 'q' | 'r' | 'b' | 'n' | undefined } }
function colorName(color: ChessColor): Color { return color === 'w' ? 'white' : 'black' }
function setBoardLayoutSize(size: BoardLayoutSize) { boardLayoutSize.value = size; writeBoardLayoutSize(localStorage, size) }
function syncClock(start: string, end: string, serverNow: string) { const offset = Date.now() - Date.parse(serverNow); startsAt = Date.parse(start) + offset; deadline = Date.parse(end) + offset; tick(); if (timer) clearInterval(timer); timer = setInterval(tick, 200) }
function tick() {
  countdownMs.value = Math.max(startsAt - Date.now(), 0)
  remainingMs.value = Math.min(Math.max(deadline - Date.now(), 0), duration.value * 1_000)
  if (countdownMs.value === 0 && phase.value === 'preparing') phase.value = 'playing'
}
function formatTime(ms: number) { const seconds = Math.max(0, Math.ceil(ms / 1000)); return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}` }
function finish(final: BattleResult) { result.value = final; phase.value = 'finished'; puzzle.value = null; if (timer) clearInterval(timer) }
function fail(text: string) { phase.value = 'error'; message.value = text }
</script>

<template>
  <NavigationAppHeader>
    <template #context-actions>
      <div class="app-header-actions">
        <fieldset aria-label="Tamanho do tabuleiro"><legend>Tabuleiro</legend><button v-for="option in [{value:'compact',label:'P'},{value:'standard',label:'M'},{value:'large',label:'G'}]" :key="option.value" :class="{active:boardLayoutSize===option.value}" @click="setBoardLayoutSize(option.value as BoardLayoutSize)">{{ option.label }}</button></fieldset>
        <button type="button" class="sound-toggle" :aria-pressed="sounds.enabled.value" :title="sounds.enabled.value ? 'Desativar sons' : 'Ativar sons'" @click="sounds.toggle">{{ sounds.enabled.value ? '🔊' : '🔇' }}<span>Sons</span></button>
        <NuxtLink class="back-to-lobby" to="/lobby">← Voltar ao salão</NuxtLink>
      </div>
    </template>
  </NavigationAppHeader>
  <main class="battle-page" :class="`layout-${boardLayoutSize}`" @pointerdown.once="sounds.unlock">
    <section v-if="phase === 'connecting' || phase === 'searching' || phase === 'error'" class="waiting"><span><Search v-if="phase !== 'error'" :size="30" /><X v-else :size="30" /></span><h2 v-if="phase !== 'searching'">{{ phase === 'error' ? 'Algo deu errado' : 'Conectando' }}</h2><p>{{ message }}</p><NuxtLink v-if="phase === 'searching' || phase === 'error'" to="/puzzles"><ArrowLeft :size="16" aria-hidden="true" /> Voltar aos modos</NuxtLink></section>

    <section v-else class="arena">
      <div class="board-wrap"><div v-if="phase === 'preparing'" class="countdown">{{ Math.max(1, Math.ceil(countdownMs / 1000)) }}</div><div class="battle-board-stage" :class="{ blurred: phase === 'preparing' }"><GameBoard v-if="puzzle" :fen="boardFen" :orientation="orientation" :turn-color="turnColor" :last-move="lastMove" :check="inCheck" :disabled="boardDisabled" @move="handleMove" /><div v-else class="board-empty"><Swords :size="42" /><strong>{{ phase === 'finished' ? resultTitle : 'Sequência concluída' }}</strong></div></div></div>
      <aside>
        <div class="clock"><Clock3 :size="18" /><span>Tempo</span><strong>{{ formattedTime }}</strong></div>
        <div class="versus"><article><small>VOCÊ</small><h2>{{ me?.nickname }}</h2><strong>{{ me?.score || 0 }}</strong><p>{{ me?.errors || 0 }} erros</p></article><span>VS</span><article><small>OPONENTE</small><h2>{{ opponent?.nickname }}</h2><strong>{{ opponent?.score || 0 }}</strong><p>{{ opponent?.errors || 0 }} erros</p></article></div>
        <div v-if="phase === 'finished'" class="result"><h2>{{ resultTitle }}</h2><p>Rating: {{ result?.players[auth.user?.id || '']?.rating_after }} <b>{{ (result?.players[auth.user?.id || '']?.rating_change || 0) >= 0 ? '+' : '' }}{{ result?.players[auth.user?.id || '']?.rating_change }}</b></p><NuxtLink to="/puzzles">Escolher outro modo</NuxtLink></div>
        <p v-else class="hint">Ambos recebem a mesma sequência. Acertou ou errou, avance e mantenha o ritmo.</p>
      </aside>
    </section>
  </main>
</template>

<style scoped>
.battle-page{--board-limit:680px;--content-limit:1080px;min-height:calc(100vh - 60px);padding:clamp(1rem,2.8vw,2.4rem);color:#3c2b20;background-color:#f4eddf;background-image:radial-gradient(#bba98e35 .7px,transparent .7px);background-size:5px 5px;font-family:Inter,system-ui,sans-serif}.app-header-actions{display:flex;align-items:center;gap:.55rem;margin-left:auto}.sound-toggle,.back-to-lobby{display:inline-flex;align-items:center;gap:.35rem;padding:.38rem .55rem;color:var(--text);background:transparent;border:1px solid var(--border);border-radius:8px;font:700 .76rem Inter,sans-serif;text-decoration:none;cursor:pointer}.sound-toggle:hover,.back-to-lobby:hover{color:var(--accent);background:var(--surface-hover);border-color:var(--accent)}.layout-compact{--board-limit:540px;--content-limit:940px}.layout-large{--board-limit:800px;--content-limit:1200px}header{display:flex;max-width:var(--content-limit);align-items:end;justify-content:space-between;margin:0 auto 1.5rem}header a{display:flex;align-items:center;gap:.35rem;color:#70442b;font-size:.75rem;font-weight:800;text-decoration:none}header span{display:block;margin-top:.7rem;color:#70416f;font-size:.65rem;font-weight:900;letter-spacing:.13em}h1{margin:.15rem 0;font:500 clamp(2.2rem,5vw,3.5rem)/1 Georgia,serif}fieldset{display:flex;gap:.12rem;padding:.2rem;background:#eee1ce;border:1px solid #d8c5a8;border-radius:9px}legend{position:absolute;width:1px;height:1px;overflow:hidden}fieldset button{width:29px;height:29px;color:#806d5d;background:transparent;border:0;border-radius:6px;font-weight:800}fieldset button.active{color:white;background:#6f4528}.waiting{display:grid;max-width:560px;place-items:center;margin:5rem auto;padding:2.5rem;text-align:center;background:#fffaf0;border:1px solid #ddcbb0;border-radius:18px}.waiting>span{display:grid;width:62px;height:62px;place-items:center;color:#fff;background:#70416f;border-radius:50%}.waiting h2{margin:1rem 0 .25rem;font:600 1.6rem Georgia,serif}.waiting p{color:#806d5d}.waiting a,.result a{padding:.75rem 1rem;color:#fff;background:#70416f;border-radius:9px;text-decoration:none;font-weight:800}.waiting a{display:inline-flex;align-items:center;gap:.4rem}.arena{display:grid;max-width:var(--content-limit);grid-template-columns:minmax(320px,var(--board-limit)) minmax(280px,340px);gap:1.5rem;margin:-.35rem auto 0}.board-wrap{position:relative;width:100%;justify-self:end;overflow:hidden;border-radius:8px}.battle-board-stage{transition:filter 180ms ease,transform 180ms ease}.battle-board-stage.blurred{filter:blur(9px);transform:scale(.985)}.countdown{position:absolute;z-index:3;inset:0;display:grid;place-items:center;color:white;background:#2e1f176b;font:700 7rem Georgia,serif;border-radius:8px}.board-empty{display:grid;aspect-ratio:1;place-items:center;align-content:center;gap:1rem;color:#70416f;background:#ede0cc;border:1px solid #d7c1a1;border-radius:9px}.board-empty strong{font:600 1.4rem Georgia,serif}aside{display:grid;align-content:start;gap:1rem;padding:1.1rem;background:#fffaf0ed;border:1px solid #dfcfb8;border-radius:16px;box-shadow:0 18px 38px #6f452817}.clock{display:grid;grid-template-columns:auto 1fr;align-items:center;gap:.3rem;color:#70416f}.clock span{font-size:.68rem;font-weight:900;text-transform:uppercase}.clock strong{grid-column:1/-1;font:700 2.5rem Georgia,serif}.versus{display:grid;grid-template-columns:1fr auto 1fr;align-items:center;gap:.45rem}.versus>span{font:800 .72rem Georgia,serif}.versus article{padding:.8rem;text-align:center;background:#f1e4d2;border:1px solid #ddc7aa;border-radius:10px}.versus small{font-size:.58rem;font-weight:900}.versus h2{overflow:hidden;margin:.25rem 0;text-overflow:ellipsis;font:600 .9rem Georgia,serif}.versus strong{display:block;color:#70416f;font:700 2.2rem Georgia,serif}.versus p{margin:.2rem 0;color:#806d5d;font-size:.68rem}.hint{color:#806d5d;font-size:.82rem;line-height:1.5}.result{padding:1rem;text-align:center;background:#eee3ef;border:1px solid #ceb9d2;border-radius:11px}.result h2{font:600 1.5rem Georgia,serif}.result b{color:#587344}.result a{display:flex;justify-content:center;margin-top:1rem}@media(max-width:900px){.arena{grid-template-columns:minmax(280px,650px);justify-content:center}}@media(max-width:820px){.app-header-actions{margin-left:0}.back-to-lobby{display:none}.sound-toggle span{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)}}@media(max-width:620px){.battle-page{padding:1rem}header{align-items:start;gap:1rem}.arena{grid-template-columns:1fr}.versus{grid-template-columns:1fr}.versus>span{text-align:center}}
@media(min-width:901px){.battle-page.layout-compact{--board-limit:510px;--content-limit:940px;padding-top:.65rem}.layout-compact header{margin-bottom:.7rem}.layout-compact .arena{grid-template-columns:minmax(420px,510px) minmax(290px,340px);justify-content:center;gap:clamp(1.2rem,3vw,2.5rem)}.layout-compact .board-wrap{width:min(100%,510px)}}
.battle-page{color:var(--text);background:var(--bg)}header a,header span,.clock,.versus strong,.board-empty{color:var(--accent)}h1,.waiting h2,.board-empty strong,.clock strong,.versus h2,.versus strong,.result h2{font-family:inherit}fieldset,.versus article{background:var(--surface-strong);border-color:var(--border)}fieldset button{color:var(--text-muted)}fieldset button.active,.waiting>span,.waiting a,.result a{color:var(--accent-ink);background:var(--accent)}.waiting,aside{background:var(--surface);border-color:var(--border);box-shadow:var(--shadow)}.waiting p,.versus p,.hint{color:var(--text-muted)}.board-empty{background:var(--surface-strong);border-color:var(--border)}.result{background:var(--surface-strong);border-color:var(--border)}.result b{color:var(--success)}
.app-header { display:block; max-width:none; align-items:initial; gap:initial; margin:0; }
</style>
