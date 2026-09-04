<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'
import { ArrowRight, Brain, Eye, Flame, Monitor, Puzzle, Swords, Trophy } from 'lucide-vue-next'
import type { BroadcastGame, ChessDuelLiveGame, BroadcastsApiResponse, ChessDuelLiveApiResponse } from '~/types/live-games'
import { combineLiveFeed } from '~/utils/liveGames'
import LobbyBroadcastCard from '~/components/live/BroadcastLiveCard.vue'
import LobbyChessDuelLiveCard from '~/components/live/ChessDuelLiveCard.vue'

definePageMeta({ middleware: 'auth', layout: 'default' })

type PresenceStatus = 'online' | 'away' | 'dnd' | 'invisible'
type LobbyUser = { id: string; nickname: string; rating: number; avatar_url: string | null; status: PresenceStatus }
type TimeControl = { id: string; label: string; initial_time_ms: number; increment_ms: number }
type Challenge = { id: string; challenger: LobbyUser; challenged: LobbyUser; time_control: TimeControl }
type LobbyState = { users: LobbyUser[]; challenges: Challenge[] }
type AcceptedGame = { game_id: string; white_player: LobbyUser; black_player: LobbyUser; time_control: TimeControl }
type PrivateRoom = { code: string; time_control: TimeControl; expires_at: string }
type RecentGame = {
  id: string
  opponent: { nickname: string }
  result: 'win' | 'loss' | 'draw'
  rating_change: number | null
  time_control: { label: string }
  finished_at: string
}
type HistoryResponse = { games: RecentGame[]; pagination: { total: number } }

const timeControls = [
  { id: 'bullet_1_0', label: 'Bullet 1+0' },
  { id: 'blitz_3_0', label: 'Blitz 3+0' },
  { id: 'blitz_5_0', label: 'Blitz 5+0' },
  { id: 'rapid_10_0', label: 'Rapid 10+0' }
] as const

const presenceOptions: Array<{ id: PresenceStatus; label: string; description: string }> = [
  { id: 'online', label: 'Online agora', description: 'Você aparece disponível.' },
  { id: 'away', label: 'Ausente', description: 'Você aparece como ausente.' },
  { id: 'dnd', label: 'Não perturbar', description: 'Você não receberá novos desafios.' },
  { id: 'invisible', label: 'Invisível', description: 'Você aparecerá offline.' }
]
const presenceStorageKey = 'chess-duel:presence'

const auth = useAuthStore()
const users = ref<LobbyUser[]>([])
const challenges = ref<Challenge[]>([])
const status = ref('Conectando ao salao...')
const errorMessage = ref('')
const selectedTimeControl = ref<(typeof timeControls)[number]['id']>('blitz_3_0')
const searchingMatch = ref(false)
const matchmakingMessage = ref('')
const privateRoom = ref<PrivateRoom | null>(null)
const creatingPrivateRoom = ref(false)
const copyMessage = ref('')
const config = useRuntimeConfig()
const recentGames = ref<RecentGame[]>([])
const gamesTotal = ref(0)
const historyLoading = ref(true)
const broadcasts = ref<BroadcastGame[]>([])
const chessDuelGames = ref<ChessDuelLiveGame[]>([])
const liveGamesLoading = ref(true)
const liveGamesError = ref('')
const presence = ref<PresenceStatus>('online')
const presenceOpen = ref(false)
const presencePicker = ref<HTMLElement | null>(null)
const connectionReady = ref(false)
let liveGamesPollingTimer: ReturnType<typeof setInterval> | null = null

const liveFeedItems = computed(() => combineLiveFeed(broadcasts.value, chessDuelGames.value))
const selectedPresence = computed(() => presenceOptions.find(option => option.id === presence.value) || presenceOptions[0]!)

let socket: Socket | null = null
let channel: Channel | null = null
let matchmakingChannel: Channel | null = null
let privateRoomChannel: Channel | null = null

const opponents = computed(() => users.value.filter(user => user.id !== auth.user?.id))
const receivedChallenges = computed(() => challenges.value.filter(item => item.challenged.id === auth.user?.id))
const sentChallenges = computed(() => challenges.value.filter(item => item.challenger.id === auth.user?.id))
const privateRoomLink = computed(() => privateRoom.value && import.meta.client
  ? `${window.location.origin}/room/${privateRoom.value.code}`
  : '')
const recentWins = computed(() => recentGames.value.filter(game => game.result === 'win').length)
const recentRatingChange = computed(() => recentGames.value.reduce((total, game) => total + (game.rating_change || 0), 0))
const recentWinRate = computed(() => recentGames.value.length ? Math.round((recentWins.value / recentGames.value.length) * 100) : 0)
const resultLabels: Record<RecentGame['result'], string> = {
  win: 'Vitória',
  loss: 'Derrota',
  draw: 'Empate'
}

