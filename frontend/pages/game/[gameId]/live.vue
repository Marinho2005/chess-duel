<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'
import type { Color, Key } from '@lichess-org/chessground/types'
import { createGameSoundGate, soundForMove, soundForSan } from '~/utils/gameSound'
import { buildReplayPositions } from '~/utils/chessMoves'
import { analysisAction as resolveAnalysisAction, type AnalysisStatus } from '~/utils/postGameAnalysis'
import { readBoardLayoutSize, writeBoardLayoutSize, type BoardLayoutSize } from '~/utils/boardLayout'

definePageMeta({ middleware: 'game-session', layout: false })

type Player = {
  id: string
  nickname: string
  rating: number | null
  avatar_url: string | null
  guest?: boolean
  bot?: boolean
  persona?: string
  difficulty?: string
  country_code?: string | null
}

type Move = {
  from: string
  to: string
  player: string
  promotion?: string | null
  captured?: string | null
  san?: string | null
}

type GameOver = {
  reason: 'checkmate' | 'stalemate' | 'draw' | 'timeout' | 'abandonment' | 'resignation' | 'aborted'
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
  guest_game: boolean
  bot_game: boolean
  bot_id: string | null
  preparation_ends_at: string | null
  review_game_id: string | null
  rematch: { status: 'idle' | 'waiting' | 'incoming' | 'started'; game_id?: string }
}

type MoveMade = Move & {
  new_fen: string
  current_turn: Color
  is_check: boolean
  is_checkmate: boolean
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
// Nesta rota, gameId é Game.game_id: o identificador público usado pelo GameServer e pelo tópico Phoenix.
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
const guestGame = ref(false)
const botGame = ref(false)
const reviewGameId = ref<string | null>(null)
const analysisStatus = ref<AnalysisStatus>('idle')
const openingAnalysis = ref(false)
const confirmingResignation = ref(false)
const rematchState = ref<'idle' | 'bot_offer' | 'incoming' | 'waiting' | 'declined' | 'starting'>('idle')
const preparationEndsAt = ref<number | null>(null)
const preparationSeconds = ref(0)
const boardLayoutSize = ref<BoardLayoutSize>('standard')
const viewedPly = ref<number | null>(null)

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
const sounds = useGameSounds()
const soundGate = createGameSoundGate()

const replayPositions = computed(() => buildReplayPositions(moves.value))
const displayedPly = computed(() => viewedPly.value ?? moves.value.length)
const displayedPosition = computed(() => replayPositions.value[displayedPly.value] || replayPositions.value.at(-1))
const displayedFen = computed(() => viewedPly.value === null ? fen.value : displayedPosition.value?.fen || fen.value)
const displayedTurn = computed<Color>(() => viewedPly.value === null ? currentTurn.value : displayedPosition.value?.turn || currentTurn.value)
const lastMove = computed<[Key, Key] | null>(() => {
  const selected = viewedPly.value === null
    ? moves.value.at(-1) ? [moves.value.at(-1)!.from, moves.value.at(-1)!.to] : null
    : displayedPosition.value?.lastMove
  return selected ? [selected[0] as Key, selected[1] as Key] : null
})
const viewingHistory = computed(() => viewedPly.value !== null)

const topPlayer = computed(() => playerColor.value === 'white' ? blackPlayer.value : whitePlayer.value)
const bottomPlayer = computed(() => playerColor.value === 'white' ? whitePlayer.value : blackPlayer.value)
const botPlayer = computed(() => whitePlayer.value?.bot ? whitePlayer.value : blackPlayer.value?.bot ? blackPlayer.value : null)
const topColor = computed<Color>(() => playerColor.value === 'white' ? 'black' : 'white')
const bottomColor = computed<Color>(() => playerColor.value)
const topTime = computed(() => topColor.value === 'white' ? whiteTime.value : blackTime.value)
const bottomTime = computed(() => bottomColor.value === 'white' ? whiteTime.value : blackTime.value)
const boardDisabled = computed(() => viewingHistory.value || pendingMove.value || gameStatus.value !== 'in_progress')
const postGameAnalysisAction = computed(() => resolveAnalysisAction(gameStatus.value, guestGame.value, reviewGameId.value, analysisStatus.value))
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
  boardLayoutSize.value = readBoardLayoutSize(localStorage)
  auth.restoreSession()
  if (!auth.token || (!auth.isGuest && !(await auth.fetchCurrentUser()))) return

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
  channel.on('game_started', applyGameStarted)
  channel.on('rematch_offered', applyRematchOffer)
  channel.on('rematch_declined', () => { rematchState.value = 'declined' })
  channel.on('rematch_expired', () => { rematchState.value = 'idle' })
  channel.on('rematch_started', (payload: { game_id: string }) => { void openRematch(payload.game_id) })
  window.addEventListener('keydown', handleLiveHistoryKeydown)
})

