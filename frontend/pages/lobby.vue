<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'

definePageMeta({ middleware: 'auth', layout: 'default' })

type LobbyUser = { id: string; nickname: string; rating: number; avatar_url: string | null }
type TimeControl = { id: string; label: string; initial_time_ms: number; increment_ms: number }
type Challenge = { id: string; challenger: LobbyUser; challenged: LobbyUser; time_control: TimeControl }
type LobbyState = { users: LobbyUser[]; challenges: Challenge[] }
type AcceptedGame = { game_id: string; white_player: LobbyUser; black_player: LobbyUser; time_control: TimeControl }
type PrivateRoom = { code: string; time_control: TimeControl; expires_at: string }

const timeControls = [
  { id: 'bullet_1_0', label: 'Bullet 1+0' },
  { id: 'blitz_3_0', label: 'Blitz 3+0' },
  { id: 'blitz_5_3', label: 'Blitz 5+3' },
  { id: 'rapid_10_0', label: 'Rapid 10+0' }
] as const

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

onMounted(async () => {
  auth.restoreSession()

  if (!auth.token || !(await auth.fetchCurrentUser())) {
    await navigateTo('/')
    return
  }

  const currentUser = auth.user
  if (!currentUser) return

  const backendUrl = useRuntimeConfig().public.api.baseURL
  const websocketUrl = `${backendUrl.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  socket = new Socket(websocketUrl, { params: { token: auth.token } })
  socket.connect()

  channel = socket.channel('games:lobby', {})
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

  socket.onError(() => { status.value = 'Reconectando...' })
  socket.onClose(() => {
    if (searchingMatch.value) {
      searchingMatch.value = false
      matchmakingMessage.value = 'Busca cancelada pela desconexão.'
    }
  })
})

onBeforeUnmount(() => {
  if (searchingMatch.value) matchmakingChannel?.push('leave_queue', {})
  matchmakingChannel?.leave()
  privateRoomChannel?.leave()
  channel?.leave()
  socket?.disconnect()
})

function applyLobbyState(state: LobbyState) {
  users.value = state.users
  challenges.value = state.challenges
  status.value = 'Online agora'
  errorMessage.value = ''
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
      <header class="welcome" id="dashboard">
        <div>
          <h1>Bem-vindo ao ChessDuel</h1>
          <p>Escolha seu oponente e comece um novo duelo.</p>
        </div>
        <div class="profile">
          <NuxtLink v-if="auth.user" class="profile-link" :to="`/profile/${encodeURIComponent(auth.user.nickname)}`">
            <strong>{{ auth.user.nickname }}</strong><small>Rating {{ auth.user.rating }}</small>
          </NuxtLink>
          <img v-if="avatarUrl(auth.user)" class="avatar" :src="avatarUrl(auth.user) || ''" alt="Sua foto de perfil">
          <span v-else class="avatar">{{ auth.user?.nickname?.charAt(0).toUpperCase() }}</span>
          <button @click="logOut">Sair</button>
        </div>
      </header>

      <p class="connection"><span /> {{ status }}</p>
      <p v-if="errorMessage" class="error">{{ errorMessage }}</p>

      <section class="panel matchmaking-panel">
        <div>
          <span class="eyebrow">MATCHMAKING</span>
          <h2>Buscar partida automaticamente</h2>
          <p>Encontre um adversário com rating próximo ao seu.</p>
        </div>
        <label class="time-control">
          <span>Formato</span>
          <select v-model="selectedTimeControl" :disabled="searchingMatch">
            <option v-for="control in timeControls" :key="control.id" :value="control.id">{{ control.label }}</option>
          </select>
        </label>
        <button v-if="!searchingMatch" class="search" type="button" @click="startMatchmaking">Buscar partida</button>
        <button v-else class="cancel-search" type="button" @click="cancelMatchmaking">Cancelar busca</button>
        <p v-if="matchmakingMessage" class="search-status"><span />{{ matchmakingMessage }}</p>
      </section>

      <section class="panel private-room-panel">
        <div>
          <span class="eyebrow">SALA PRIVADA</span>
          <h2>Jogar com um amigo</h2>
          <p>Crie um link exclusivo no formato selecionado acima.</p>
        </div>
        <button class="private-room-button" type="button" :disabled="creatingPrivateRoom || searchingMatch" @click="createPrivateRoom">
          {{ creatingPrivateRoom ? 'Criando...' : 'Criar sala privada' }}
        </button>
        <div v-if="privateRoom" class="room-waiting">
          <p class="search-status"><span />Aguardando seu amigo entrar em {{ privateRoom.time_control.label }}...</p>
          <div class="room-link-row">
            <input :value="privateRoomLink" readonly aria-label="Link da sala privada" @focus="($event.target as HTMLInputElement).select()">
            <button type="button" @click="copyPrivateRoomLink">Copiar link</button>
          </div>
          <small>{{ copyMessage || 'A sala expira em aproximadamente 20 minutos.' }}</small>
        </div>
      </section>

      <section class="panel">
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
        <p v-else class="empty">Nenhum desafio recebido por enquanto.</p>
      </section>

      <section class="panel" id="online">
        <div class="section-heading">
          <div><span class="eyebrow">ARENA</span><h2>Jogadores online</h2></div>
          <span>{{ opponents.length }} disponivel(is)</span>
        </div>
        <div v-if="opponents.length" class="online-grid">
          <article v-for="opponent in opponents" :key="opponent.id" class="online-card">
            <span class="online-dot" />
            <img v-if="avatarUrl(opponent)" class="avatar small" :src="avatarUrl(opponent) || ''" :alt="`Foto de ${opponent.nickname}`">
            <span v-else class="avatar small">{{ opponent.nickname.charAt(0).toUpperCase() }}</span>
            <div><NuxtLink class="player-link" :to="`/profile/${encodeURIComponent(opponent.nickname)}`"><strong>{{ opponent.nickname }}</strong></NuxtLink><small>Rating {{ opponent.rating }}</small></div>
            <button :disabled="searchingMatch || challengeSentTo(opponent.id)" @click="challenge(opponent.id)">
              {{ challengeSentTo(opponent.id) ? 'Aguardando' : 'Desafiar' }}
            </button>
          </article>
        </div>
        <p v-else class="empty">Voce e o unico jogador online. Abra outra aba e entre com uma segunda conta para testar.</p>
      </section>

      <section v-if="sentChallenges.length" class="panel compact">
        <h2>Desafios enviados</h2>
        <p v-for="item in sentChallenges" :key="item.id">Aguardando resposta de <strong>{{ item.challenged.nickname }}</strong> · {{ item.time_control.label }}.</p>
      </section>
    </div>
  </main>
</template>

<style scoped>
.lobby-shell { --cream: #f4eddf; --panel: #fffaf0; --line: #dfcfb8; --ink: #3c2b20; --brown: #925b35; min-height: 100vh; color: var(--ink); background-color: var(--cream); background-image: radial-gradient(#bba98e35 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
.content { display: grid; align-content: start; gap: 1.4rem; padding: 2rem; }
.welcome, .panel { padding: 1.6rem; background: #fffaf0e8; border: 1px solid #eadcc7; border-radius: 18px; box-shadow: 0 14px 30px #60401f12; }
.welcome { display: flex; align-items: center; justify-content: space-between; }.welcome h1, h2 { margin: 0; font-family: Georgia, serif; font-weight: 500; }.welcome p { margin: 0.4rem 0 0; color: #857060; }
.profile { display: flex; align-items: center; gap: 0.8rem; text-align: right; }.profile-link { display: grid; color: inherit; text-decoration: none; }.profile small, .player-row small, .online-card small { color: #8b7664; }.player-link { color: inherit; text-decoration: none; }.profile-link:hover, .player-link:hover { color: var(--brown); text-decoration: underline; }
.avatar { display: grid; width: 46px; height: 46px; place-items: center; color: white; object-fit: cover; font-weight: 700; background: var(--brown); border-radius: 50%; }.avatar.small { width: 40px; height: 40px; }
button { padding: 0.7rem 1rem; color: var(--ink); background: #f7eedf; border: 1px solid var(--line); border-radius: 9px; cursor: pointer; }button:disabled { opacity: 0.6; cursor: default; }
.connection { margin: 0; color: #6f855c; font-size: 0.9rem; }.connection span, .online-dot { display: inline-block; width: 8px; height: 8px; background: #668a57; border-radius: 50%; box-shadow: 0 0 8px #668a57; }
.section-heading { display: flex; align-items: end; justify-content: space-between; margin-bottom: 1.2rem; }.section-heading > span { color: #8b7664; font-size: 0.85rem; }.eyebrow { display: inline-block; margin-bottom: 0.5rem; padding: 0.3rem 0.6rem; color: var(--brown); background: #ead7bc; border-radius: 999px; font-size: 0.7rem; font-weight: 700; letter-spacing: 0.1em; }
.list { display: grid; gap: 0.75rem; }.player-row, .online-card { display: flex; align-items: center; gap: 0.9rem; padding: 1rem; background: #efe3cf; border: 1px solid var(--line); border-radius: 14px; }.player-row > div:not(.actions), .online-card > div { display: grid; }.actions, .online-card button { margin-left: auto; }.accept { color: white; background: #67865a; }.decline { color: white; background: #bd5737; }
.online-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0.8rem; }.online-card { position: relative; }.online-dot { position: absolute; top: 0.8rem; right: 0.8rem; }.empty { margin: 0; padding: 1.2rem; color: #8b7664; text-align: center; border: 1px dashed var(--line); border-radius: 12px; }.compact p { margin-bottom: 0; }.error { margin: 0; padding: 0.8rem 1rem; color: #9e3828; background: #f9ded5; border-radius: 10px; }
.time-control { display: flex; align-items: center; justify-content: flex-end; gap: .7rem; margin: 0 0 1.2rem; color: #806d5d; font-size: .85rem; }.time-control select { padding: .65rem .8rem; color: var(--ink); background: #fffaf0; border: 1px solid var(--line); border-radius: 9px; font: inherit; }
.matchmaking-panel { display: grid; grid-template-columns: 1fr auto auto; align-items: center; gap: 1rem; }.matchmaking-panel p { margin: .35rem 0 0; color: #857060; }.matchmaking-panel .time-control { margin: 0; }.search { color: white; font-weight: 700; background: var(--brown); }.cancel-search { color: white; font-weight: 700; background: #a74c35; }.search-status { display: flex; grid-column: 1 / -1; align-items: center; gap: .5rem; padding-top: .8rem; border-top: 1px solid var(--line); }.search-status span { width: 9px; height: 9px; background: #668a57; border-radius: 50%; box-shadow: 0 0 8px #668a57; animation: pulse 1.2s infinite; }@keyframes pulse { 50% { opacity: .35; transform: scale(.8); } }
.private-room-panel { display: grid; grid-template-columns: 1fr auto; align-items: center; gap: 1rem; }.private-room-panel p { margin: .35rem 0 0; color: #857060; }.private-room-button { color: white; font-weight: 700; background: #765039; }.room-waiting { display: grid; grid-column: 1 / -1; gap: .7rem; padding-top: .4rem; }.room-waiting .search-status { margin: 0; }.room-link-row { display: grid; grid-template-columns: 1fr auto; gap: .6rem; }.room-link-row input { min-width: 0; padding: .75rem; color: var(--ink); background: #fffaf0; border: 1px solid var(--line); border-radius: 9px; font: inherit; }.room-waiting small { color: #806d5d; }
@media (max-width: 760px) { .content { padding: 1rem; }.welcome { align-items: flex-start; gap: 1rem; }.welcome > div:first-child p { display: none; }.profile > div { display: none; }.matchmaking-panel, .private-room-panel { grid-template-columns: 1fr; }.matchmaking-panel .time-control { justify-content: stretch; }.matchmaking-panel select { flex: 1; }.room-link-row { grid-template-columns: 1fr; }.online-grid { grid-template-columns: 1fr; }.section-heading { align-items: flex-start; }.player-row { flex-wrap: wrap; }.actions { width: 100%; display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; }.actions button { width: 100%; } }
</style>
