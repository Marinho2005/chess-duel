<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'

definePageMeta({ middleware: 'auth' })

type Player = {
  id: string
  nickname: string
  rating: number
}

type Move = {
  from: string
  to: string
  player: string
}

type GameState = {
  moves: Move[]
  current_turn: string
  fen: string
  status: string
  game_over_reason: GameOver['reason'] | null
  winner_player_id: string | null
  player_color: 'white' | 'black' | null
  white_player_id: string | null
  black_player_id: string | null
  white_player: Player | null
  black_player: Player | null
  white_time_remaining_ms: number
  black_time_remaining_ms: number
}

type MoveMade = Move & {
  new_fen: string
  current_turn: string
  is_check: boolean
  is_checkmate: boolean
  is_stalemate: boolean
  is_draw: boolean
  white_time_remaining_ms: number
  black_time_remaining_ms: number
}

type GameOver = {
  reason: 'checkmate' | 'stalemate' | 'draw' | 'timeout' | 'abandonment'
  winner_player_id: string | null
}

type RatingUpdate = {
  game_id: string
  white: { id: string; before: number; after: number }
  black: { id: string; before: number; after: number }
}

const route = useRoute()
const gameId = computed(() =>
  typeof route.params.gameId === 'string' ? route.params.gameId : 'test-game-1'
)
const auth = useAuthStore()
const from = ref('')
const to = ref('')
const moves = ref<Move[]>([])
const currentTurn = ref('white')
const fen = ref('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1')
const whiteTimeRemainingMs = ref(180_000)
const blackTimeRemainingMs = ref(180_000)
const serverWhiteTimeRemainingMs = ref(180_000)
const serverBlackTimeRemainingMs = ref(180_000)
const clockReceivedAt = ref(Date.now())
const gameStatus = ref('in_progress')
const playerId = computed(() => auth.user?.id ?? '')
const playerColor = ref<string | null>(null)
const whitePlayer = ref<Player | null>(null)
const blackPlayer = ref<Player | null>(null)
const connectionStatus = ref('Conectando...')
const errorMessage = ref('')
const gameOverMessage = ref('')
const ratingMessage = ref('')

let socket: Socket | null = null
let channel: Channel | null = null
let clockInterval: ReturnType<typeof setInterval> | null = null

onMounted(async () => {
  auth.restoreSession()

  if (!auth.token || !(await auth.fetchCurrentUser())) {
    connectionStatus.value = 'Faca login para entrar na partida.'
    return
  }

  const backendUrl = useRuntimeConfig().public.api.baseURL
  const websocketUrl = `${backendUrl.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`

  socket = new Socket(websocketUrl, { params: { token: auth.token } })
  socket.onError(() => {
    connectionStatus.value = 'Reconectando...'
  })
  socket.onClose(() => {
    connectionStatus.value = 'Reconectando...'
  })
  socket.connect()

  channel = socket.channel(`game:${gameId.value}`, {})
  channel
    .join()
    .receive('ok', (state: GameState) => {
      moves.value = state.moves
      currentTurn.value = state.current_turn
      fen.value = state.fen
      gameStatus.value = state.status
      playerColor.value = state.player_color
      whitePlayer.value = state.white_player
      blackPlayer.value = state.black_player
      syncClocks(state.white_time_remaining_ms, state.black_time_remaining_ms)
      gameOverMessage.value = state.game_over_reason
        ? formatGameOverMessage({
            reason: state.game_over_reason,
            winner_player_id: state.winner_player_id
          })
        : ''
      connectionStatus.value = `Conectado como ${auth.user?.nickname}${formatPlayerColor(state.player_color)}`

      if (state.status === 'finished') {
        stopClockInterval()
      } else {
        startClockInterval()
      }
    })
    .receive('error', (reason: unknown) => {
      connectionStatus.value = 'Falha ao entrar na partida'
      errorMessage.value = JSON.stringify(reason)
    })

  channel.on('move_made', (move: MoveMade) => {
    moves.value.push({ from: move.from, to: move.to, player: move.player })
    currentTurn.value = move.current_turn
    fen.value = move.new_fen
    syncClocks(move.white_time_remaining_ms, move.black_time_remaining_ms)
    errorMessage.value = ''
  })

  channel.on('game_over', (result: GameOver) => {
    updateDisplayedClocks()
    gameStatus.value = 'finished'
    stopClockInterval()
    gameOverMessage.value = formatGameOverMessage(result)
  })

  channel.on('rating_updated', async (rating: RatingUpdate) => {
    applyPlayerRating(rating.white)
    applyPlayerRating(rating.black)

    const ownRating = rating.white.id === playerId.value ? rating.white : rating.black
    const change = ownRating.after - ownRating.before
    ratingMessage.value = `Rating: ${ownRating.before} → ${ownRating.after} (${change >= 0 ? '+' : ''}${change})`
    await auth.fetchCurrentUser()
  })
})

