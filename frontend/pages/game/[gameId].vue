<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'
import type { Color, Key } from '@lichess-org/chessground/types'

definePageMeta({ middleware: 'auth' })

type Player = {
  id: string
  nickname: string
  rating: number
  avatar_url: string | null
}

type Move = {
  from: string
  to: string
  player: string
  promotion?: string | null
}

type GameOver = {
  reason: 'checkmate' | 'stalemate' | 'draw' | 'timeout' | 'abandonment'
  winner_player_id: string | null
}

type GameState = {
  moves: Move[]
  current_turn: Color
  fen: string
  status: 'waiting' | 'in_progress' | 'finished'
  game_over_reason: GameOver['reason'] | null
  winner_player_id: string | null
  player_color: Color
  white_player: Player | null
  black_player: Player | null
  is_check: boolean
  white_time_remaining_ms: number
  black_time_remaining_ms: number
  initial_time_ms: number
  increment_ms: number
}

type MoveMade = Move & {
  new_fen: string
  current_turn: Color
  is_check: boolean
  white_time_remaining_ms: number
  black_time_remaining_ms: number
}

type RatingUpdate = {
  white: { id: string; before: number; after: number }
  black: { id: string; before: number; after: number }
}

const route = useRoute()
const auth = useAuthStore()
const config = useRuntimeConfig()
const gameId = computed(() => String(route.params.gameId))

const fen = ref('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1')
const moves = ref<Move[]>([])
const currentTurn = ref<Color>('white')
const playerColor = ref<Color>('white')
const whitePlayer = ref<Player | null>(null)
const blackPlayer = ref<Player | null>(null)
const gameStatus = ref<GameState['status']>('waiting')
const isCheck = ref(false)
const connectionStatus = ref('Conectando à partida...')
const errorMessage = ref('')
const gameOverMessage = ref('')
const ratingMessage = ref('')
const pendingMove = ref(false)

const whiteTime = ref(180_000)
const blackTime = ref(180_000)
const serverWhiteTime = ref(180_000)
const serverBlackTime = ref(180_000)
const clockReceivedAt = ref(Date.now())
const initialTimeMs = ref(180_000)
const incrementMs = ref(0)

let socket: Socket | null = null
let channel: Channel | null = null
let clockInterval: ReturnType<typeof setInterval> | null = null

const lastMove = computed<[Key, Key] | null>(() => {
  const move = moves.value.at(-1)
  return move ? [move.from as Key, move.to as Key] : null
})

const topPlayer = computed(() => playerColor.value === 'white' ? blackPlayer.value : whitePlayer.value)
const bottomPlayer = computed(() => playerColor.value === 'white' ? whitePlayer.value : blackPlayer.value)
const topColor = computed<Color>(() => playerColor.value === 'white' ? 'black' : 'white')
const bottomColor = computed<Color>(() => playerColor.value)
const topTime = computed(() => topColor.value === 'white' ? whiteTime.value : blackTime.value)
const bottomTime = computed(() => bottomColor.value === 'white' ? whiteTime.value : blackTime.value)
const boardDisabled = computed(() => pendingMove.value || gameStatus.value === 'finished')
const timeControlLabel = computed(() => {
  const minutes = Math.floor(initialTimeMs.value / 60_000)
  const increment = Math.floor(incrementMs.value / 1_000)
  const category = minutes <= 1 ? 'Bullet' : minutes <= 5 ? 'Blitz' : 'Rapid'
  return `${category} ${minutes}+${increment}`
})
const timeControlDescription = computed(() => {
  const minutes = Math.floor(initialTimeMs.value / 60_000)
  const increment = Math.floor(incrementMs.value / 1_000)
  return increment > 0 ? `${minutes} min · incremento de ${increment}s` : `${minutes} min · sem incremento`
})