function setBoardLayoutSize(size: BoardLayoutSize) {
  boardLayoutSize.value = size
  writeBoardLayoutSize(localStorage, size)
}

onBeforeUnmount(() => {
  stopClock()
  channel?.leave()
  socket?.disconnect()
  window.removeEventListener('keydown', handleLiveHistoryKeydown)
})

function selectLivePly(ply: number) {
  const target = Math.min(Math.max(ply, 0), moves.value.length)
  if (target === displayedPly.value) return
  viewedPly.value = target === moves.value.length ? null : target
  if (target > 0) sounds.play(soundForSan(moves.value[target - 1]?.san))
}

function handleLiveHistoryKeydown(event: KeyboardEvent) {
  const target = event.target as HTMLElement | null
  if (target?.matches('input, textarea, select, button, [contenteditable="true"]')) return
  if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return
  event.preventDefault()
  selectLivePly(displayedPly.value + (event.key === 'ArrowRight' ? 1 : -1))
}

function applyInitialState(state: GameState) {
  moves.value = state.moves
  soundGate.sync(state.moves.length)
  currentTurn.value = state.current_turn
  fen.value = state.fen
  gameStatus.value = state.status
  playerColor.value = state.player_color
  whitePlayer.value = state.white_player
  blackPlayer.value = state.black_player
  isCheck.value = state.is_check
  initialTimeMs.value = state.initial_time_ms
  incrementMs.value = state.increment_ms
  guestGame.value = state.guest_game
  botGame.value = state.bot_game
  reviewGameId.value = state.review_game_id
  applyInitialRematch(state.rematch)
  preparationEndsAt.value = state.preparation_ends_at ? Date.parse(state.preparation_ends_at) : null
  updatePreparationCountdown()
  syncClocks(state.white_time_remaining_ms, state.black_time_remaining_ms)
  connectionStatus.value = 'Conectado em tempo real'

  if (state.game_over_reason) {
    applyGameOver({ reason: state.game_over_reason, winner_player_id: state.winner_player_id }, true)
  } else if (state.status === 'in_progress') {
    startClock()
  } else if (state.status === 'waiting') {
    startClock()
  }
}

function applyServerMove(move: MoveMade) {
  const previous = moves.value.at(-1)
  if (fen.value === move.new_fen || (previous?.from === move.from && previous?.to === move.to && previous?.promotion === move.promotion)) return

  moves.value.push({
    from: move.from,
    to: move.to,
    player: move.player,
    promotion: move.promotion,
    captured: move.captured,
    san: move.san
  })
  fen.value = move.new_fen
  currentTurn.value = move.current_turn
  isCheck.value = move.is_check
  gameStatus.value = 'in_progress'
  pendingMove.value = false
  errorMessage.value = ''
  syncClocks(move.white_time_remaining_ms, move.black_time_remaining_ms)
  startClock()
  if (soundGate.acceptMove(moves.value.length, sounds.enabled.value)) {
    sounds.play(soundForMove(move))
  }
}