onBeforeUnmount(() => {
  stopClockInterval()
  channel?.leave()
  socket?.disconnect()
})

function syncClocks(whiteTimeMs: number, blackTimeMs: number) {
  serverWhiteTimeRemainingMs.value = whiteTimeMs
  serverBlackTimeRemainingMs.value = blackTimeMs
  clockReceivedAt.value = Date.now()
  whiteTimeRemainingMs.value = whiteTimeMs
  blackTimeRemainingMs.value = blackTimeMs
}

function updateDisplayedClocks() {
  if (gameStatus.value === 'finished') {
    return
  }

  const elapsedMs = Date.now() - clockReceivedAt.value

  if (currentTurn.value === 'white') {
    whiteTimeRemainingMs.value = Math.max(0, serverWhiteTimeRemainingMs.value - elapsedMs)
    blackTimeRemainingMs.value = serverBlackTimeRemainingMs.value
  } else {
    whiteTimeRemainingMs.value = serverWhiteTimeRemainingMs.value
    blackTimeRemainingMs.value = Math.max(0, serverBlackTimeRemainingMs.value - elapsedMs)
  }
}

function startClockInterval() {
  if (clockInterval) {
    return
  }

  clockInterval = setInterval(updateDisplayedClocks, 250)
}

function applyPlayerRating(update: RatingUpdate['white']) {
  if (whitePlayer.value?.id === update.id) whitePlayer.value.rating = update.after
  if (blackPlayer.value?.id === update.id) blackPlayer.value.rating = update.after
}

function stopClockInterval() {
  if (!clockInterval) {
    return
  }

  clearInterval(clockInterval)
  clockInterval = null
}

function formatClock(timeMs: number) {
  const totalSeconds = Math.ceil(Math.max(0, timeMs) / 1000)
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60

  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
}

function sendMove() {
  errorMessage.value = ''

  if (!channel || !from.value.trim() || !to.value.trim()) {
    errorMessage.value = 'Preencha as casas de origem e destino.'
    return
  }

  channel
    .push('move', { from: from.value.trim(), to: to.value.trim() })
    .receive('ok', () => {
      from.value = ''
      to.value = ''
    })
    .receive('error', (reason: { reason?: string }) => {
      const messages: Record<string, string> = {
        illegal_move: 'Lance ilegal',
        not_your_turn: 'Ainda nao e sua vez.',
        not_a_player: 'Voce esta observando esta partida.',
        game_finished: 'A partida ja terminou.'
      }

      errorMessage.value = reason.reason ? messages[reason.reason] || reason.reason : JSON.stringify(reason)
    })
}

function formatPlayerColor(color: string | null) {
  if (color === 'white') {
    return ' (brancas)'
  }

  if (color === 'black') {
    return ' (pretas)'
  }

  return ''
}

function formatGameOverMessage(result: GameOver) {
  if (result.winner_player_id === playerId.value) {
    return `Voce venceu! ${formatGameOverReason(result.reason)}`
  }

  if (result.winner_player_id) {
    return `Voce perdeu. ${formatGameOverReason(result.reason)}`
  }

  return `Empate. ${formatGameOverReason(result.reason)}`
}

function formatGameOverReason(reason: GameOver['reason']) {
  const reasons: Record<GameOver['reason'], string> = {
    checkmate: 'Fim de jogo por xeque-mate.',
    stalemate: 'Partida encerrada por afogamento.',
    draw: 'Partida encerrada em empate.',
    timeout: 'Fim de jogo por tempo esgotado.',
    abandonment: 'Fim de jogo por abandono.'
  }

  return reasons[reason]
}

function playerName(playerId: string) {
  if (playerId === whitePlayer.value?.id) {
    return whitePlayer.value.nickname
  }

  if (playerId === blackPlayer.value?.id) {
    return blackPlayer.value.nickname
  }

  return playerId
}
</script>