onMounted(async () => {
  auth.restoreSession()
  if (!auth.token || !(await auth.fetchCurrentUser())) return

  const backendUrl = config.public.api.baseURL
  const websocketUrl = `${backendUrl.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  socket = new Socket(websocketUrl, { params: { token: auth.token } })
  socket.onError(() => { connectionStatus.value = 'Reconectando...' })
  socket.onClose(() => { connectionStatus.value = 'Conexão interrompida. Reconectando...' })
  socket.connect()

  channel = socket.channel(`game:${gameId.value}`, {})
  channel.join()
    .receive('ok', applyInitialState)
    .receive('error', (reason: unknown) => {
      connectionStatus.value = 'Não foi possível entrar nesta partida.'
      errorMessage.value = formatChannelError(reason)
    })

  channel.on('move_made', applyServerMove)
  channel.on('game_over', applyGameOver)
  channel.on('rating_updated', applyRatingUpdate)
})

onBeforeUnmount(() => {
  stopClock()
  channel?.leave()
  socket?.disconnect()
})

function applyInitialState(state: GameState) {
  moves.value = state.moves
  currentTurn.value = state.current_turn
  fen.value = state.fen
  gameStatus.value = state.status
  playerColor.value = state.player_color
  whitePlayer.value = state.white_player
  blackPlayer.value = state.black_player
  isCheck.value = state.is_check
  initialTimeMs.value = state.initial_time_ms
  incrementMs.value = state.increment_ms
  syncClocks(state.white_time_remaining_ms, state.black_time_remaining_ms)
  connectionStatus.value = 'Conectado em tempo real'

  if (state.game_over_reason) {
    applyGameOver({ reason: state.game_over_reason, winner_player_id: state.winner_player_id })
  } else if (state.status === 'in_progress') {
    startClock()
  }
}

function applyServerMove(move: MoveMade) {
  moves.value.push({
    from: move.from,
    to: move.to,
    player: move.player,
    promotion: move.promotion
  })
  fen.value = move.new_fen
  currentTurn.value = move.current_turn
  isCheck.value = move.is_check
  gameStatus.value = 'in_progress'
  pendingMove.value = false
  errorMessage.value = ''
  syncClocks(move.white_time_remaining_ms, move.black_time_remaining_ms)
  startClock()
}

function sendBoardMove(move: { from: Key; to: Key; promotion?: 'q'; premove: boolean }) {
  if (!channel || boardDisabled.value) return

  pendingMove.value = true
  errorMessage.value = move.premove ? 'Enviando lance pré-movido...' : ''

  channel.push('move', { from: move.from, to: move.to, promotion: move.promotion })
    .receive('error', (reason: { reason?: string }) => {
      pendingMove.value = false
      errorMessage.value = moveError(reason.reason)
      // Alterar o estado de disabled faz o componente reaplicar o FEN oficial.
    })
}

function applyGameOver(result: GameOver) {
  updateClocks()
  gameStatus.value = 'finished'
  pendingMove.value = false
  stopClock()

  if (result.winner_player_id === auth.user?.id) {
    gameOverMessage.value = `Você venceu · ${gameOverReason(result.reason)}`
  } else if (result.winner_player_id) {
    gameOverMessage.value = `Você perdeu · ${gameOverReason(result.reason)}`
  } else {
    gameOverMessage.value = `Empate · ${gameOverReason(result.reason)}`
  }
}

async function applyRatingUpdate(rating: RatingUpdate) {
  updatePlayerRating(rating.white)
  updatePlayerRating(rating.black)
  const own = rating.white.id === auth.user?.id ? rating.white : rating.black
  const variation = own.after - own.before
  ratingMessage.value = `${own.before} → ${own.after} (${variation >= 0 ? '+' : ''}${variation})`
  await auth.fetchCurrentUser()
}

function updatePlayerRating(update: RatingUpdate['white']) {
  if (whitePlayer.value?.id === update.id) whitePlayer.value.rating = update.after
  if (blackPlayer.value?.id === update.id) blackPlayer.value.rating = update.after
}

function syncClocks(white: number, black: number) {
  serverWhiteTime.value = white
  serverBlackTime.value = black
  whiteTime.value = white
  blackTime.value = black
  clockReceivedAt.value = Date.now()
}

function updateClocks() {
  if (gameStatus.value === 'finished') return
  const elapsed = Date.now() - clockReceivedAt.value

  if (currentTurn.value === 'white') {
    whiteTime.value = Math.max(0, serverWhiteTime.value - elapsed)
    blackTime.value = serverBlackTime.value
  } else {
    whiteTime.value = serverWhiteTime.value
    blackTime.value = Math.max(0, serverBlackTime.value - elapsed)
  }
}

function startClock() {
  if (!clockInterval) clockInterval = setInterval(updateClocks, 250)
}

function stopClock() {
  if (!clockInterval) return
  clearInterval(clockInterval)
  clockInterval = null
}

function formatClock(milliseconds: number) {
  const seconds = Math.ceil(Math.max(0, milliseconds) / 1000)
  return `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`
}

function avatarUrl(player: Player | null) {
  return resolveAvatarUrl(player?.avatar_url, config.public.api.baseURL)
}

function playerName(playerId: string) {
  if (playerId === whitePlayer.value?.id) return whitePlayer.value.nickname
  if (playerId === blackPlayer.value?.id) return blackPlayer.value.nickname
  return 'Jogador'
}

function moveError(reason?: string) {
  const messages: Record<string, string> = {
    illegal_move: 'Lance ilegal. O tabuleiro foi restaurado.',
    not_your_turn: 'Ainda não é sua vez.',
    not_a_player: 'Você não faz parte desta partida.',
    game_finished: 'Esta partida já terminou.'
  }
  return messages[reason || ''] || 'O servidor rejeitou o lance.'
}

function formatChannelError(reason: unknown) {
  if (reason && typeof reason === 'object' && 'reason' in reason) {
    const value = String((reason as { reason: unknown }).reason)
    if (value === 'game_full') return 'Esta partida já possui dois jogadores.'
  }
  return 'Falha ao conectar com a partida.'
}

function gameOverReason(reason: GameOver['reason']) {
  const reasons: Record<GameOver['reason'], string> = {
    checkmate: 'xeque-mate',
    stalemate: 'afogamento',
    draw: 'empate',
    timeout: 'tempo esgotado',
    abandonment: 'abandono'
  }
  return reasons[reason]
}
</script>

<template>
  <main class="game-shell">
    <header class="game-header">
      <NuxtLink to="/lobby" class="brand"><span>♟</span> ChessDuel</NuxtLink>
      <div class="connection"><i />{{ connectionStatus }}</div>
      <NuxtLink to="/lobby" class="leave">← Voltar ao salão</NuxtLink>
    </header>

    <div class="game-layout">
      <section class="board-column">
        <article class="player-bar" :class="{ thinking: currentTurn === topColor && gameStatus !== 'finished' }">
          <img v-if="avatarUrl(topPlayer)" :src="avatarUrl(topPlayer) || ''" :alt="`Foto de ${topPlayer?.nickname}`">
          <span v-else class="avatar">{{ topPlayer?.nickname.charAt(0).toUpperCase() || '?' }}</span>
          <div><strong>{{ topPlayer?.nickname || 'Aguardando oponente' }}</strong><small>Rating {{ topPlayer?.rating || '—' }}</small></div>
          <time>{{ formatClock(topTime) }}</time>
        </article>

        <div class="board-frame">
          <GameBoard
            :fen="fen"
            :orientation="playerColor"
            :turn-color="currentTurn"
            :last-move="lastMove"
            :check="isCheck"
            :disabled="boardDisabled"
            @move="sendBoardMove"
          />
        </div>

        <article class="player-bar" :class="{ thinking: currentTurn === bottomColor && gameStatus !== 'finished' }">
          <img v-if="avatarUrl(bottomPlayer)" :src="avatarUrl(bottomPlayer) || ''" :alt="`Foto de ${bottomPlayer?.nickname}`">
          <span v-else class="avatar">{{ bottomPlayer?.nickname.charAt(0).toUpperCase() || '?' }}</span>
          <div><strong>{{ bottomPlayer?.nickname || 'Você' }}</strong><small>Rating {{ bottomPlayer?.rating || '—' }}</small></div>
          <time>{{ formatClock(bottomTime) }}</time>
        </article>
      </section>

      <aside class="match-panel">
        <div class="panel-heading">
          <span>PARTIDA RANQUEADA</span>
          <h1>Duelo em andamento</h1>
          <p>{{ timeControlLabel }} · {{ timeControlDescription }}</p>
        </div>

        <div v-if="gameOverMessage" class="result-card">
          <span>RESULTADO</span>
          <strong>{{ gameOverMessage }}</strong>
          <p v-if="ratingMessage">Novo rating: {{ ratingMessage }}</p>
        </div>

        <p v-if="errorMessage" class="error">{{ errorMessage }}</p>

        <section class="moves-panel">
          <div class="moves-title"><h2>Lances</h2><span>{{ moves.length }}</span></div>
          <ol v-if="moves.length">
            <li v-for="(move, index) in moves" :key="`${index}-${move.from}-${move.to}`">
              <span>{{ index + 1 }}</span>
              <strong>{{ move.from }} → {{ move.to }}{{ move.promotion ? `=${move.promotion.toUpperCase()}` : '' }}</strong>
              <small>{{ playerName(move.player) }}</small>
            </li>
          </ol>
          <p v-else class="empty">O primeiro lance será registrado aqui.</p>
        </section>

        <footer>
          <span v-if="gameStatus === 'finished'">Partida encerrada</span>
          <span v-else-if="currentTurn === playerColor">Sua vez de jogar</span>
          <span v-else>Oponente pensando...</span>
          <small>O servidor valida todos os lances</small>
        </footer>
      </aside>
    </div>
  </main>
</template>

<style scoped>
.game-shell { --cream: #f4eddf; --panel: #fffaf0; --line: #ddcdb5; --ink: #38281e; --brown: #925b35; min-height: 100vh; padding: 1.2rem clamp(1rem, 3vw, 2.5rem) 2rem; color: var(--ink); background-color: var(--cream); background-image: radial-gradient(#bba98e35 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
.game-header { display: grid; grid-template-columns: 1fr auto 1fr; align-items: center; max-width: 1260px; margin: 0 auto 1.2rem; }.brand { color: var(--brown); font: 700 1.65rem Georgia, serif; text-decoration: none; }.brand span { font-size: 1.2rem; }.leave { justify-self: end; color: #765944; text-decoration: none; }.leave:hover { text-decoration: underline; }.connection { display: flex; align-items: center; gap: 0.45rem; color: #6d7f5e; font-size: 0.82rem; }.connection i { width: 7px; height: 7px; background: #6c8d5c; border-radius: 50%; box-shadow: 0 0 7px #6c8d5c; }
.game-layout { display: grid; grid-template-columns: minmax(420px, 780px) minmax(290px, 360px); justify-content: center; align-items: start; gap: clamp(1.2rem, 3vw, 2.5rem); max-width: 1260px; margin: auto; }.board-column { display: grid; gap: 0.7rem; min-width: 0; }.board-frame { width: min(100%, calc(100vh - 205px)); justify-self: center; }.player-bar { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 0.8rem; min-height: 66px; padding: 0.65rem 0.85rem; background: #fffaf0c9; border: 1px solid transparent; border-radius: 13px; transition: border-color 160ms, box-shadow 160ms; }.player-bar.thinking { border-color: #b98a62; box-shadow: 0 5px 18px #6d47231b; }.player-bar img, .avatar { display: grid; width: 44px; height: 44px; place-items: center; object-fit: cover; color: white; background: var(--brown); border-radius: 50%; font-weight: 800; }.player-bar div { display: grid; }.player-bar small { color: #887261; }.player-bar time { min-width: 112px; padding: 0.45rem 0.7rem; text-align: center; background: #eadcc7; border-radius: 9px; font: 700 clamp(1.45rem, 3vw, 2.1rem)/1 ui-monospace, monospace; }
.match-panel { display: flex; min-height: min(760px, calc(100vh - 85px)); flex-direction: column; overflow: hidden; background: #fffaf0e8; border: 1px solid #e4d5bf; border-radius: 18px; box-shadow: 0 18px 40px #60401f18; }.panel-heading { padding: 1.5rem; border-bottom: 1px solid var(--line); }.panel-heading > span, .result-card > span { color: var(--brown); font-size: 0.68rem; font-weight: 800; letter-spacing: 0.11em; }.panel-heading h1 { margin: 0.35rem 0; font: 500 1.65rem Georgia, serif; }.panel-heading p { margin: 0; color: #867160; font-size: 0.86rem; }.result-card { display: grid; gap: 0.45rem; margin: 1rem; padding: 1rem; color: #f8f3e8; background: #765039; border-radius: 12px; }.result-card strong { font: 500 1.15rem Georgia, serif; }.result-card p { margin: 0; color: #e9d9c7; }.error { margin: 1rem; padding: 0.8rem; color: #9c3f2f; background: #f6ded5; border-radius: 10px; }
.moves-panel { display: flex; min-height: 0; flex: 1; flex-direction: column; padding: 1.2rem 1.5rem; }.moves-title { display: flex; align-items: center; justify-content: space-between; }.moves-title h2 { margin: 0; font: 500 1.25rem Georgia, serif; }.moves-title span { display: grid; min-width: 27px; height: 27px; place-items: center; color: #79543b; background: #eadcc7; border-radius: 50%; font-size: 0.75rem; }.moves-panel ol { display: grid; align-content: start; gap: 0.25rem; max-height: 410px; margin: 1rem 0 0; padding: 0; overflow-y: auto; list-style: none; }.moves-panel li { display: grid; grid-template-columns: 28px 1fr auto; align-items: center; gap: 0.6rem; padding: 0.55rem 0.45rem; border-bottom: 1px solid #eadfce; }.moves-panel li > span, .moves-panel small, .empty { color: #8c7867; font-size: 0.78rem; }.moves-panel strong { font-family: ui-monospace, monospace; }.empty { margin: auto; text-align: center; }.match-panel footer { display: grid; gap: 0.2rem; padding: 1rem 1.5rem; color: #6f855c; background: #eee2d0; border-top: 1px solid var(--line); }.match-panel footer small { color: #8a7766; }
@media (max-width: 900px) { .game-header { grid-template-columns: 1fr auto; }.connection { display: none; }.game-layout { grid-template-columns: minmax(0, 680px); }.board-frame { width: 100%; }.match-panel { min-height: 0; }.moves-panel ol { max-height: 260px; } }
@media (max-width: 560px) { .game-shell { padding: 0.7rem 0.55rem 1rem; }.game-header { margin: 0 0.35rem 0.7rem; }.brand { font-size: 1.25rem; }.leave { font-size: 0.78rem; }.player-bar { min-height: 55px; padding: 0.45rem 0.55rem; }.player-bar img, .avatar { width: 38px; height: 38px; }.player-bar time { min-width: 88px; font-size: 1.35rem; }.board-frame { border-radius: 5px; }.match-panel { border-radius: 13px; }.panel-heading { padding: 1.1rem; } }
</style>