function applyGameStarted(state: Pick<GameState, 'status' | 'white_time_remaining_ms' | 'black_time_remaining_ms'>) {
  gameStatus.value = state.status
  preparationSeconds.value = 0
  syncClocks(state.white_time_remaining_ms, state.black_time_remaining_ms)
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

function applyGameOver(result: GameOver, silent = false) {
  updateClocks()
  gameStatus.value = 'finished'
  pendingMove.value = false
  confirmingResignation.value = false
  stopClock()
  if (!silent && soundGate.acceptGameOver(sounds.enabled.value)) {
    sounds.play('gameOver')
  }

  if (result.reason === 'aborted') {
    gameOverMessage.value = 'Partida abortada · sem resultado'
  } else if (result.winner_player_id === auth.identityId) {
    gameOverMessage.value = `Você venceu · ${gameOverReason(result.reason)}`
  } else if (result.winner_player_id) {
    gameOverMessage.value = `Você perdeu · ${gameOverReason(result.reason)}`
  } else {
    gameOverMessage.value = `Empate · ${gameOverReason(result.reason)}`
  }

  void refreshAnalysisStatus()
  if (botGame.value && rematchState.value === 'idle') rematchState.value = 'bot_offer'
}

function applyInitialRematch(rematch: GameState['rematch']) {
  if (rematch.status === 'started' && rematch.game_id) {
    void openRematch(rematch.game_id)
  } else if (rematch.status === 'incoming') {
    rematchState.value = 'incoming'
  } else if (rematch.status === 'waiting') {
    rematchState.value = 'waiting'
  }
}

function applyRematchOffer(payload: { requester_player_id: string }) {
  rematchState.value = payload.requester_player_id === auth.identityId ? 'waiting' : 'incoming'
}

function requestRematch() { pushRematch('request_rematch') }
function acceptRematch() { pushRematch(botGame.value ? 'accept_bot_rematch' : 'accept_rematch') }

function declineRematch() {
  if (botGame.value) {
    rematchState.value = 'declined'
    return
  }
  pushRematch('decline_rematch')
}

function pushRematch(event: 'request_rematch' | 'accept_rematch' | 'decline_rematch' | 'accept_bot_rematch') {
  if (!channel || rematchState.value === 'starting') return
  if (event.includes('accept')) rematchState.value = 'starting'

  channel.push(event, {})
    .receive('ok', (payload: { status?: string; game_id?: string }) => {
      if (payload?.game_id) void openRematch(payload.game_id)
      else if (event === 'request_rematch') rematchState.value = 'waiting'
      else if (event === 'decline_rematch') rematchState.value = 'declined'
    })
    .receive('error', () => {
      rematchState.value = botGame.value ? 'bot_offer' : 'idle'
      errorMessage.value = 'Não foi possível iniciar a revanche.'
    })
}

async function openRematch(nextGameId: string) {
  rematchState.value = 'starting'
  await navigateTo(`/game/${nextGameId}/live`)
}

async function refreshAnalysisStatus() {
  if (auth.isGuest || !reviewGameId.value || !auth.token) return
  analysisStatus.value = 'checking'
  try {
    const response = await $fetch<{ status: 'pending' | 'processing' | 'completed' | 'failed' }>(`/api/games/${reviewGameId.value}/analysis`, {
      baseURL: config.public.api.baseURL,
      headers: { Authorization: `Bearer ${auth.token}` }
    })
    analysisStatus.value = response.status
  } catch (requestError) {
    const status = (requestError as { status?: number; statusCode?: number }).statusCode || (requestError as { status?: number }).status
    analysisStatus.value = status === 404 ? 'missing' : 'failed'
  }
}

async function openAnalysis() {
  if (gameStatus.value !== 'finished' || !reviewGameId.value || !auth.token || openingAnalysis.value) return
  openingAnalysis.value = true
  try {
    const response = await $fetch<{ status: 'pending' | 'processing' | 'completed' | 'failed' }>(`/api/games/${reviewGameId.value}/analyze`, {
      baseURL: config.public.api.baseURL,
      method: 'POST',
      headers: { Authorization: `Bearer ${auth.token}` }
    })
    analysisStatus.value = response.status
    await navigateTo(`/game/${reviewGameId.value}/review`)
  } catch {
    errorMessage.value = 'Não foi possível iniciar a análise desta partida.'
    openingAnalysis.value = false
  }
}

async function applyRatingUpdate(rating: RatingUpdate) {
  if (auth.isGuest) return

  updatePlayerRating(rating.white)
  updatePlayerRating(rating.black)
  const own = rating.white.id === auth.identityId ? rating.white : rating.black
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
  updatePreparationCountdown()
  if (gameStatus.value === 'finished') return
  if (gameStatus.value === 'waiting') return
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

function botPortrait(player: Player | null) {
  if (!player?.bot) return null
  const id = player.id.replace(/^bot:/, '')
  return ['clark', 'jonathan', 'renan', 'boris', 'terminator'].includes(id) ? `/bots/${id}.webp` : null
}

function playerSubtitle(player: Player | null) {
  if (player?.bot) return `Bot · força aproximada ${player.rating}`
  return player?.guest ? 'Convidado · sem rating' : `Rating ${player?.rating ?? '—'}`
}

function updatePreparationCountdown() {
  if (gameStatus.value !== 'waiting' || !preparationEndsAt.value) return
  preparationSeconds.value = Math.max(0, Math.ceil((preparationEndsAt.value - Date.now()) / 1000))
}

function abortGame() {
  channel?.push('abort', {}).receive('error', () => { errorMessage.value = 'O período para abortar já terminou.' })
}

function resignGame() {
  confirmingResignation.value = false
  channel?.push('resign', {}).receive('error', () => { errorMessage.value = 'Não foi possível desistir desta partida.' })
}

async function leaveGame() {
  if (auth.isGuest) {
    await auth.logOut()
    await navigateTo('/')
  } else {
    await navigateTo('/lobby')
  }
}

async function exitToPlay() {
  channel?.leave()
  if (auth.isGuest) {
    await auth.logOut()
    await navigateTo('/')
  } else {
    await navigateTo('/play')
  }
}

function moveError(reason?: string) {
  const messages: Record<string, string> = {
    illegal_move: 'Lance ilegal. O tabuleiro foi restaurado.',
    not_your_turn: 'Ainda não é sua vez.',
    not_a_player: 'Você não faz parte desta partida.',
    game_finished: 'Esta partida já terminou.',
    game_preparing: 'A partida ainda está nos 10 segundos de preparação.'
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
    abandonment: 'abandono',
    resignation: 'desistência',
    aborted: 'partida abortada'
  }
  return reasons[reason]
}
</script>

<template>
  <NavigationAppHeader>
    <template #context-actions>
      <div class="header-actions">
        <fieldset class="layout-size" aria-label="Tamanho do tabuleiro">
          <legend>Tabuleiro</legend>
          <button v-for="option in [{value:'compact',label:'P'},{value:'standard',label:'M'},{value:'large',label:'G'}]" :key="option.value" type="button" :class="{ active: boardLayoutSize === option.value }" :aria-pressed="boardLayoutSize === option.value" @click="setBoardLayoutSize(option.value as BoardLayoutSize)">{{ option.label }}</button>
        </fieldset>
        <button type="button" class="sound-toggle" :aria-pressed="sounds.enabled.value" :title="sounds.enabled.value ? 'Desativar sons' : 'Ativar sons'" @click="sounds.toggle">
          {{ sounds.enabled.value ? '🔊' : '🔇' }}<span>Sons</span>
        </button>
        <button type="button" class="leave" @click="leaveGame">← {{ auth.isGuest ? 'Sair da sessão' : 'Voltar ao salão' }}</button>
      </div>
    </template>
  </NavigationAppHeader>
  <main class="game-shell" :class="`layout-${boardLayoutSize}`" @pointerdown.once="sounds.unlock">
    <div class="game-layout">
      <section class="board-column">
        <article class="player-bar" :class="{ thinking: currentTurn === topColor && gameStatus !== 'finished' }">
          <img v-if="botPortrait(topPlayer)" :src="botPortrait(topPlayer) || ''" :alt="`Retrato de ${topPlayer?.nickname}`">
          <img v-else-if="avatarUrl(topPlayer)" :src="avatarUrl(topPlayer) || ''" :alt="`Foto de ${topPlayer?.nickname}`">
          <span v-else class="avatar">{{ topPlayer?.nickname.charAt(0).toUpperCase() || '?' }}</span>
          <div><strong>{{ topPlayer?.nickname || 'Aguardando oponente' }} <ProfileCountryFlag :code="topPlayer?.country_code" /> <em v-if="topPlayer?.guest">Convidado</em><em v-if="topPlayer?.bot" class="bot-tag">Bot</em></strong><small>{{ playerSubtitle(topPlayer) }}</small></div>
          <time>{{ formatClock(topTime) }}</time>
        </article>

        <div class="board-frame">
          <GameBoard
            :fen="displayedFen"
            :orientation="playerColor"
            :turn-color="displayedTurn"
            :last-move="lastMove"
            :check="isCheck"
            :disabled="boardDisabled"
            @move="sendBoardMove"
          />
          <div v-if="gameOverMessage" class="result-overlay" role="dialog" aria-modal="true" aria-labelledby="game-result-title">
            <div class="result-card">
              <span>RESULTADO DA PARTIDA</span>
              <strong id="game-result-title">{{ gameOverMessage }}</strong>
              <p v-if="ratingMessage">Novo rating: {{ ratingMessage }}</p>
              <p v-if="guestGame">Crie uma conta para salvar seu histórico e disputar rating nas próximas partidas.</p>
              <button v-if="postGameAnalysisAction === 'button'" type="button" :disabled="openingAnalysis" @click="openAnalysis">{{ openingAnalysis ? 'Abrindo análise…' : 'Analisar partida' }}</button>
              <span v-else-if="postGameAnalysisAction === 'processing'" class="analysis-progress">{{ analysisStatus === 'checking' ? 'Consultando análise…' : 'Análise em processamento…' }}</span>

              <div class="rematch-card">
                <template v-if="botGame && rematchState === 'bot_offer'">
                  <span class="rematch-dialogue">{{ botPlayer?.nickname || 'O bot' }} inclina uma peça e pergunta: “Outra partida?”</span>
                  <div><button type="button" @click="acceptRematch">Aceitar revanche</button><button type="button" class="quiet" @click="declineRematch">Agora não</button></div>
                </template>
                <template v-else-if="!botGame && rematchState === 'idle'">
                  <button type="button" @click="requestRematch">Pedir revanche</button>
                </template>
                <template v-else-if="rematchState === 'incoming'">
                  <span class="rematch-dialogue">Seu oponente quer jogar novamente.</span>
                  <div><button type="button" @click="acceptRematch">Aceitar revanche</button><button type="button" class="quiet" @click="declineRematch">Recusar</button></div>
                </template>
                <span v-else-if="rematchState === 'waiting'" class="rematch-dialogue">Pedido de revanche enviado. Aguardando resposta…</span>
                <span v-else-if="rematchState === 'starting'" class="rematch-dialogue">Preparando a revanche…</span>
                <span v-else-if="rematchState === 'declined'" class="rematch-dialogue">Revanche recusada.</span>

                <button v-if="rematchState !== 'starting'" type="button" @click="exitToPlay">Sair</button>
              </div>
            </div>
          </div>
        </div>

        <article class="player-bar" :class="{ thinking: currentTurn === bottomColor && gameStatus !== 'finished' }">
          <img v-if="botPortrait(bottomPlayer)" :src="botPortrait(bottomPlayer) || ''" :alt="`Retrato de ${bottomPlayer?.nickname}`">
          <img v-else-if="avatarUrl(bottomPlayer)" :src="avatarUrl(bottomPlayer) || ''" :alt="`Foto de ${bottomPlayer?.nickname}`">
          <span v-else class="avatar">{{ bottomPlayer?.nickname.charAt(0).toUpperCase() || '?' }}</span>
          <div><strong>{{ bottomPlayer?.nickname || 'Você' }} <ProfileCountryFlag :code="bottomPlayer?.country_code" /> <em v-if="bottomPlayer?.guest">Convidado</em><em v-if="bottomPlayer?.bot" class="bot-tag">Bot</em></strong><small>{{ playerSubtitle(bottomPlayer) }}</small></div>
          <time>{{ formatClock(bottomTime) }}</time>
        </article>
      </section>

      <aside class="match-panel">
        <div class="panel-heading">
          <span>{{ botGame ? 'PARTIDA CASUAL · CONTRA BOT' : guestGame ? 'PARTIDA CASUAL · CONVIDADOS' : 'PARTIDA RANQUEADA' }}</span>
          <h1>Duelo em andamento</h1>
          <p>{{ timeControlLabel }} · {{ timeControlDescription }}</p>
        </div>

        <p v-if="errorMessage" class="error">{{ errorMessage }}</p>

        <section v-if="gameStatus === 'waiting'" class="preparation-card">
          <span>PREPARAÇÃO</span>
          <strong>{{ preparationSeconds }}</strong>
          <p>Os relógios estão congelados. A partida começa automaticamente.</p>
          <button type="button" @click="abortGame">Abortar partida</button>
        </section>

        <section class="moves-panel">
          <div class="moves-title"><h2>Lances</h2><div><button v-if="viewingHistory" type="button" @click="selectLivePly(moves.length)">Voltar ao vivo</button><span>{{ displayedPly }}/{{ moves.length }}</span></div></div>
          <GameMoveTable v-if="moves.length" :moves="moves" :current-ply="displayedPly" @select="selectLivePly" />
          <p v-else class="empty">O primeiro lance será registrado aqui.</p>
        </section>

        <div v-if="gameStatus === 'in_progress'" class="game-actions" aria-live="polite">
          <template v-if="confirmingResignation">
            <span>Confirmar desistência?</span>
            <button type="button" class="cancel-resign" @click="confirmingResignation = false">Cancelar</button>
            <button type="button" class="confirm-resign" @click="resignGame">Confirmar</button>
          </template>
          <button v-else type="button" @click="confirmingResignation = true">Desistir</button>
        </div>

        <footer>
          <span v-if="gameStatus === 'finished'">Partida encerrada</span>
          <span v-else-if="gameStatus === 'waiting'">Preparação · relógios pausados</span>
          <span v-else-if="currentTurn === playerColor">Sua vez de jogar</span>
          <span v-else>Oponente pensando...</span>
          <small>O servidor valida todos os lances</small>
        </footer>
      </aside>
    </div>
  </main>
</template>

<style scoped>
.game-shell { --cream: #f4eddf; --panel: #fffaf0; --line: #ddcdb5; --ink: #38281e; --brown: #6f4528; --board-limit: 720px; --avatar-size: 44px; --bot-emote-scale: .9565; min-height: calc(100vh - 60px); padding: 0 clamp(1rem, 3vw, 2.5rem) 1.5rem; color: var(--ink); background-color: var(--cream); background-image: radial-gradient(#bba98e35 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: var(--font-sans); }.game-shell.layout-compact { --board-limit: 560px; --avatar-size: 38px; --bot-emote-scale: .8261; }.game-shell.layout-large { --board-limit: 820px; --avatar-size: 50px; --bot-emote-scale: 1.087; }
.header-actions { display: flex; align-items: center; gap: .5rem; margin-left: auto; }.leave,.sound-toggle { padding: 0; color: var(--text); background: transparent; border: 0; font: inherit; cursor: pointer; }.leave:hover { color: var(--accent); text-decoration: underline; }.sound-toggle { display: inline-flex; align-items: center; gap: .3rem; padding: .3rem .45rem; border: 1px solid var(--border); border-radius: 8px; transition: background 150ms ease, color 150ms ease, border-color 150ms ease; }.sound-toggle span { font-size: .72rem; }.sound-toggle:hover { color: var(--accent); background: var(--surface-hover); border-color: var(--accent); }.layout-size { display: flex; align-items: center; gap: .12rem; margin: 0; padding: .14rem; border: 1px solid var(--border); border-radius: 8px; }.layout-size legend { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); }.layout-size button { display: grid; width: 25px; height: 25px; place-items: center; padding: 0; color: var(--text-muted); background: transparent; border: 0; border-radius: 6px; font: 800 .66rem var(--font-sans); cursor: pointer; }.layout-size button:hover,.layout-size button.active { color: var(--accent-ink); background: var(--accent); }
.game-layout { display: grid; grid-template-columns: minmax(420px, var(--board-limit)) minmax(290px, 360px); justify-content: center; align-items: start; gap: clamp(1.2rem, 3vw, 2.5rem); max-width: 1360px; margin: auto; }.board-column { display: grid; width: min(100%, var(--board-limit)); gap: 0.7rem; min-width: 0; justify-self: end; }.board-frame { position:relative; width: min(100%, calc(100dvh - 280px)); justify-self: center; }.layout-compact .board-column { width: min(100%, 530px); gap: .35rem; }.layout-compact .board-frame { width: min(100%, 510px); }.layout-compact .player-bar { min-height: calc(var(--avatar-size) + 16px); padding: .45rem .7rem; }.player-bar { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 0.8rem; min-height: calc(var(--avatar-size) + 22px); padding: 0.65rem 0.85rem; background: #fffaf0c9; border: 1px solid transparent; border-radius: 13px; transition: border-color 160ms, box-shadow 160ms; }.player-bar.thinking { border-color: #b98a62; box-shadow: 0 5px 18px #6d47231b; }.player-bar img, .avatar { display: grid; width: var(--avatar-size); height: var(--avatar-size); place-items: center; object-fit: cover; color: white; background: var(--brown); border-radius: 50%; font-weight: 800; }.player-bar div { display: grid; }.player-bar small { color: #887261; }.player-bar time { min-width: 112px; padding: 0.45rem 0.7rem; text-align: center; background: #eadcc7; border-radius: 9px; font: 700 clamp(1.45rem, 3vw, 2.1rem)/1 var(--font-mono); }
.player-bar em { display: inline-block; margin-left: .35rem; padding: .15rem .4rem; color: #7f5130; background: #ead7bc; border-radius: 999px; font-size: .62rem; font-style: normal; text-transform: uppercase; letter-spacing: .06em; }
.player-bar em.bot-tag { color: #fffaf0; background: #6f4528; }
.match-panel { display: flex; min-height: min(760px, calc(100vh - 85px)); flex-direction: column; overflow: hidden; background: #fffaf0e8; border: 1px solid #e4d5bf; border-radius: 18px; box-shadow: 0 18px 40px #6f452818; }.panel-heading { padding: 1.5rem; border-bottom: 1px solid var(--line); }.panel-heading > span { color: var(--brown); font-size: 0.68rem; font-weight: 800; letter-spacing: 0.11em; }.panel-heading h1 { margin: 0.35rem 0; font: 500 1.65rem var(--font-serif); }.panel-heading p { margin: 0; color: #867160; font-size: 0.86rem; }.result-overlay { position:absolute; z-index:10; inset:0; display:grid; place-items:center; padding:clamp(.8rem,3vw,1.5rem); background:#38281e94; border-radius:7px; backdrop-filter:blur(2px); }.result-card { display:grid; width:min(100%,430px); gap:.75rem; padding:clamp(1.15rem,3vw,1.65rem); color:var(--ink); background:#fffaf0f5; border:1px solid #d8c3a6; border-radius:18px; box-shadow:0 24px 60px #2c1b1166; }.result-card>span:first-child { color:var(--brown); font-size:.65rem; font-weight:900; letter-spacing:.13em; }.result-card>strong { font:600 clamp(1.25rem,3vw,1.65rem)/1.25 var(--font-serif); }.result-card>p { margin:0; color:#806d5d; font-size:.85rem; line-height:1.45; }.result-card>button,.rematch-card button { min-height:44px; padding:.7rem .9rem; color:#fffaf0; background:var(--brown); border:1px solid var(--brown); border-radius:10px; font-weight:800; cursor:pointer; transition:transform 150ms ease,background 150ms ease; }.result-card>button:hover,.rematch-card button:hover { background:#805437; transform:translateY(-1px); }.result-card button:disabled { opacity:.65; cursor:wait; }.analysis-progress { padding:.7rem; color:#6f4528; background:#f0e2ce; border-radius:9px; font-size:.8rem; text-align:center; }
.rematch-card { display:grid; gap:.7rem; margin-top:.15rem; padding-top:.9rem; border-top:1px solid #dfcfb8; }.rematch-card>div { display:grid; grid-template-columns:1fr auto; gap:.55rem; }.rematch-dialogue { color:#5f4838; font-size:.86rem; line-height:1.5; }.result-card .rematch-card button { margin:0; }.result-card .rematch-card button.quiet { color:#6f4528; background:transparent; border-color:#caaa82; }.result-card .rematch-card button.quiet:hover { background:#f0e2ce; }
.preparation-card { display: grid; justify-items: center; gap: .55rem; margin: 1rem; padding: 1.1rem; text-align: center; background: #f2e5d2; border: 1px solid #d8c3a6; border-radius: 13px; }.preparation-card > span { color: #6f4528; font-size: .68rem; font-weight: 800; letter-spacing: .12em; }.preparation-card strong { display: grid; width: 58px; height: 58px; place-items: center; color: white; background: #6f4528; border-radius: 50%; font: 700 1.7rem var(--font-mono); }.preparation-card p { margin: 0; color: #806d5d; font-size: .82rem; line-height: 1.45; }.preparation-card button, .game-actions button { padding: .58rem .8rem; color: #fffaf0; background: #7f5130; border: 1px solid #7f5130; border-radius: 8px; font-weight: 700; cursor: pointer; transition: background 150ms ease, border-color 150ms ease, transform 150ms ease; }.preparation-card button:hover, .game-actions button:hover { background: #6f4528; border-color: #6f4528; transform: translateY(-1px); }.game-actions { display: flex; min-height: 50px; align-items: center; justify-content: flex-end; gap: .4rem; padding: .55rem 1.2rem 0; }.game-actions > span { margin-right: auto; color: #806d5d; font-size: .76rem; }.game-actions .cancel-resign { color: #7f5130; background: transparent; border-color: #d8c7af; }.game-actions .cancel-resign:hover { color: #6f4528; background: #efe2ce; }.game-actions .confirm-resign { color: #fffaf0; background: #8e3f32; border-color: #8e3f32; }
.moves-panel { display: flex; min-height: 0; flex: 1; flex-direction: column; padding: 1.2rem 1.5rem; }.moves-title { display: flex; align-items: center; justify-content: space-between; }.moves-title h2 { margin: 0; font: 500 1.25rem var(--font-serif); }.moves-title > div { display: flex; align-items: center; gap: .4rem; }.moves-title button { padding: .3rem .5rem; color: #6f4528; background: #fffaf0; border: 1px solid #d8c4aa; border-radius: 7px; font-size: .68rem; font-weight: 800; cursor: pointer; }.moves-title span { display: grid; min-width: 38px; height: 27px; padding: 0 .35rem; place-items: center; color: #79543b; background: #eadcc7; border-radius: 999px; font-size: 0.7rem; }.moves-panel ol { display: grid; align-content: start; gap: 0.25rem; max-height: 410px; margin: 1rem 0 0; padding: 0; overflow-y: auto; list-style: none; }.moves-panel li { display: grid; grid-template-columns: 28px 1fr auto; align-items: center; gap: 0.6rem; padding: 0.55rem 0.45rem; border-bottom: 1px solid #eadfce; }.moves-panel li > span, .moves-panel small, .empty { color: #8c7867; font-size: 0.78rem; }.moves-panel strong { font-family: var(--font-mono); }.empty { margin: auto; text-align: center; }.match-panel footer { display: grid; gap: 0.2rem; padding: 1rem 1.5rem; color: #6f855c; background: #eee2d0; border-top: 1px solid var(--line); }.match-panel footer small { color: #8a7766; }
@media (max-width: 1100px) { .header-actions .leave { display:none; } }
@media (max-width: 900px) { .game-layout { grid-template-columns: minmax(0, 680px); }.board-frame { width: 100%; }.match-panel { min-height: 0; }.moves-panel ol { max-height: 260px; } }
@media (max-width: 820px) { .header-actions { margin-left:0; }.header-actions .sound-toggle span { display:none; } }
@media (max-width: 560px) { .game-shell { min-height:calc(100vh - 58px); padding: 0 .55rem 1rem; }.leave { font-size: 0.78rem; }.player-bar { min-height: 55px; padding: 0.45rem 0.55rem; }.player-bar img, .avatar { width: 38px; height: 38px; }.player-bar time { min-width: 88px; font-size: 1.35rem; }.board-frame { border-radius: 5px; }.match-panel { border-radius: 13px; }.panel-heading { padding: 1.1rem; } }

/* Superfícies da partida acompanham o tema; o tabuleiro mantém sua paleta própria. */
.game-shell { --ink:var(--text); --brown:var(--accent); --line:var(--border); color:var(--text); }
.player-bar { background:color-mix(in srgb,var(--surface) 94%,transparent); border-color:var(--border-subtle); }
.player-bar.thinking { border-color:var(--accent); box-shadow:0 5px 18px color-mix(in srgb,var(--accent) 14%,transparent); }
.player-bar small { color:var(--text-muted); }
.player-bar time { color:var(--text); background:var(--surface-strong); }
.player-bar em { color:var(--accent); background:color-mix(in srgb,var(--accent) 14%,var(--surface-strong)); }
.player-bar em.bot-tag { color:var(--accent-ink); background:var(--accent); }
.avatar { color:var(--accent-ink); background:var(--accent); }
.match-panel { color:var(--text); background:color-mix(in srgb,var(--surface) 96%,transparent); border-color:var(--border); box-shadow:var(--shadow); }
.panel-heading { border-color:var(--border); }
.panel-heading > span,.panel-heading p { color:var(--text-muted); }
.panel-heading > span { color:var(--accent); }
.preparation-card { background:var(--surface-strong); border-color:var(--border); }
.preparation-card > span { color:var(--accent); }
.preparation-card strong,.preparation-card button,.game-actions button { color:var(--accent-ink); background:var(--accent); border-color:var(--accent); }
.preparation-card p,.game-actions > span,.empty { color:var(--text-muted); }
.preparation-card button:hover,.game-actions button:hover { background:var(--accent-hover); border-color:var(--accent-hover); }
.game-actions .cancel-resign { color:var(--text); background:transparent; border-color:var(--border); }
.game-actions .cancel-resign:hover { color:var(--accent); background:var(--surface-hover); }
.moves-title button { color:var(--accent); background:var(--surface-strong); border-color:var(--border); }
.moves-title span { color:var(--text-muted); background:var(--surface-strong); }
.match-panel footer { color:var(--success); background:var(--surface-strong); border-color:var(--border); }
.match-panel footer small { color:var(--text-muted); }
.result-card { color:var(--text); background:color-mix(in srgb,var(--surface) 97%,transparent); border-color:var(--border); box-shadow:var(--shadow); }
.result-card>span:first-child { color:var(--accent); }
.result-card>p,.rematch-dialogue { color:var(--text-muted); }
.result-card>button,.rematch-card button { color:var(--accent-ink); background:var(--accent); border-color:var(--accent); }
.result-card>button:hover,.rematch-card button:hover { background:var(--accent-hover); }
.rematch-card { border-color:var(--border); }
.result-card .rematch-card button.quiet { color:var(--text); background:transparent; border-color:var(--border); }
.result-card .rematch-card button.quiet:hover,.analysis-progress { color:var(--accent); background:var(--surface-hover); }
</style>