onMounted(async () => {
  auth.restoreSession()
  const savedPresence = localStorage.getItem(presenceStorageKey)
  if (presenceOptions.some(option => option.id === savedPresence)) presence.value = savedPresence as PresenceStatus
  document.addEventListener('pointerdown', closePresenceMenu)

  if (!auth.token || !(await auth.fetchCurrentUser())) {
    await navigateTo('/')
    return
  }

  const currentUser = auth.user
  if (!currentUser) return

  void loadDashboardHistory()
  void fetchLiveGames(true)
  liveGamesPollingTimer = setInterval(() => {
    void fetchLiveGames(false)
  }, 20_000)

  const backendUrl = useRuntimeConfig().public.api.baseURL
  const websocketUrl = `${backendUrl.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  socket = new Socket(websocketUrl, { params: { token: auth.token } })
  socket.connect()

  channel = socket.channel('games:lobby', { status: presence.value })
  channel.join()
    .receive('ok', applyLobbyState)
    .receive('error', () => { status.value = 'Nao foi possivel entrar no salao.' })

  channel.on('lobby_updated', applyLobbyState)
  channel.on('challenge_accepted', async (game: AcceptedGame) => {
    if (game.white_player.id === auth.user?.id || game.black_player.id === auth.user?.id) {
      await navigateTo(`/game/${game.game_id}/live`)
    }
  })

  matchmakingChannel = socket.channel(`matchmaking:${currentUser.id}`, {})
  matchmakingChannel.join()
    .receive('error', () => { errorMessage.value = 'Não foi possível acessar o matchmaking.' })

  matchmakingChannel.on('match_found', async (game: AcceptedGame) => {
    searchingMatch.value = false
    matchmakingMessage.value = 'Partida encontrada!'
    await navigateTo(`/game/${game.game_id}/live`)
  })
  matchmakingChannel.on('queue_waiting', (payload: { message?: string }) => {
    matchmakingMessage.value = payload.message || 'A busca continua com uma faixa maior de rating.'
  })

  privateRoomChannel = socket.channel(`private_rooms:${currentUser.id}`, {})
  privateRoomChannel.join()
    .receive('error', () => { errorMessage.value = 'Não foi possível acessar as salas privadas.' })
  privateRoomChannel.on('match_found', enterPrivateGame)

  socket.onError(() => {
    connectionReady.value = false
    status.value = 'Reconectando...'
  })
  socket.onClose(() => {
    connectionReady.value = false
    if (searchingMatch.value) {
      searchingMatch.value = false
      matchmakingMessage.value = 'Busca cancelada pela desconexão.'
    }
  })
})

async function loadDashboardHistory() {
  if (!auth.token) return
  try {
    const response = await $fetch<HistoryResponse>('/api/users/me/games', {
      baseURL: config.public.api.baseURL,
      headers: { Authorization: `Bearer ${auth.token}` },
      query: { page: 1, per_page: 5 }
    })
    recentGames.value = response.games
    gamesTotal.value = response.pagination.total
  } catch {
    recentGames.value = []
    gamesTotal.value = 0
  } finally {
    historyLoading.value = false
  }
}

function relativeDate(value: string) {
  const elapsed = Date.now() - new Date(value).getTime()
  const formatter = new Intl.RelativeTimeFormat('pt-BR', { numeric: 'auto' })
  if (elapsed < 3_600_000) return formatter.format(-Math.max(1, Math.round(elapsed / 60_000)), 'minute')
  if (elapsed < 86_400_000) return formatter.format(-Math.round(elapsed / 3_600_000), 'hour')
  return formatter.format(-Math.round(elapsed / 86_400_000), 'day')
}

async function fetchLiveGames(isInitial = false) {
  if (isInitial && !broadcasts.value.length && !chessDuelGames.value.length) {
    liveGamesLoading.value = true
  }

  let broadcastFailed = false
  let chessDuelFailed = false

  const [broadcastResult, chessDuelResult] = await Promise.allSettled([
    $fetch<BroadcastsApiResponse>('/api/broadcasts/live', { baseURL: config.public.api.baseURL }),
    $fetch<ChessDuelLiveApiResponse>('/api/games/live', { baseURL: config.public.api.baseURL })
  ])

  if (broadcastResult.status === 'fulfilled') {
    broadcasts.value = broadcastResult.value?.games || []
  } else {
    broadcastFailed = true
  }

  if (chessDuelResult.status === 'fulfilled') {
    chessDuelGames.value = chessDuelResult.value?.games || []
  } else {
    chessDuelFailed = true
  }

  if (broadcastFailed && chessDuelFailed) {
    if (!broadcasts.value.length && !chessDuelGames.value.length) {
      liveGamesError.value = 'Não foi possível carregar as partidas ao vivo.'
    }
  } else {
    liveGamesError.value = ''
  }

  liveGamesLoading.value = false
}

onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', closePresenceMenu)
  if (liveGamesPollingTimer) {
    clearInterval(liveGamesPollingTimer)
    liveGamesPollingTimer = null
  }
  if (searchingMatch.value) matchmakingChannel?.push('leave_queue', {})
  matchmakingChannel?.leave()
  privateRoomChannel?.leave()
  channel?.leave()
  socket?.disconnect()
})

function applyLobbyState(state: LobbyState) {
  users.value = state.users
  challenges.value = state.challenges
  connectionReady.value = true
  status.value = selectedPresence.value.label
  errorMessage.value = ''
}

function selectPresence(nextPresence: PresenceStatus) {
  presence.value = nextPresence
  presenceOpen.value = false
  localStorage.setItem(presenceStorageKey, nextPresence)
  if (connectionReady.value) status.value = selectedPresence.value.label

  channel?.push('set_presence', { status: nextPresence })
    .receive('error', showChannelError)
}

function closePresenceMenu(event: PointerEvent) {
  if (!presencePicker.value?.contains(event.target as Node)) presenceOpen.value = false
}

function challenge(userId: string) {
  channel?.push('challenge', { user_id: userId, time_control: selectedTimeControl.value })
    .receive('error', showChannelError)
}

function startMatchmaking() {
  if (!matchmakingChannel || searchingMatch.value) return

  errorMessage.value = ''
  matchmakingMessage.value = 'Procurando um oponente com rating próximo...'

  matchmakingChannel.push('join_queue', { time_control: selectedTimeControl.value })
    .receive('ok', () => { searchingMatch.value = true })
    .receive('error', showChannelError)
}

function cancelMatchmaking() {
  matchmakingChannel?.push('leave_queue', {})
    .receive('ok', () => {
      searchingMatch.value = false
      matchmakingMessage.value = ''
    })
    .receive('error', showChannelError)
}

function createPrivateRoom() {
  if (!privateRoomChannel || creatingPrivateRoom.value) return

  creatingPrivateRoom.value = true
  errorMessage.value = ''
  copyMessage.value = ''
  privateRoomChannel.push('create_room', { time_control: selectedTimeControl.value })
    .receive('ok', (room: PrivateRoom) => {
      privateRoom.value = room
      creatingPrivateRoom.value = false
    })
    .receive('error', (error: { reason?: string }) => {
      creatingPrivateRoom.value = false
      showChannelError(error)
    })
}

async function copyPrivateRoomLink() {
  if (!privateRoomLink.value) return

  try {
    await navigator.clipboard.writeText(privateRoomLink.value)
    copyMessage.value = 'Link copiado!'
  } catch {
    copyMessage.value = 'Não foi possível copiar. Selecione o link manualmente.'
  }
}

async function enterPrivateGame(match: { game_id: string }) {
  await navigateTo(`/game/${match.game_id}/live`)
}

function accept(challengeId: string) {
  channel?.push('accept_challenge', { challenge_id: challengeId })
    .receive('error', showChannelError)
}

function decline(challengeId: string) {
  channel?.push('decline_challenge', { challenge_id: challengeId })
    .receive('error', showChannelError)
}

function showChannelError(error: { reason?: string }) {
  const messages: Record<string, string> = {
    user_offline: 'Esse jogador saiu do salao.',
    user_unavailable: 'Esse jogador não está recebendo desafios agora.',
    invalid_presence: 'Escolha um status de presença válido.',
    challenge_already_exists: 'Voce ja desafiou esse jogador.',
    challenge_not_found: 'Esse desafio nao esta mais disponivel.',
    invalid_time_control: 'Escolha um formato de tempo válido.',
    queue_unavailable: 'A fila está indisponível no momento.',
    room_unavailable: 'As salas privadas estão indisponíveis no momento.'
  }
  errorMessage.value = messages[error.reason || ''] || 'Nao foi possivel concluir a acao.'
}

function challengeSentTo(userId: string) {
  return sentChallenges.value.some(item => item.challenged.id === userId)
}

function avatarUrl(user: LobbyUser | null | undefined) {
  return resolveAvatarUrl(user?.avatar_url, config.public.api.baseURL)
}

async function logOut() {
  channel?.leave()
  socket?.disconnect()
  await auth.logOut()
  await navigateTo('/')
}
</script>

<template>
  <main class="lobby-shell">
    <div class="content">
      <header class="welcome" id="dashboard"><h1>Como você quer jogar?</h1><p>Escolha seu modo de jogo e comece um novo duelo.</p></header>
      <section class="mode-grid" aria-label="Modos de jogo">
        <a class="mode-card featured" href="#matchmaking"><Swords :size="34" aria-hidden="true" /><span><strong>Buscar partida</strong><small>Encontre um adversário online e jogue agora.</small></span><ArrowRight :size="19" aria-hidden="true" /></a>
        <NuxtLink class="mode-card" to="/bots"><Monitor :size="34" aria-hidden="true" /><span><strong>Jogar contra computador</strong><small>Desafie nossos bots em diversos níveis.</small></span><ArrowRight :size="19" aria-hidden="true" /></NuxtLink>
        <NuxtLink class="mode-card" to="/puzzles"><Puzzle :size="34" aria-hidden="true" /><span><strong>Problemas</strong><small>Resolva problemas e melhore seu raciocínio tático.</small></span><ArrowRight :size="19" aria-hidden="true" /></NuxtLink>
        <a class="mode-card" href="#live-games"><Eye :size="34" aria-hidden="true" /><span><strong>Observar</strong><small>Acompanhe partidas ao vivo.</small></span><ArrowRight :size="19" aria-hidden="true" /></a>
      </section>

      <section id="matchmaking" class="play-bar" aria-label="Buscar partida">
        <div ref="presencePicker" class="presence-picker" @keydown.esc="presenceOpen = false">
          <button class="connection presence-trigger" type="button" :disabled="!connectionReady" :aria-expanded="presenceOpen" aria-haspopup="menu" @click="presenceOpen = !presenceOpen">
            <span class="presence-dot" :class="presence" aria-hidden="true" />
            <span aria-live="polite">{{ status }}</span>
            <span class="presence-chevron" aria-hidden="true">⌄</span>
          </button>
          <div v-if="presenceOpen" class="presence-menu" role="menu" aria-label="Definir status">
            <button
              v-for="option in presenceOptions"
              :key="option.id"
              type="button"
              role="menuitemradio"
              :aria-checked="presence === option.id"
              class="presence-option"
              @click="selectPresence(option.id)"
            >
              <span class="presence-dot" :class="option.id" aria-hidden="true" />
              <span><strong>{{ option.label }}</strong><small>{{ option.description }}</small></span>
              <span v-if="presence === option.id" class="presence-check" aria-hidden="true">✓</span>
            </button>
          </div>
        </div>
        <label class="time-control">
          <span class="sr-only">Formato</span>
          <select v-model="selectedTimeControl" :disabled="searchingMatch">
            <option v-for="control in timeControls" :key="control.id" :value="control.id">{{ control.label }}</option>
          </select>
        </label>
        <button v-if="!searchingMatch" class="search" type="button" @click="startMatchmaking">Buscar partida</button>
        <button v-else class="cancel-search" type="button" @click="cancelMatchmaking">Cancelar busca</button>
        <button class="private-room-button" type="button" :disabled="creatingPrivateRoom || searchingMatch" @click="createPrivateRoom">
          {{ creatingPrivateRoom ? 'Criando convite…' : 'Convidar amigo' }}
        </button>
      </section>
      <p v-if="matchmakingMessage" class="inline-status"><span />{{ matchmakingMessage }}</p>
      <section v-if="privateRoom" class="invite-result" aria-live="polite">
        <span>Aguardando seu amigo em {{ privateRoom.time_control.label }}</span>
        <input :value="privateRoomLink" readonly aria-label="Link da sala privada" @focus="($event.target as HTMLInputElement).select()">
        <button type="button" @click="copyPrivateRoomLink">{{ copyMessage || 'Copiar link' }}</button>
      </section>
      <p v-if="errorMessage" class="error">{{ errorMessage }}</p>

      <section id="live-games" class="live-games-section" aria-labelledby="live-title">
        <header class="live-heading">
          <p>
            <span aria-hidden="true" />
            <strong id="live-title">Partidas ao vivo</strong>
          </p>
          <small>Atualização a cada 20s</small>
        </header>

        <div v-if="liveGamesLoading && !liveFeedItems.length" class="live-loading-grid" aria-label="Carregando partidas ao vivo">
          <div v-for="i in 4" :key="i" class="card-skeleton" />
        </div>

        <div v-else-if="liveGamesError && !liveFeedItems.length" class="live-error">
          <p>{{ liveGamesError }}</p>
          <button type="button" @click="fetchLiveGames(true)">Tentar novamente</button>
        </div>

        <div v-else-if="!liveFeedItems.length" class="live-empty">
          <Eye :size="42" aria-hidden="true" />
          <strong>Nenhuma partida ao vivo no momento.</strong>
          <p>Quando houver torneios oficiais em andamento ou jogadores em duelo no ChessDuel, as partidas aparecerão aqui automaticamente.</p>
        </div>

        <div v-else class="live-grid">
          <template v-for="item in liveFeedItems" :key="item.id">
            <LobbyBroadcastCard v-if="item.source === 'broadcast'" :game="item.game" />
            <LobbyChessDuelLiveCard v-else-if="item.source === 'chessduel'" :game="item.game" />
          </template>
        </div>
      </section>

      <section v-if="receivedChallenges.length" class="panel">
        <div class="section-heading">
          <div><span class="eyebrow">CONVITES</span><h2>Desafios recebidos</h2></div>
          <span>{{ receivedChallenges.length }} pendente(s)</span>
        </div>
        <div v-if="receivedChallenges.length" class="list">
          <article v-for="item in receivedChallenges" :key="item.id" class="player-row">
            <img v-if="avatarUrl(item.challenger)" class="avatar small" :src="avatarUrl(item.challenger) || ''" :alt="`Foto de ${item.challenger.nickname}`">
            <span v-else class="avatar small">{{ item.challenger.nickname.charAt(0).toUpperCase() }}</span>
            <div><NuxtLink class="player-link" :to="`/profile/${encodeURIComponent(item.challenger.nickname)}`"><strong>{{ item.challenger.nickname }}</strong></NuxtLink><small>Rating {{ item.challenger.rating }} · {{ item.time_control.label }}</small></div>
            <div class="actions"><button class="accept" :disabled="searchingMatch" @click="accept(item.id)">Aceitar</button><button class="decline" @click="decline(item.id)">Recusar</button></div>
          </article>
        </div>
      </section>

      <section v-if="sentChallenges.length" class="panel compact">
        <h2>Desafios enviados</h2>
        <p v-for="item in sentChallenges" :key="item.id">Aguardando resposta de <strong>{{ item.challenged.nickname }}</strong> · {{ item.time_control.label }}.</p>
      </section>

      <section class="dashboard-grid" aria-label="Resumo da sua atividade">
        <article class="panel recent-panel">
          <header class="widget-heading"><h2>Partidas recentes</h2><NuxtLink to="/profile/history">Ver tudo</NuxtLink></header>
          <p v-if="historyLoading" class="widget-state">Carregando histórico…</p>
          <p v-else-if="!recentGames.length" class="widget-state">Suas partidas finalizadas aparecerão aqui.</p>
          <div v-else class="recent-list">
            <NuxtLink v-for="game in recentGames.slice(0, 3)" :key="game.id" :to="`/game/${game.id}/review`" class="recent-row">
              <span class="result-pill" :class="game.result">{{ resultLabels[game.result] }}</span>
              <span><strong>vs {{ game.opponent.nickname }}</strong><small>{{ game.time_control.label }}</small></span>
              <span class="recent-meta"><strong :class="{ positive: (game.rating_change || 0) > 0, negative: (game.rating_change || 0) < 0 }">{{ game.rating_change === null ? 'Casual' : game.rating_change > 0 ? `+${game.rating_change}` : game.rating_change }}</strong><small>{{ relativeDate(game.finished_at) }}</small></span>
            </NuxtLink>
          </div>
        </article>

        <article class="panel performance-panel">
          <header class="widget-heading"><h2>Seu desempenho</h2><Trophy :size="20" aria-hidden="true" /></header>
          <span class="metric-label">Rating atual</span>
          <div class="rating-value"><strong>{{ auth.user?.rating ?? '—' }}</strong><span :class="{ positive: recentRatingChange > 0, negative: recentRatingChange < 0 }">{{ recentRatingChange > 0 ? `+${recentRatingChange}` : recentRatingChange }}</span></div>
          <small class="sample-note">Variação nas últimas {{ recentGames.length }} partidas exibidas</small>
          <dl class="performance-stats"><div><dt>Partidas</dt><dd>{{ gamesTotal }}</dd></div><div><dt>Vitórias recentes</dt><dd>{{ recentWins }}</dd></div><div><dt>Aproveitamento</dt><dd>{{ recentWinRate }}%</dd></div></dl>
        </article>

        <article class="panel training-panel">
          <header class="widget-heading"><h2>Treino tático</h2><NuxtLink to="/puzzles">Ver hub</NuxtLink></header>
          <NuxtLink to="/puzzles/session?mode=classic"><Brain :size="21" aria-hidden="true" /><span><strong>Modo Clássico</strong><small>Resolva no seu ritmo</small></span><ArrowRight :size="18" aria-hidden="true" /></NuxtLink>
          <NuxtLink to="/puzzles/session?mode=rush&duration=180"><Flame :size="21" aria-hidden="true" /><span><strong>Corrida de problemas</strong><small>Velocidade e precisão</small></span><ArrowRight :size="18" aria-hidden="true" /></NuxtLink>
          <NuxtLink to="/puzzles/battle/180"><Swords :size="21" aria-hidden="true" /><span><strong>Batalha de problemas</strong><small>Enfrente outro jogador</small></span><ArrowRight :size="18" aria-hidden="true" /></NuxtLink>
        </article>
      </section>
    </div>
  </main>
</template>

<style scoped>
.lobby-shell { --cream: #f4eddf; --panel: #fffaf0; --line: #dfcfb8; --ink: #3c2b20; --brown: #6f4528; min-height: 100vh; color: var(--ink); background-color: var(--cream); background-image: radial-gradient(#bba98e35 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
.content { display: grid; align-content: start; gap: 1.4rem; padding: 2rem; }
.welcome, .panel { padding: 1.6rem; background: #fffaf0e8; border: 1px solid #eadcc7; border-radius: 18px; box-shadow: 0 14px 30px #6f452812; }
.welcome { display: flex; align-items: center; justify-content: space-between; }.welcome h1, h2 { margin: 0; font-family: Georgia, serif; font-weight: 500; }.welcome p { margin: 0.4rem 0 0; color: #857060; }
.profile { display: flex; align-items: center; gap: 0.8rem; text-align: right; }.profile-link { display: grid; color: inherit; text-decoration: none; }.profile small, .player-row small, .online-card small { color: #8b7664; }.player-link { color: inherit; text-decoration: none; }.profile-link:hover, .player-link:hover { color: var(--brown); text-decoration: underline; }
.avatar { display: grid; width: 46px; height: 46px; place-items: center; color: white; object-fit: cover; font-weight: 700; background: var(--brown); border-radius: 50%; }.avatar.small { width: 40px; height: 40px; }
button { padding: 0.7rem 1rem; color: var(--ink); background: #f7eedf; border: 1px solid var(--line); border-radius: 9px; cursor: pointer; transition: background 160ms ease, border-color 160ms ease, color 160ms ease, transform 160ms ease; }button:hover:not(:disabled) { border-color: #b9996b; transform: translateY(-1px); }button:disabled { opacity: 0.6; cursor: default; }
.connection { margin: 0; color: #6f855c; font-size: 0.9rem; }.online-dot { display: inline-block; width: 7px; height: 7px; background: #668a57; border-radius: 50%; box-shadow: 0 0 7px #668a57; }
.section-heading { display: flex; align-items: end; justify-content: space-between; margin-bottom: 1.2rem; }.section-heading > span { color: #8b7664; font-size: 0.85rem; }.eyebrow { display: inline-block; margin-bottom: 0.5rem; padding: 0.3rem 0.6rem; color: var(--brown); background: #ead7bc; border-radius: 999px; font-size: 0.7rem; font-weight: 700; letter-spacing: 0.1em; }
.list { display: grid; gap: 0.75rem; }.player-row, .online-card { display: flex; align-items: center; gap: 0.9rem; padding: 1rem; background: #efe3cf; border: 1px solid var(--line); border-radius: 14px; }.player-row > div:not(.actions), .online-card > div { display: grid; }.actions, .online-card button { margin-left: auto; }.online-card button:not(:disabled) { color: #fffaf0; font-weight: 800; background: var(--brown); border-color: var(--brown); box-shadow: 0 8px 16px #6f452824; }.online-card button:not(:disabled):hover { background: #7f5130; border-color: #7f5130; }.accept { color: white; background: #67865a; }.decline { color: white; background: #bd5737; }
.online-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0.8rem; }.online-card { position: relative; }.online-dot { position: absolute; top: 0.8rem; right: 0.8rem; }.empty { margin: 0; padding: 1.2rem; color: #8b7664; text-align: center; border: 1px dashed var(--line); border-radius: 12px; }.compact p { margin-bottom: 0; }.error { margin: 0; padding: 0.8rem 1rem; color: #9e3828; background: #f9ded5; border-radius: 10px; }
.time-control { display: flex; align-items: center; justify-content: flex-end; gap: .7rem; margin: 0 0 1.2rem; color: #806d5d; font-size: .85rem; }.time-control select { padding: .65rem .8rem; color: var(--ink); background: #fffaf0; border: 1px solid var(--line); border-radius: 9px; font: inherit; }
.matchmaking-panel { display: grid; grid-template-columns: 1fr auto auto; align-items: center; gap: 1rem; }.matchmaking-panel p { margin: .35rem 0 0; color: #857060; }.matchmaking-panel .time-control { margin: 0; }.search { color: white; font-weight: 700; background: var(--brown); border-color: var(--brown); box-shadow: 0 9px 18px #6f452824; }.search:hover:not(:disabled) { background: #7f5130; border-color: #7f5130; }.cancel-search { color: white; font-weight: 700; background: #8e3f32; border-color: #8e3f32; }.search-status { display: flex; grid-column: 1 / -1; align-items: center; gap: .5rem; padding-top: .8rem; border-top: 1px solid var(--line); }.search-status span { width: 9px; height: 9px; background: #668a57; border-radius: 50%; box-shadow: 0 0 8px #668a57; animation: pulse 1.2s infinite; }@keyframes pulse { 50% { opacity: .35; transform: scale(.8); } }
.private-room-panel { display: grid; grid-template-columns: 1fr auto; align-items: center; gap: 1rem; }.private-room-panel p { margin: .35rem 0 0; color: #857060; }.private-room-button { color: white; font-weight: 700; background: #7f5130; border-color: #7f5130; box-shadow: 0 8px 16px #6f45281d; }.private-room-button:hover:not(:disabled) { background: #6f4528; border-color: #6f4528; }.room-waiting { display: grid; grid-column: 1 / -1; gap: .7rem; padding-top: .4rem; }.room-waiting .search-status { margin: 0; }.room-link-row { display: grid; grid-template-columns: 1fr auto; gap: .6rem; }.room-link-row input { min-width: 0; padding: .75rem; color: var(--ink); background: #fffaf0; border: 1px solid var(--line); border-radius: 9px; font: inherit; }.room-waiting small { color: #806d5d; }
@media (max-width: 760px) { .content { padding: 1rem; }.welcome { align-items: flex-start; gap: 1rem; }.welcome > div:first-child p { display: none; }.profile > div { display: none; }.matchmaking-panel, .private-room-panel { grid-template-columns: 1fr; }.matchmaking-panel .time-control { justify-content: stretch; }.matchmaking-panel select { flex: 1; }.room-link-row { grid-template-columns: 1fr; }.online-grid { grid-template-columns: 1fr; }.section-heading { align-items: flex-start; }.player-row { flex-wrap: wrap; }.actions { width: 100%; display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; }.actions button { width: 100%; } }

/* Dashboard visual migration: all color decisions come from the global theme tokens. */
.lobby-shell { min-height: calc(100vh - 76px); color: var(--text); background-color: var(--bg); background-image: radial-gradient(color-mix(in srgb, var(--text-muted) 18%, transparent) .7px, transparent .7px); background-size: 5px 5px; }
:global(:root[data-theme='white']) .lobby-shell { background-color: #f4eddf; background-image: radial-gradient(#bba98e35 .7px, transparent .7px); }
.content { width: min(1440px, 100%); margin: auto; padding: clamp(1.5rem, 3vw, 3rem); gap: 1.5rem; }
.welcome { display: block; padding: 0; background: transparent; border: 0; border-radius: 0; box-shadow: none; }
.welcome h1 { font-family: inherit; font-size: clamp(1.55rem, 3vw, 2.1rem); font-weight: 700; letter-spacing: -.035em; }
.welcome p { margin-top: .45rem; color: var(--text-muted); }
.mode-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 1rem; padding-bottom: 1.5rem; border-bottom: 1px solid var(--border-subtle); }
.mode-card { display: grid; min-height: 164px; grid-template-columns: auto 1fr; align-items: center; gap: 1.2rem; padding: 1.35rem; color: var(--text); background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; text-decoration: none; box-shadow: 0 10px 25px rgb(0 0 0 / 7%); transition: transform 180ms ease, background 180ms ease, border-color 180ms ease; }
.mode-card.featured { border-color: var(--accent); }.mode-card:hover { background: var(--surface-hover); border-color: var(--accent); transform: translateY(-2px); }
.mode-card > svg:first-child { color: var(--accent); }.mode-card > svg:last-child { grid-column: 2; justify-self: end; color: var(--accent); transition: transform 180ms ease; }.mode-card:hover > svg:last-child { transform: translateX(3px); }
.mode-card span { display: grid; gap: .55rem; }.mode-card strong { font-size: 1rem; }.mode-card small { color: var(--text-muted); font-size: .84rem; line-height: 1.55; }
.panel { padding: 1.5rem; background: var(--surface); border-color: var(--border-subtle); border-radius: 12px; box-shadow: var(--shadow); scroll-margin-top: 96px; }
.panel h2 { color: var(--text); font-family: inherit; font-weight: 700; letter-spacing: -.02em; }.matchmaking-panel p, .private-room-panel p, .section-heading > span, .empty, .compact p, .room-waiting small, .profile small, .player-row small, .online-card small { color: var(--text-muted); }
.eyebrow { color: var(--accent); background: color-mix(in srgb, var(--accent) 13%, transparent); }.connection { color: var(--success); }.online-dot { background: var(--success); box-shadow: 0 0 7px var(--success); }
button { color: var(--text); background: var(--surface-strong); border-color: var(--border); }.time-control, label { color: var(--text-muted); }.time-control select, .room-link-row input { color: var(--text); background: var(--surface-strong); border-color: var(--border); }
.search, .private-room-button, .online-card button:not(:disabled) { color: var(--accent-ink); background: var(--accent); border-color: var(--accent); box-shadow: none; }.search:hover:not(:disabled), .private-room-button:hover:not(:disabled), .online-card button:not(:disabled):hover { color: var(--accent-ink); background: var(--accent-hover); border-color: var(--accent-hover); }
.cancel-search, .decline { color: white; background: var(--danger); border-color: var(--danger); }.accept { color: white; background: var(--success); border-color: var(--success); }
.player-row, .online-card { background: var(--surface-strong); border-color: var(--border); }.player-link { color: var(--text); }.player-link:hover { color: var(--accent); }.empty { border-color: var(--border); }.error { color: var(--danger); background: var(--danger-soft); }.search-status { border-color: var(--border); }.search-status span { background: var(--success); box-shadow: 0 0 8px var(--success); }
@media (max-width: 1100px) { .mode-grid { grid-template-columns: repeat(2, 1fr); } }
@media (max-width: 760px) { .lobby-shell { min-height: calc(100vh - 64px); }.content { padding: 1rem; }.welcome p { display: block; }.mode-grid { grid-template-columns: 1fr; }.mode-card { min-height: 132px; }.matchmaking-panel .time-control { justify-content: stretch; } }
.dashboard-grid { display: grid; grid-template-columns: 1.12fr .9fr .98fr; gap: 1rem; }.dashboard-grid .panel { min-width: 0; }.widget-heading { display: flex; align-items: center; justify-content: space-between; margin-bottom: 1.1rem; }.widget-heading h2 { font-size: 1.05rem; }.widget-heading a { padding: .38rem .58rem; color: var(--accent); border: 1px solid var(--border); border-radius: 7px; font-size: .72rem; text-decoration: none; }.widget-heading svg { color: var(--accent); }.widget-state { min-height: 128px; display: grid; place-items: center; margin: 0; color: var(--text-muted); text-align: center; }.recent-list { display: grid; }.recent-row { display: grid; grid-template-columns: 72px minmax(0, 1fr) auto; align-items: center; gap: .75rem; padding: .7rem 0; color: var(--text); border-bottom: 1px solid var(--border-subtle); text-decoration: none; }.recent-row:last-child { border-bottom: 0; }.recent-row:hover strong:first-child { color: var(--accent); }.recent-row > span:not(.result-pill) { display: grid; gap: .18rem; }.recent-row small { color: var(--text-muted); font-size: .7rem; }.result-pill { padding: .42rem .5rem; border-radius: 6px; font-size: .7rem; font-weight: 700; text-align: center; }.result-pill.win { color: var(--success); background: var(--success-soft); }.result-pill.loss { color: var(--danger); background: var(--danger-soft); }.result-pill.draw { color: var(--text-muted); background: var(--surface-strong); }.recent-meta { justify-items: end; }.positive { color: var(--success) !important; }.negative { color: var(--danger) !important; }.metric-label, .sample-note { color: var(--text-muted); }.rating-value { display: flex; align-items: baseline; gap: .65rem; margin: .35rem 0; }.rating-value > strong { font-size: 2.5rem; letter-spacing: -.05em; }.rating-value > span { color: var(--text-muted); font-weight: 700; }.sample-note { font-size: .7rem; }.performance-stats { display: grid; grid-template-columns: repeat(3, 1fr); margin: 1.35rem 0 0; padding-top: 1rem; border-top: 1px solid var(--border-subtle); }.performance-stats div { display: grid; justify-items: center; gap: .28rem; border-right: 1px solid var(--border-subtle); }.performance-stats div:last-child { border: 0; }.performance-stats dt { color: var(--text-muted); font-size: .7rem; text-align: center; }.performance-stats dd { margin: 0; font-size: 1.15rem; font-weight: 700; }.training-panel > a { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: .75rem; padding: .72rem; color: var(--text); border-bottom: 1px solid var(--border-subtle); text-decoration: none; }.training-panel > a:last-child { border: 0; }.training-panel > a:hover { background: var(--surface-hover); border-radius: 8px; }.training-panel > a > svg { color: var(--accent); }.training-panel > a span { display: grid; gap: .15rem; }.training-panel > a small { color: var(--text-muted); }
@media (max-width: 1050px) { .dashboard-grid { grid-template-columns: 1fr 1fr; }.training-panel { grid-column: 1 / -1; } }
@media (max-width: 700px) { .dashboard-grid { grid-template-columns: 1fr; }.training-panel { grid-column: auto; }.recent-row { grid-template-columns: 68px minmax(0, 1fr); }.recent-meta { grid-column: 2; grid-auto-flow: column; justify-content: space-between; justify-items: start; } }
.mode-grid { grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .75rem; padding-bottom: .8rem; }.mode-card { min-height: 82px; grid-template-columns: auto 1fr; gap: .8rem; padding: .85rem 1rem; box-shadow: none; }.mode-card span { gap: .2rem; }.mode-card small { font-size: .72rem; line-height: 1.3; }.matchmaking-panel { grid-template-columns: 1fr auto auto auto; padding: 1rem 1.15rem; }.matchmaking-panel h2 { font-size: 1rem; }.matchmaking-panel p { font-size: .78rem; }.private-room-button { color: var(--text); background: var(--surface-strong); border-color: var(--border); }.private-room-button:hover:not(:disabled) { color: var(--text); background: var(--surface-hover); border-color: var(--accent); }.live-games-section { display: grid; gap: .8rem; padding: .2rem 0; scroll-margin-top: 96px; }.live-heading { display: flex; align-items: center; justify-content: space-between; }.live-heading p { display: flex; align-items: center; gap: .5rem; margin: 0; }.live-heading p > span { width: 7px; height: 7px; background: var(--success); border-radius: 50%; box-shadow: 0 0 7px var(--success); }.live-heading small { color: var(--text-muted); }.live-empty { display: grid; min-height: 280px; place-items: center; align-content: center; gap: .6rem; padding: 2rem; color: var(--text-muted); text-align: center; background: linear-gradient(145deg,var(--surface),color-mix(in srgb,var(--surface-strong) 55%,var(--surface))); border: 1px solid var(--border-subtle); border-radius: 12px; }.live-empty svg { color: var(--accent); }.live-empty strong { color: var(--text); }.live-empty p { max-width: 520px; margin: 0; line-height: 1.55; }.room-waiting { grid-column: 1 / -1; }
@media (max-width: 900px) { .mode-grid { grid-template-columns: repeat(2, 1fr); }.matchmaking-panel { grid-template-columns: 1fr 1fr; }.matchmaking-panel > div:first-child { grid-column: 1 / -1; }.matchmaking-panel .time-control { justify-content: stretch; }.matchmaking-panel select { flex: 1; } }
@media (max-width: 560px) { .mode-grid { grid-template-columns: 1fr; }.mode-card { min-height: 68px; }.matchmaking-panel { grid-template-columns: 1fr; }.matchmaking-panel > div:first-child { grid-column: auto; }.live-empty { min-height: 230px; }.live-heading small { display: none; } }
.play-bar { display: flex; align-items: center; justify-content: flex-end; gap: .75rem; padding-bottom: .85rem; border-bottom: 1px solid var(--border-subtle); }.play-bar .connection { margin-right: auto; }.play-bar .time-control { margin: 0; }.play-bar select { min-width: 150px; padding: .72rem .85rem; color: var(--text); background: var(--surface); border: 1px solid var(--border); border-radius: 8px; }.play-bar button { min-height: 42px; }.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; }.inline-status { display: flex; align-items: center; gap: .5rem; margin: -.7rem 0 0; color: var(--text-muted); font-size: .82rem; }.inline-status span { width: 8px; height: 8px; background: var(--success); border-radius: 50%; animation: pulse 1.2s infinite; }.live-empty { min-height: 360px; }.dashboard-grid > .panel { min-height: 270px; }
@media (max-width: 560px) { .play-bar { align-items: stretch; flex-wrap: wrap; }.play-bar .presence-picker { width: 100%; }.play-bar .connection { width: 100%; }.play-bar .time-control { flex: 1; }.play-bar select { width: 100%; min-width: 0; }.play-bar button { flex: 1; }.live-empty { min-height: 300px; } }
.mode-grid { gap: 1rem; padding-bottom: 1.25rem; }.mode-card { min-height: 166px; grid-template-columns: auto minmax(0, 1fr); gap: 1rem; padding: 1.35rem; box-shadow: 0 10px 25px rgb(0 0 0 / 7%); }.mode-card span { gap: .45rem; }.mode-card strong { font-size: 1rem; }.mode-card small { font-size: .8rem; line-height: 1.5; }.mode-card > svg:last-child { grid-column: 2; }.dashboard-grid > .panel { min-height: 0; }.invite-result { display: grid; grid-template-columns: auto minmax(220px, 1fr) auto; align-items: center; gap: .7rem; margin-top: -.7rem; padding: .75rem; color: var(--text-muted); background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 9px; font-size: .8rem; }.invite-result input { min-width: 0; padding: .6rem .7rem; color: var(--text); background: var(--surface-strong); border: 1px solid var(--border); border-radius: 7px; }.invite-result button { padding: .6rem .8rem; color: var(--text); background: var(--surface-strong); border: 1px solid var(--border); border-radius: 7px; cursor: pointer; }
@media (max-width: 760px) { .mode-card { min-height: 140px; }.invite-result { grid-template-columns: 1fr auto; }.invite-result > span { grid-column: 1 / -1; } }
@media (max-width: 480px) { .invite-result { grid-template-columns: 1fr; }.invite-result > span { grid-column: auto; } }
.presence-picker { position: relative; margin-right: auto; }.play-bar .presence-trigger { display: flex; min-height: 42px; align-items: center; gap: .55rem; margin: 0; padding: .55rem .7rem; color: var(--text); background: transparent; border-color: transparent; font-weight: 700; }.play-bar .presence-trigger:hover:not(:disabled),.play-bar .presence-trigger[aria-expanded="true"] { background: var(--surface-hover); border-color: var(--border); transform: none; }.presence-trigger:disabled { opacity: .7; }.presence-chevron { margin-left: .1rem; color: var(--text-muted); }.presence-dot { position: relative; display: inline-block; width: 7px; height: 7px; flex: 0 0 auto; background: var(--success); border-radius: 50%; box-shadow: 0 0 7px var(--success); }.presence-dot.online { width: 7px; height: 7px; background: var(--success); border-radius: 50%; box-shadow: 0 0 7px var(--success); }.presence-dot.away { background: #e7a83e; box-shadow: none; }.presence-dot.dnd { background: var(--danger); box-shadow: none; }.presence-dot.dnd::after { position: absolute; top: 2.5px; right: 1px; left: 1px; height: 2px; content: ''; background: var(--surface); border-radius: 2px; }.presence-dot.invisible { background: transparent; border: 2px solid var(--text-muted); box-shadow: none; }.presence-menu { position: absolute; z-index: 30; top: calc(100% + .45rem); left: 0; width: min(330px, calc(100vw - 2rem)); padding: .45rem; background: var(--surface); border: 1px solid var(--border); border-radius: 12px; box-shadow: var(--shadow); }.presence-option { display: grid; width: 100%; grid-template-columns: 16px 1fr auto; align-items: center; gap: .75rem; padding: .7rem .75rem; color: var(--text); background: transparent; border: 0; text-align: left; }.presence-option:hover,.presence-option[aria-checked="true"] { background: var(--surface-hover); transform: none; }.presence-option .presence-dot { justify-self: center; }.presence-option > span:nth-child(2) { display: grid; gap: .18rem; }.presence-option strong { font-size: .88rem; }.presence-option small { color: var(--text-muted); font-size: .72rem; font-weight: 400; line-height: 1.35; }.presence-check { color: var(--accent); font-weight: 800; }
.content { padding-top: clamp(1rem, 2vw, 1.6rem); gap: 1rem; }.welcome h1 { margin: 0; }.welcome p { margin: .3rem 0 0; }.mode-grid { margin-top: .25rem; }.mode-card.featured { border-color: var(--border-subtle); }.mode-card.featured:hover { border-color: var(--accent); }.play-bar { min-height: 54px; padding: .3rem 0 .55rem; }.play-bar select { padding-block: .58rem; }.play-bar button { min-height: 38px; padding-block: .55rem; }.live-games-section { gap: .55rem; }
.play-bar .search, .play-bar .cancel-search, .play-bar .private-room-button { min-height: 36px; padding: .45rem .75rem; font-size: .82rem; }
.live-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1rem; }
.live-loading-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1rem; }
.card-skeleton { min-height: 340px; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; animation: pulse-skeleton 1.5s ease-in-out infinite; }
@keyframes pulse-skeleton { 0%, 100% { opacity: 0.6; } 50% { opacity: 0.25; } }
.live-error { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.8rem; padding: 2.5rem; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; color: var(--danger); text-align: center; }
.live-error button { padding: 0.5rem 1rem; color: var(--text); background: var(--surface-strong); border: 1px solid var(--border); border-radius: 8px; cursor: pointer; }
.live-error button:hover { border-color: var(--accent); }
@media (max-width: 600px) { .live-grid, .live-loading-grid { grid-template-columns: 1fr; } }
</style>
