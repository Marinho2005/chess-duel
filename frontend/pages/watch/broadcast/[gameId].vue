<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'
import { ArrowLeft, ExternalLink } from 'lucide-vue-next'
import { Chess } from 'chess.js'
import type { Key } from '@lichess-org/chessground/types'
import type { BroadcastLiveGame, LiveMove } from '~/types/live-games'
import type { Evaluation } from '~/types/game-review'
import EvaluationBar from '~/components/review/EvaluationBar.vue'
import { buildReplayPositions } from '~/utils/chessMoves'
import { soundForSan } from '~/utils/gameSound'

definePageMeta({ middleware: 'auth', layout: false })

const route = useRoute()
const api = useApi()
const roundId = computed(() => typeof route.query.round === 'string' ? route.query.round : '')
let refreshTimer: ReturnType<typeof setInterval> | null = null
let disposed = false
const completed = computed(() => Boolean(game.value?.result && game.value.result !== '*'))
const auth = useAuthStore()
const config = useRuntimeConfig()
const sounds = useGameSounds()
const gameId = computed(() => String(route.params.gameId || ''))
const game = ref<BroadcastLiveGame | null>(null)
const state = ref<'connecting' | 'loaded' | 'not_found' | 'unavailable' | 'ended'>('connecting')
const viewedPly = ref<number | null>(null)
const evaluations = ref<Record<number, Evaluation>>({})
const principalVariations = ref<Record<number, string[]>>({})
const evaluatingPly = ref<number | null>(null)
const evaluationError = ref(false)
let socket: Socket | null = null
let channel: Channel | null = null
let latestReceivedPly = 0
const soundTimers: Array<ReturnType<typeof setTimeout>> = []

const replayPositions = computed(() => buildReplayPositions(game.value?.moves || [], game.value?.initial_fen || undefined))
const displayedPly = computed(() => viewedPly.value ?? game.value?.moves.length ?? 0)
const viewingHistory = computed(() => viewedPly.value !== null)
const displayedPosition = computed(() => replayPositions.value[displayedPly.value])
const displayedEvaluation = computed(() => evaluations.value[displayedPly.value] || null)
const displayedFen = computed(() => viewingHistory.value
  ? displayedPosition.value?.fen || game.value?.fen || ''
  : game.value?.fen || '')
const displayedLastMove = computed<[Key, Key] | null>(() => {
  if (viewingHistory.value) {
    const move = displayedPosition.value?.lastMove
    return move ? [move[0] as Key, move[1] as Key] : null
  }
  return game.value?.last_move
    ? [game.value.last_move.from as Key, game.value.last_move.to as Key]
    : null
})
const suggestedLine = computed(() => {
  const variation = principalVariations.value[displayedPly.value] || []
  if (!variation.length || !displayedFen.value) return ''

  try {
    const chess = new Chess(displayedFen.value)
    return variation.slice(0, 8).map((uci) => {
      const move = chess.move({
        from: uci.slice(0, 2),
        to: uci.slice(2, 4),
        promotion: uci[4] || undefined,
      })
      return move.san
    }).join(' ')
  } catch {
    return variation.slice(0, 8).join(' ')
  }
})