<template>
  <main class="container">
    <h1>Partida em tempo real</h1>
    <NuxtLink to="/lobby" class="back-link">← Voltar ao salao</NuxtLink>
    <p v-if="!auth.token"><NuxtLink to="/">Entrar ou criar conta</NuxtLink></p>
    <p class="muted">Canal: <code>game:{{ gameId }}</code></p>
    <p>{{ connectionStatus }} · turno atual: <strong>{{ currentTurn }}</strong></p>
    <p v-if="auth.user" class="muted">Usuario: <strong>{{ auth.user.nickname }}</strong> · rating {{ auth.user.rating }} · <code>{{ auth.user.id }}</code></p>
    <div class="opponents">
      <article :class="{ active: currentTurn === 'white' }">
        <span>Brancas</span>
        <NuxtLink v-if="whitePlayer" :to="`/profile/${encodeURIComponent(whitePlayer.nickname)}`"><strong>{{ whitePlayer.nickname }}</strong></NuxtLink>
        <strong v-else>Aguardando...</strong>
        <small v-if="whitePlayer">Rating {{ whitePlayer.rating }}</small>
      </article>
      <span class="versus">×</span>
      <article :class="{ active: currentTurn === 'black' }">
        <span>Pretas</span>
        <NuxtLink v-if="blackPlayer" :to="`/profile/${encodeURIComponent(blackPlayer.nickname)}`"><strong>{{ blackPlayer.nickname }}</strong></NuxtLink>
        <strong v-else>Aguardando...</strong>
        <small v-if="blackPlayer">Rating {{ blackPlayer.rating }}</small>
      </article>
    </div>
    <div class="clocks">
      <p>Brancas: <strong>{{ formatClock(whiteTimeRemainingMs) }}</strong></p>
      <p>Pretas: <strong>{{ formatClock(blackTimeRemainingMs) }}</strong></p>
    </div>
    <p class="fen"><strong>FEN:</strong> <code>{{ fen }}</code></p>
    <p v-if="gameOverMessage" class="game-over">{{ gameOverMessage }}</p>
    <p v-if="ratingMessage" class="rating-update">{{ ratingMessage }}</p>

    <form class="move-form" @submit.prevent="sendMove">
      <label>
        Origem
        <input v-model="from" placeholder="e2" autocomplete="off">
      </label>
      <label>
        Destino
        <input v-model="to" placeholder="e4" autocomplete="off">
      </label>
      <button type="submit">Enviar lance</button>
    </form>

    <p v-if="errorMessage" class="error">{{ errorMessage }}</p>

    <section>
      <h2>Lances recebidos</h2>
      <p v-if="moves.length === 0" class="muted">Nenhum lance ainda.</p>
      <ol v-else>
        <li v-for="(move, index) in moves" :key="index">
          <strong>{{ move.from }} → {{ move.to }}</strong>
          <span class="muted"> por {{ playerName(move.player) }}</span>
        </li>
      </ol>
    </section>
  </main>
</template>

<style scoped>
.container {
  max-width: 720px;
  min-height: 100vh;
  margin: 0 auto;
  padding: 2rem 1.5rem;
  color: #e8e8ee;
  background: #0f1115;
  font-family: system-ui, sans-serif;
}
.muted { color: #9aa0aa; }
.back-link { color: #8ab4ff; }
.opponents { display: grid; grid-template-columns: 1fr auto 1fr; align-items: center; gap: 1rem; margin: 1.5rem 0; }
.opponents article { display: grid; gap: 0.25rem; padding: 1rem; background: #171a21; border: 1px solid #232835; border-radius: 12px; }
.opponents article.active { border-color: #3769d4; box-shadow: 0 0 0 1px #3769d4; }
.opponents span, .opponents small { color: #9aa0aa; }
.versus { font-size: 1.5rem; }
.clocks { display: flex; gap: 2rem; }
.move-form {
  display: flex;
  align-items: end;
  gap: 1rem;
  padding: 1.25rem;
  margin: 1.5rem 0;
  background: #171a21;
  border: 1px solid #232835;
  border-radius: 12px;
}
label { display: grid; gap: 0.4rem; }
input, button {
  padding: 0.65rem 0.8rem;
  color: inherit;
  background: #0f1115;
  border: 1px solid #3a4150;
  border-radius: 6px;
}
button { cursor: pointer; background: #2855b6; border-color: #3769d4; }
li { margin: 0.6rem 0; }
.error { color: #ff7b72; }
.fen { overflow-wrap: anywhere; }
.game-over {
  padding: 1rem;
  color: #fff;
  background: #2855b6;
  border-radius: 8px;
}
.rating-update { padding: 0.85rem 1rem; color: #dcebcf; background: #24351f; border: 1px solid #527347; border-radius: 8px; }
@media (max-width: 560px) {
  .move-form { align-items: stretch; flex-direction: column; }
}
</style>