onMounted(async () => {
  window.addEventListener('keydown', handleHistoryKeydown)
  auth.restoreSession()
  if (!auth.token || !(await auth.fetchCurrentUser())) {
    await navigateTo('/')
    return
  }

  if (roundId.value) {
    await loadRoundGame()
    if (disposed) return
    refreshTimer = setInterval(() => { if (!completed.value) void loadRoundGame() }, 20_000)
    if (completed.value) return
  }

  const websocketUrl = `${config.public.api.baseURL.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  socket = new Socket(websocketUrl, { params: { token: auth.token } })
  socket.connect()
  socket.onError(() => { if (!game.value) state.value = 'unavailable' })
  socket.onClose(() => { if (!game.value) state.value = 'unavailable' })

  channel = socket.channel(`broadcast_watch:${gameId.value}`, {})
  channel.on('broadcast_move', applyMove)
  channel.on('broadcast_evaluation', applyEvaluation)
  channel.on('broadcast_ended', () => { if (roundId.value) void loadRoundGame(); else state.value = 'ended' })
  channel.join()
    .receive('ok', (snapshot: BroadcastLiveGame) => {
      game.value = snapshot
      latestReceivedPly = snapshot.moves.length
      state.value = 'loaded'
      requestEvaluation(snapshot.moves.length)
    })
    .receive('error', (error: { reason?: string }) => {
      if (!game.value) state.value = error.reason === 'broadcast_not_found' ? 'not_found' : 'unavailable'
    })
    .receive('timeout', () => { if (!game.value) state.value = 'unavailable' })
})

onBeforeUnmount(() => {
  disposed = true
  if (refreshTimer) clearInterval(refreshTimer)
  channel?.off('broadcast_move')
  channel?.off('broadcast_evaluation')
  channel?.off('broadcast_ended')
  channel?.leave()
  socket?.disconnect()
  window.removeEventListener('keydown', handleHistoryKeydown)
  soundTimers.forEach(clearTimeout)
  channel = null
  socket = null
})

async function loadRoundGame() {
  const result = await api.request<{ games: BroadcastLiveGame[] }>(`/api/broadcasts/rounds/${encodeURIComponent(roundId.value)}/games`)
  if (disposed) return
  const snapshot = result.data?.games.find(item => item.game_id === gameId.value)
  if (snapshot) {
    if (game.value && snapshot.moves.length < game.value.moves.length && snapshot.result === '*') return
    game.value = snapshot
    latestReceivedPly = snapshot.moves.length
    state.value = 'loaded'
    if (viewedPly.value !== null) viewedPly.value = Math.min(viewedPly.value, snapshot.moves.length)
  } else if (!game.value) {
    state.value = result.error ? 'unavailable' : 'not_found'
  }
}

function applyMove(payload: { fen: string; last_move: LiveMove | null; moves: LiveMove[] }) {
  if (!game.value || completed.value) return
  const wasAtLivePosition = viewedPly.value === null
  const newMoves = payload.moves.slice(latestReceivedPly)
  newMoves.forEach((move, index) => {
    soundTimers.push(setTimeout(() => sounds.play(soundForSan(move.san)), index * 180))
  })
  latestReceivedPly = payload.moves.length
  game.value = { ...game.value, fen: payload.fen, last_move: payload.last_move, moves: payload.moves }
  if (wasAtLivePosition) viewedPly.value = null
  state.value = 'loaded'
  requestEvaluation(payload.moves.length)
}

function selectPly(ply: number) {
  if (!game.value) return
  const target = Math.min(Math.max(ply, 0), game.value.moves.length)
  if (target === displayedPly.value) return
  viewedPly.value = target === game.value.moves.length ? null : target
  if (target > 0) sounds.play(soundForSan(game.value.moves[target - 1]?.san))
  requestEvaluation(target)
}

function requestEvaluation(ply: number) {
  if (completed.value || !channel || evaluations.value[ply]) return

  evaluatingPly.value = ply
  evaluationError.value = false
  channel.push('evaluate', { ply })
    .receive('ok', (payload: { status: 'ready' | 'pending'; ply: number; evaluation?: Evaluation; principal_variation?: string[] }) => {
      if (payload.evaluation) applyEvaluation({
        ply: payload.ply,
        evaluation: payload.evaluation,
        principal_variation: payload.principal_variation,
      })
    })
    .receive('error', () => {
      if (evaluatingPly.value === ply) evaluatingPly.value = null
      evaluationError.value = true
    })
}

function applyEvaluation(payload: { ply: number; evaluation: Evaluation; principal_variation?: string[] }) {
  evaluations.value = { ...evaluations.value, [payload.ply]: payload.evaluation }
  principalVariations.value = {
    ...principalVariations.value,
    [payload.ply]: payload.principal_variation || [],
  }
  if (evaluatingPly.value === payload.ply) evaluatingPly.value = null
  evaluationError.value = false
}

function handleHistoryKeydown(event: KeyboardEvent) {
  const target = event.target as HTMLElement | null
  if (target?.matches('input, textarea, select, button, [contenteditable="true"]')) return
  if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return
  event.preventDefault()
  selectPly(displayedPly.value + (event.key === 'ArrowRight' ? 1 : -1))
}

function playerMeta(title: string | null, rating: number | null) {
  return [title, rating].filter(value => value !== null && value !== '').join(' · ') || 'Sem rating informado'
}
</script>

<template>
  <NavigationAppHeader>
    <template #context-actions>
      <div class="header-actions">
        <button type="button" class="sound-toggle" :aria-pressed="sounds.enabled.value" :title="sounds.enabled.value ? 'Desativar sons' : 'Ativar sons'" @click="sounds.toggle">{{ sounds.enabled.value ? '🔊' : '🔇' }}<span>Sons</span></button>
        <NuxtLink class="back-link" :to="game ? { path: `/observar/torneio/${game.tournament_id}`, query: { round: game.round_id } } : '/observar'"><ArrowLeft :size="18" aria-hidden="true" /> Voltar ao torneio</NuxtLink>
      </div>
    </template>
  </NavigationAppHeader>
  <main class="watch-page" @pointerdown.once="sounds.unlock">
    <section v-if="!game" class="watch-state" :role="state === 'connecting' ? 'status' : 'alert'">
      <strong v-if="state === 'connecting'">Conectando ao broadcast…</strong>
      <template v-else-if="state === 'not_found'"><strong>Broadcast não encontrado.</strong><p>Ele pode ter sido encerrado ou removido da lista ao vivo.</p></template>
      <template v-else-if="state === 'ended'"><strong>O broadcast foi encerrado.</strong><p>Volte ao lobby para encontrar outras partidas ao vivo.</p></template>
      <template v-else><strong>Canal temporariamente indisponível.</strong><p>Tente novamente em alguns instantes.</p></template>
    </section>
    <section v-else class="watch-layout">
      <div class="board-column">
        <article class="player-bar">
          <span class="piece" aria-hidden="true">♟</span>
          <div><strong :title="game.black.name">{{ game.black.name }} <ProfileCountryFlag :code="game.black.country_code" /></strong><small>{{ playerMeta(game.black.title, game.black.rating) }}</small></div>
        </article>
        <div class="board-with-evaluation">
          <div v-if="!completed" class="evaluation-rail" :aria-busy="evaluatingPly === displayedPly" :title="evaluationError ? 'Avaliação temporariamente indisponível' : 'Avaliação Stockfish'">
            <EvaluationBar :evaluation="displayedEvaluation" orientation="white" />
            <span v-if="evaluatingPly === displayedPly" class="evaluation-loading" aria-label="Stockfish analisando">•••</span>
          </div>
          <div class="board-frame">
            <GameReadonlyBoard :fen="displayedFen" :last-move="displayedLastMove" :label="`Broadcast de ${game.white.name} contra ${game.black.name}`" />
          </div>
        </div>
        <article class="player-bar">
          <span class="piece" aria-hidden="true">♙</span>
          <div><strong :title="game.white.name">{{ game.white.name }} <ProfileCountryFlag :code="game.white.country_code" /></strong><small>{{ playerMeta(game.white.title, game.white.rating) }}</small></div>
        </article>
      </div>
      <aside class="game-panel">
        <div class="panel-heading">
          <span class="live-badge">{{ completed ? `ENCERRADA · ${game.result}` : state === 'ended' ? 'TRANSMISSÃO ENCERRADA' : '● AO VIVO' }}</span>
          <h1>{{ game.tournament }}</h1>
          <p>{{ game.round }}</p>
          <section v-if="!completed" class="suggested-line" aria-live="polite">
            <strong>Linha sugerida</strong>
            <code v-if="suggestedLine">{{ suggestedLine }}</code>
            <span v-else-if="evaluatingPly === displayedPly">Stockfish analisando…</span>
            <span v-else-if="evaluationError">Análise temporariamente indisponível.</span>
            <span v-else>Aguardando avaliação.</span>
          </section>
        </div>
        <section class="moves" aria-labelledby="moves-title">
          <div class="moves-title">
            <h2 id="moves-title">Lances</h2>
            <div>
              <button type="button" :disabled="displayedPly === 0" aria-label="Lance anterior" @click="selectPly(displayedPly - 1)">←</button>
              <button type="button" :disabled="displayedPly === game.moves.length" aria-label="Próximo lance" @click="selectPly(displayedPly + 1)">→</button>
              <button v-if="viewingHistory" type="button" @click="selectPly(game.moves.length)">{{ completed ? 'Posição final' : 'Ao vivo' }}</button>
              <span>{{ displayedPly }}/{{ game.moves.length }}</span>
            </div>
          </div>
          <div v-if="game.initial_fen && game.moves.length" class="custom-position-moves"><button v-for="(move, index) in game.moves" :key="index" type="button" :aria-pressed="displayedPly === index + 1" @click="selectPly(index + 1)">{{ move.san }}</button></div>
          <GameMoveTable v-else-if="game.moves.length" :moves="game.moves" :current-ply="displayedPly" @select="selectPly" />
          <p v-else class="empty-moves">Aguardando o primeiro lance.</p>
          <small class="keyboard-hint">Use as setas ← → do teclado para rever a partida.</small>
        </section>
        <a class="lichess-link" :href="game.lichess_url" target="_blank" rel="noopener noreferrer">Ver no Lichess <ExternalLink :size="15" aria-hidden="true" /></a>
      </aside>
    </section>
  </main>
</template>

<style scoped>
.custom-position-moves { display:flex; flex-wrap:wrap; gap:.4rem; }.custom-position-moves button { padding:.5rem; color:var(--text); background:var(--surface); border:1px solid var(--border); border-radius:5px; cursor:pointer; }.custom-position-moves button[aria-pressed="true"] { border-color:var(--accent); }
.header-actions { display:flex; align-items:center; gap:.5rem; margin-left:auto; }.back-link { display:flex; align-items:center; gap:.4rem; color:var(--text); text-decoration:none; }.back-link:hover { color:var(--accent); text-decoration:underline; }.sound-toggle { display:inline-flex; align-items:center; gap:.3rem; padding:.3rem .45rem; color:var(--text); background:transparent; border:1px solid var(--border); border-radius:8px; font:inherit; cursor:pointer; }.sound-toggle span { font-size:.72rem; }.sound-toggle:hover { color:var(--accent); background:var(--surface-hover); border-color:var(--accent); }
.watch-page { min-height:calc(100vh - 60px); padding:0 clamp(1rem,3vw,2.5rem) 1.5rem; color:var(--text); background:var(--bg); font-family:Inter,system-ui,sans-serif; }
.watch-layout { display:grid; grid-template-columns:minmax(420px,760px) minmax(290px,360px); justify-content:center; align-items:start; gap:clamp(1.2rem,3vw,2.5rem); max-width:1400px; margin:auto; }
.board-column { display:grid; width:min(100%,760px); gap:.7rem; min-width:0; justify-self:end; }.board-with-evaluation { display:flex; width:min(100%,calc(100dvh - 240px)); min-width:0; justify-self:center; align-items:stretch; gap:.55rem; }.board-frame { width:auto; min-width:0; flex:1; }.evaluation-rail { position:relative; display:flex; width:30px; min-width:30px; align-self:stretch; }.evaluation-loading { position:absolute; right:2px; bottom:6px; left:2px; z-index:5; color:#f7f4ee; font-size:.58rem; font-weight:900; letter-spacing:-.08em; text-align:center; text-shadow:0 1px 2px #000; animation:evaluation-pulse 900ms ease-in-out infinite alternate; }@keyframes evaluation-pulse { to { opacity:.35; } }
.player-bar { display:grid; grid-template-columns:auto minmax(0,1fr); align-items:center; gap:.8rem; min-height:66px; padding:.65rem .85rem; background:color-mix(in srgb,var(--surface) 94%,transparent); border:1px solid var(--border-subtle); border-radius:13px; }.player-bar .piece { display:grid; width:44px; height:44px; place-items:center; color:var(--accent-ink); background:var(--accent); border-radius:50%; font-size:1.7rem; }.player-bar div { display:grid; min-width:0; gap:.12rem; }.player-bar strong { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }.player-bar small { color:var(--text-muted); }
.game-panel { display:flex; min-height:min(760px,calc(100vh - 85px)); flex-direction:column; overflow:hidden; background:color-mix(in srgb,var(--surface) 96%,transparent); border:1px solid var(--border); border-radius:18px; box-shadow:var(--shadow); }.panel-heading { padding:1.5rem; border-bottom:1px solid var(--border); }.panel-heading h1 { margin:.55rem 0 .3rem; font:500 1.55rem Georgia,serif; }.panel-heading>p { margin:0; color:var(--text-muted); }.live-badge { display:inline-block; padding:.3rem .5rem; color:var(--danger); background:var(--danger-soft); border-radius:999px; font-size:.68rem; font-weight:800; letter-spacing:.05em; }
.suggested-line { display:grid; gap:.32rem; margin-top:1rem; padding:.72rem .8rem; background:var(--surface-strong); border:1px solid var(--border-subtle); border-radius:9px; }.suggested-line strong { color:var(--text); font-size:.72rem; letter-spacing:.04em; text-transform:uppercase; }.suggested-line code,.suggested-line span { color:var(--text-muted); font:500 .82rem/1.45 ui-monospace,SFMono-Regular,Menlo,monospace; overflow-wrap:anywhere; }.suggested-line code { color:var(--text); }
.moves { display:flex; min-height:0; flex:1; flex-direction:column; gap:.85rem; padding:1.2rem 1.5rem; }.moves-title { display:flex; align-items:center; justify-content:space-between; gap:.6rem; }.moves-title h2 { margin:0; font:500 1.25rem Georgia,serif; }.moves-title>div { display:flex; align-items:center; gap:.3rem; }.moves-title button { min-width:28px; height:28px; padding:0 .45rem; color:var(--accent); background:var(--surface-strong); border:1px solid var(--border); border-radius:7px; font-size:.7rem; font-weight:800; cursor:pointer; }.moves-title button:disabled { opacity:.4; cursor:default; }.moves-title span { display:grid; min-width:42px; height:28px; place-items:center; color:var(--text-muted); background:var(--surface-strong); border-radius:999px; font-size:.7rem; }.empty-moves { margin:auto; color:var(--text-muted); text-align:center; }.keyboard-hint { color:var(--text-muted); font-size:.7rem; text-align:center; }.lichess-link { display:flex; align-items:center; justify-content:center; gap:.4rem; padding:1rem; color:var(--accent); border-top:1px solid var(--border); font-weight:700; text-decoration:none; }.lichess-link:hover { background:var(--surface-hover); }
.watch-state { display:grid; min-height:65vh; place-content:center; justify-items:center; gap:.5rem; color:var(--text-muted); text-align:center; }.watch-state strong { color:var(--text); font-size:1.2rem; }.watch-state p { margin:0; }
@media (max-width:900px) { .watch-layout { grid-template-columns:minmax(0,720px); }.board-with-evaluation { width:100%; }.game-panel { min-height:0; }.moves { min-height:320px; } }
@media (max-width:560px) { .watch-page { min-height:calc(100vh - 58px); padding:0 .55rem 1rem; }.back-link { font-size:.78rem; }.sound-toggle span { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0,0,0,0); }.player-bar { min-height:55px; padding:.45rem .55rem; }.player-bar .piece { width:38px; height:38px; }.board-with-evaluation { gap:.35rem; }.evaluation-rail { width:23px; min-width:23px; }.game-panel { border-radius:13px; }.panel-heading { padding:1.1rem; }.moves { padding:1rem; }.keyboard-hint { display:none; } }
</style>
