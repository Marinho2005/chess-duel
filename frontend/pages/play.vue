<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'
import { Check, Copy, Link2, Search, ShieldCheck, Swords, UserRoundPlus, Users } from 'lucide-vue-next'

definePageMeta({ middleware: ['auth', 'active-game'], layout: 'default' })

type TimeControlId = 'bullet_1_0' | 'blitz_3_0' | 'blitz_5_0' | 'rapid_10_0'
type TimeControl = { id: TimeControlId; label: string; detail: string; category: string; icon: 'bullet' | 'blitz' | 'rapid' }
type PrivateRoom = { code: string; time_control: { label: string }; expires_at: string }
type MatchFound = { game_id: string }
type PlayerRatings = { bullet: number; blitz: number; rapid: number }
type Player = { id: string; nickname: string; avatar_url: string | null; status: 'online' | 'offline' | 'away' | 'dnd' | 'invisible'; rating: number; ratings: PlayerRatings }
type ChallengePlayer = { id: string; nickname: string; avatar_url: string | null; status: Player['status']; rating: number; ratings?: PlayerRatings }
type LobbyChallenge = { id: string; challenger: ChallengePlayer; challenged: ChallengePlayer; time_control: { id: string; label: string } }
type LobbyState = { challenges: LobbyChallenge[] }
type AcceptedGame = MatchFound & { white_player: { id: string }; black_player: { id: string } }

const timeControls: TimeControl[] = [
  { id: 'bullet_1_0', label: '1 min', detail: '1+0', category: 'Bullet', icon: 'bullet' },
  { id: 'blitz_3_0', label: '3 min', detail: '3+0', category: 'Blitz', icon: 'blitz' },
  { id: 'blitz_5_0', label: '5 min', detail: '5+0', category: 'Blitz', icon: 'blitz' },
  { id: 'rapid_10_0', label: '10 min', detail: '10+0', category: 'Rapid', icon: 'rapid' },
]

const auth = useAuthStore()
const config = useRuntimeConfig()
const route = useRoute()
const selectedTimeControl = ref<TimeControlId>('blitz_3_0')
const connectionReady = ref(false)
const searching = ref(false)
const searchMessage = ref('')
const errorMessage = ref('')
const creatingRoom = ref(false)
const privateRoom = ref<PrivateRoom | null>(null)
const copyMessage = ref('')
const challengeDialogOpen = ref(false)
const directChallengeReady = ref(false)
const directChallengeSending = ref(false)
const directChallengeError = ref('')
const directChallengeNotice = ref('')
const selectedOpponent = ref<Player | null>(null)
const opponentLoading = ref(false)
const lobbyChallenges = ref<LobbyChallenge[]>([])
const cancelingChallengeId = ref('')
const cancelingAllChallenges = ref(false)
let socket: Socket | null = null
let matchmakingChannel: Channel | null = null
let privateRoomChannel: Channel | null = null
let lobbyChannel: Channel | null = null
let navigating = false

const selectedControl = computed(() => timeControls.find(control => control.id === selectedTimeControl.value) || timeControls[1]!)
const pendingDirectChallenge = computed(() => lobbyChallenges.value.find(challenge =>
  challenge.challenger.id === auth.user?.id && challenge.challenged.id === selectedOpponent.value?.id
))
const sentChallenges = computed(() => lobbyChallenges.value.filter(challenge => challenge.challenger.id === auth.user?.id))
const opponentRating = computed(() => selectedOpponent.value?.ratings?.[selectedControl.value.icon] ?? selectedOpponent.value?.rating ?? '?')
const privateRoomLink = computed(() => privateRoom.value && import.meta.client
  ? `${window.location.origin}/room/${privateRoom.value.code}`
  : '')

onMounted(async () => {
  if (!auth.token || !auth.user) return

  try {
    const activeData = await $fetch<{ active: boolean; game_id?: string }>('/api/games/active', {
      baseURL: config.public.api.baseURL,
      headers: { Authorization: `Bearer ${auth.token}` }
    })
    if (activeData?.active && activeData.game_id) {
      await navigateTo(`/game/${activeData.game_id}/live`)
      return
    }
  } catch {
    // proceed
  }

  void loadRouteOpponent()

  const websocketUrl = `${config.public.api.baseURL.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  socket = new Socket(websocketUrl, { params: { token: auth.token } })
  socket.connect()

  matchmakingChannel = socket.channel(`matchmaking:${auth.user.id}`, {})
  matchmakingChannel.join()
    .receive('ok', () => { connectionReady.value = true })
    .receive('error', () => showError('queue_unavailable'))
  matchmakingChannel.on('match_found', enterGame)
  matchmakingChannel.on('queue_waiting', (payload: { message?: string }) => {
    searchMessage.value = payload.message || 'A busca continua com uma faixa maior de rating.'
  })

  privateRoomChannel = socket.channel(`private_rooms:${auth.user.id}`, {})
  privateRoomChannel.join()
    .receive('error', () => showError('room_unavailable'))
  privateRoomChannel.on('match_found', enterGame)

  lobbyChannel = socket.channel('games:lobby', { status: auth.presence })
  lobbyChannel.join()
    .receive('ok', (state: LobbyState) => {
      directChallengeReady.value = true
      lobbyChallenges.value = state.challenges || []
    })
    .receive('error', () => { directChallengeError.value = 'Não foi possível acessar os desafios.' })
  lobbyChannel.on('lobby_updated', (state: LobbyState) => { lobbyChallenges.value = state.challenges || [] })
  lobbyChannel.on('challenge_accepted', (game: AcceptedGame) => {
    if (game.white_player.id === auth.user?.id || game.black_player.id === auth.user?.id) {
      void enterGame(game)
    }
  })

  socket.onError(() => {
    connectionReady.value = false
    directChallengeReady.value = false
    if (searching.value) {
      searching.value = false
      searchMessage.value = ''
    }
    errorMessage.value = 'A conexão foi interrompida. Tentando reconectar…'
  })
})

onBeforeUnmount(() => {
  if (searching.value) matchmakingChannel?.push('leave_queue', {})
  matchmakingChannel?.leave()
  privateRoomChannel?.leave()
  lobbyChannel?.leave()
  socket?.disconnect()
})

function startMatchmaking() {
  if (!matchmakingChannel || !connectionReady.value || searching.value) return

  errorMessage.value = ''
  privateRoom.value = null
  copyMessage.value = ''
  searchMessage.value = `Procurando um adversário para ${selectedControl.value.category} ${selectedControl.value.detail}…`
  matchmakingChannel.push('join_queue', { time_control: selectedTimeControl.value })
    .receive('ok', () => { searching.value = true })
    .receive('error', (error: { reason?: string; game_id?: string }) => {
      if (error?.reason === 'already_in_game' && error.game_id) {
        void navigateTo(`/game/${error.game_id}/live`)
      } else {
        showError(error?.reason || 'queue_unavailable')
      }
    })
}

function cancelMatchmaking() {
  matchmakingChannel?.push('leave_queue', {})
    .receive('ok', () => {
      searching.value = false
      searchMessage.value = ''
    })
    .receive('error', (error: { reason?: string }) => showError(error.reason || 'queue_unavailable'))
}

function createPrivateRoom() {
  if (!privateRoomChannel || creatingRoom.value || searching.value) return

  creatingRoom.value = true
  privateRoom.value = null
  copyMessage.value = ''
  errorMessage.value = ''
  privateRoomChannel.push('create_room', { time_control: selectedTimeControl.value })
    .receive('ok', (room: PrivateRoom) => {
      privateRoom.value = room
      creatingRoom.value = false
    })
    .receive('error', (error: { reason?: string }) => {
      creatingRoom.value = false
      showError(error.reason || 'room_unavailable')
    })
}

function challengeByNickname(player: Player) {
  if (!lobbyChannel || !directChallengeReady.value || directChallengeSending.value) return

  directChallengeSending.value = true
  directChallengeError.value = ''
  directChallengeNotice.value = ''
  lobbyChannel.push('challenge_user', { user_id: player.id, time_control: selectedTimeControl.value })
    .receive('ok', (payload: { challenge?: LobbyChallenge }) => {
      directChallengeSending.value = false
      challengeDialogOpen.value = false
      selectedOpponent.value = player
      if (payload.challenge) {
        lobbyChallenges.value = [...lobbyChallenges.value.filter(challenge => challenge.id !== payload.challenge?.id), payload.challenge]
      }
      directChallengeNotice.value = `Desafio enviado para ${player.nickname}.`
      selectedOpponent.value = null
      void navigateTo('/play', { replace: true })
    })
    .receive('error', (error: { reason?: string }) => {
      directChallengeSending.value = false
      directChallengeError.value = challengeErrorMessage(error.reason)
    })
}

async function loadRouteOpponent() {
  const nickname = Array.isArray(route.query.opponent) ? route.query.opponent[0] : route.query.opponent
  if (!nickname || !auth.token) return

  opponentLoading.value = true
  try {
    const response = await $fetch<{ profile: Player }>(`/api/users/${encodeURIComponent(nickname)}`, {
      baseURL: config.public.api.baseURL,
      headers: { Authorization: `Bearer ${auth.token}` },
      query: { count_view: 'false' },
    })
    if (response.profile.id !== auth.user?.id) selectedOpponent.value = response.profile
  } catch {
    errorMessage.value = 'Não foi possível carregar o jogador escolhido.'
  } finally {
    opponentLoading.value = false
  }
}

function sendSelectedChallenge() {
  if (selectedOpponent.value) challengeByNickname(selectedOpponent.value)
}

function cancelDirectChallenge(challengeId: string) {
  if (!lobbyChannel || cancelingChallengeId.value || cancelingAllChallenges.value) return

  const challenge = lobbyChallenges.value.find(item => item.id === challengeId)
  cancelingChallengeId.value = challengeId
  directChallengeError.value = ''
  lobbyChannel.push('cancel_challenge', { challenge_id: challengeId })
    .receive('ok', () => {
      lobbyChallenges.value = lobbyChallenges.value.filter(item => item.id !== challengeId)
      cancelingChallengeId.value = ''
      directChallengeNotice.value = ''
      if (selectedOpponent.value?.id === challenge?.challenged.id) {
        selectedOpponent.value = null
        void navigateTo('/play', { replace: true })
      }
    })
    .receive('error', (error: { reason?: string }) => {
      cancelingChallengeId.value = ''
      directChallengeError.value = challengeErrorMessage(error.reason)
    })
}

function cancelAllChallenges() {
  if (searching.value) cancelMatchmaking()
  if (!lobbyChannel || !sentChallenges.value.length || cancelingAllChallenges.value) return

  cancelingAllChallenges.value = true
  directChallengeError.value = ''
  lobbyChannel.push('cancel_challenges', {})
    .receive('ok', () => {
      lobbyChallenges.value = lobbyChallenges.value.filter(challenge => challenge.challenger.id !== auth.user?.id)
      cancelingAllChallenges.value = false
      selectedOpponent.value = null
      directChallengeNotice.value = ''
      void navigateTo('/play', { replace: true })
    })
    .receive('error', () => {
      cancelingAllChallenges.value = false
      directChallengeError.value = 'Não foi possível cancelar os desafios.'
    })
}

function challengeRating(challenge: LobbyChallenge) {
  const category = challenge.time_control.id.startsWith('bullet') ? 'bullet'
    : challenge.time_control.id.startsWith('rapid') ? 'rapid'
      : 'blitz'
  return challenge.challenged.ratings?.[category] ?? challenge.challenged.rating
}

function challengeErrorMessage(reason?: string) {
  const messages: Record<string, string> = {
    challenge_already_exists: 'Você já desafiou esse jogador.',
    invalid_time_control: 'Escolha um ritmo de jogo válido.',
    user_not_found: 'Esse jogador não está disponível.',
    user_unavailable: 'Esse jogador não está recebendo desafios agora.',
    cannot_challenge_yourself: 'Você não pode desafiar a si mesmo.',
    challenge_not_found: 'Esse desafio não está mais disponível.',
    not_challenger: 'Somente quem enviou o desafio pode removê-lo.',
  }
  return messages[reason || ''] || 'Não foi possível enviar o desafio.'
}

async function copyPrivateRoomLink() {
  if (!privateRoomLink.value) return

  try {
    await navigator.clipboard.writeText(privateRoomLink.value)
    copyMessage.value = 'Link copiado'
  } catch {
    copyMessage.value = 'Selecione e copie o link'
  }
}

async function enterGame(match: MatchFound) {
  if (navigating) return
  navigating = true
  searching.value = false
  searchMessage.value = 'Partida encontrada! Abrindo o tabuleiro…'
  await navigateTo(`/game/${match.game_id}/live`)
}

function showError(reason: string) {
  const messages: Record<string, string> = {
    invalid_time_control: 'Escolha um ritmo de jogo válido.',
    queue_unavailable: 'A fila está indisponível no momento.',
    room_unavailable: 'Não foi possível criar o convite agora.',
    unauthorized: 'Sua sessão não tem permissão para essa ação.',
  }
  searching.value = false
  searchMessage.value = ''
  errorMessage.value = messages[reason] || 'Não foi possível concluir a ação.'
}
</script>

<template>
  <main class="play-page">
    <div class="play-shell">
      <section class="duel-preview" aria-labelledby="play-title">
        <header>
          <span class="eyebrow"><Swords :size="15" aria-hidden="true" /> NOVO DUELO</span>
          <h1 id="play-title">{{ selectedOpponent ? `Desafie ${selectedOpponent.nickname}` : sentChallenges.length ? 'Desafios enviados' : 'Prepare sua próxima partida' }}</h1>
          <p>{{ selectedOpponent ? 'Escolha o ritmo e envie um desafio direto para este jogador.' : sentChallenges.length ? 'Acompanhe os adversários desafiados ou adicione mais alguém à lista.' : 'Escolha o ritmo e encontre um adversário com rating próximo ao seu.' }}</p>
        </header>

        <div v-if="selectedOpponent && !pendingDirectChallenge" class="versus-card opponent-preview">
          <div class="player opponent">
            <ProfilePresenceAvatar v-if="selectedOpponent" :name="selectedOpponent.nickname" :avatar-url="selectedOpponent.avatar_url" :status="selectedOpponent.status" :size="58" />
            <span><small>Novo adversário</small><strong>{{ selectedOpponent.nickname }}</strong></span>
            <b>{{ opponentRating }}</b>
          </div>
        </div>

        <section v-if="sentChallenges.length" class="challenge-stack" aria-labelledby="sent-challenges-title">
          <header><div><strong>{{ auth.user?.nickname }}</strong><span>VS</span></div><small id="sent-challenges-title">{{ sentChallenges.length }} {{ sentChallenges.length === 1 ? 'jogador desafiado' : 'jogadores desafiados' }}</small></header>
          <article v-for="challenge in sentChallenges" :key="challenge.id" class="challenge-row">
            <ProfilePresenceAvatar :name="challenge.challenged.nickname" :avatar-url="challenge.challenged.avatar_url" :status="challenge.challenged.status" :size="48" />
            <span><strong>{{ challenge.challenged.nickname }}</strong><small>{{ challenge.time_control.label }}</small></span>
            <b>{{ challengeRating(challenge) }}</b>
            <button type="button" :disabled="!!cancelingChallengeId || cancelingAllChallenges" :aria-label="`Remover desafio para ${challenge.challenged.nickname}`" @click="cancelDirectChallenge(challenge.id)">{{ cancelingChallengeId === challenge.id ? 'Removendo…' : 'Remover' }}</button>
          </article>
        </section>

        <div v-if="!sentChallenges.length && (!selectedOpponent || pendingDirectChallenge)" class="versus-card opponent-preview">
          <div class="player opponent">
            <span class="avatar-placeholder"><Search :size="28" aria-hidden="true" /></span>
            <span><small>Seu adversário</small><strong>{{ opponentLoading ? 'Carregando…' : searching ? 'Procurando…' : 'Aguardando busca' }}</strong></span>
            <b>?</b>
          </div>
        </div>

        <div class="match-summary">
          <div><GameCategoryIcon :category="selectedControl.icon" :size="26" class="category-symbol" /><span><small>Ritmo escolhido</small><strong>{{ selectedControl.category }} {{ selectedControl.detail }}</strong></span></div>
          <div><ShieldCheck :size="21" aria-hidden="true" /><span><small>Tipo de partida</small><strong>Valendo rating</strong></span></div>
        </div>
      </section>

      <section class="duel-config" aria-label="Configurar duelo">
        <header><span>CONFIGURAÇÃO</span><h2>Nova partida</h2><p>Selecione quanto tempo cada jogador terá.</p></header>

        <fieldset :disabled="searching || creatingRoom || directChallengeSending || !!cancelingChallengeId || cancelingAllChallenges || !!pendingDirectChallenge">
          <legend>Ritmo da partida</legend>
          <div class="time-grid">
            <label v-for="control in timeControls" :key="control.id" :class="{ selected: selectedTimeControl === control.id }">
              <input v-model="selectedTimeControl" type="radio" name="time-control" :value="control.id">
              <GameCategoryIcon :category="control.icon" :size="28" class="category-symbol" />
              <span><strong>{{ control.label }}</strong><small>{{ control.category }} · {{ control.detail }}</small></span>
              <Check v-if="selectedTimeControl === control.id" :size="17" aria-hidden="true" />
            </label>
          </div>
        </fieldset>

        <button v-if="searching || pendingDirectChallenge || (sentChallenges.length && !selectedOpponent)" class="cancel-action" type="button" :disabled="cancelingAllChallenges" @click="cancelAllChallenges">{{ cancelingAllChallenges ? 'Cancelando…' : 'Cancelar busca' }}</button>
        <button v-else class="primary-action" type="button" :disabled="selectedOpponent ? !directChallengeReady || directChallengeSending : !connectionReady || creatingRoom" @click="selectedOpponent ? sendSelectedChallenge() : startMatchmaking()">
          <Swords v-if="selectedOpponent" :size="20" aria-hidden="true" /><Search v-else :size="20" aria-hidden="true" />
          {{ directChallengeSending ? 'Enviando desafio…' : selectedOpponent ? `Desafiar ${selectedOpponent.nickname}` : 'Começar partida' }}
        </button>

        <p v-if="searchMessage" class="search-status" role="status"><i /><span>{{ searchMessage }}</span></p>
        <p v-if="directChallengeNotice" class="search-status" role="status"><i /><span>{{ directChallengeNotice }}</span></p>
        <p v-if="directChallengeError" class="error" role="alert">{{ directChallengeError }}</p>
        <p v-if="errorMessage" class="error" role="alert">{{ errorMessage }}</p>

        <div class="divider"><span>ou</span></div>

        <button class="friend-action" type="button" :disabled="!directChallengeReady || searching" @click="challengeDialogOpen = true; directChallengeError = ''">
          <UserRoundPlus :size="21" aria-hidden="true" />
          <span><strong>Desafie alguém</strong><small>Busque pelo apelido ou compartilhe um link</small></span>
        </button>

        <div v-if="privateRoom" class="invite-box" aria-live="polite">
          <div><Link2 :size="18" aria-hidden="true" /><span><strong>Convite criado</strong><small>Aguardando seu amigo entrar</small></span></div>
          <div class="link-row"><input :value="privateRoomLink" readonly aria-label="Link da sala privada" @focus="($event.target as HTMLInputElement).select()"><button type="button" :aria-label="copyMessage || 'Copiar link'" @click="copyPrivateRoomLink"><Check v-if="copyMessage === 'Link copiado'" :size="17" /><Copy v-else :size="17" /></button></div>
          <small v-if="copyMessage">{{ copyMessage }}</small>
        </div>

        <NuxtLink class="players-link" to="/lobby"><Users :size="19" aria-hidden="true" /> Desafiar um jogador do lobby</NuxtLink>
      </section>
    </div>
    <ChallengesChallengePlayerDialog
      :open="challengeDialogOpen"
      :time-control-label="`${selectedControl.category} ${selectedControl.detail}`"
      :challenge-ready="directChallengeReady"
      :challenge-busy="directChallengeSending"
      :challenge-error="directChallengeError"
      :creating-link="creatingRoom"
      :invite-link="privateRoomLink"
      :copy-message="copyMessage"
      @close="challengeDialogOpen = false"
      @challenge="challengeByNickname"
      @create-link="createPrivateRoom"
      @copy-link="copyPrivateRoomLink"
    />
  </main>
</template>

<style scoped>
.category-symbol { color: var(--accent); }
.play-page { min-height: calc(100vh - 60px); color: var(--text); background-color: var(--bg); background-image: radial-gradient(color-mix(in srgb, var(--text-muted) 16%, transparent) .7px, transparent .7px); background-size: 5px 5px; }
.play-shell { display: grid; width: min(1180px, 100%); grid-template-columns: minmax(0, 1.05fr) minmax(390px, .8fr); gap: 1.4rem; margin: auto; padding: clamp(1.25rem, 3vw, 2.5rem); }
.duel-preview,.duel-config { background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 16px; box-shadow: var(--shadow); }
.duel-preview { display: grid; align-content: start; gap: 1.5rem; padding: clamp(1.5rem, 3vw, 2.5rem); background: linear-gradient(145deg,var(--surface),color-mix(in srgb,var(--surface-strong) 58%,var(--surface))); }
.duel-preview header { max-width: 560px; }.eyebrow { display: inline-flex; align-items: center; gap: .4rem; color: var(--accent); font-size: .7rem; font-weight: 800; letter-spacing: .1em; }.duel-preview h1 { margin: .7rem 0 .5rem; font-size: clamp(2rem,4vw,3.2rem); line-height: 1.05; letter-spacing: -.05em; }.duel-preview header p { margin: 0; color: var(--text-muted); line-height: 1.6; }
.versus-card { display: grid; overflow: hidden; background: var(--surface); border: 1px solid var(--border); border-radius: 14px; }.player { display: grid; grid-template-columns: 58px minmax(0,1fr) auto; align-items: center; gap: 1rem; padding: 1.25rem; }.player.opponent { background: var(--surface-strong); }.player > span:nth-child(2) { display: grid; gap: .25rem; }.player small,.match-summary small,.duel-config header span,.duel-config header p,.friend-action small,.invite-box small { color: var(--text-muted); }.player strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }.player > b { color: var(--accent); font-size: 1.05rem; }.avatar-placeholder { display: grid; width: 58px; height: 58px; place-items: center; color: var(--text-muted); background: var(--surface); border: 1px dashed var(--border); border-radius: 50%; }.versus-line { position: relative; height: 1px; background: var(--border); }.versus-line span { position: absolute; top: 50%; left: 50%; padding: .3rem .45rem; color: var(--text-muted); background: var(--surface); border: 1px solid var(--border); border-radius: 999px; font-size: .62rem; font-weight: 800; transform: translate(-50%,-50%); }
.challenge-stack { overflow: hidden; background: var(--surface); border: 1px solid var(--border); border-radius: 14px; }.challenge-stack > header { display: flex; align-items: center; justify-content: space-between; gap: 1rem; padding: .85rem 1rem; background: var(--surface-strong); border-bottom: 1px solid var(--border); }.challenge-stack > header div { display: flex; align-items: center; gap: .55rem; }.challenge-stack > header span { display: inline-grid; min-width: 30px; min-height: 30px; place-items: center; color: var(--accent); background: var(--surface); border: 1px solid var(--border); border-radius: 999px; font-size: .65rem; font-weight: 850; }.challenge-stack > header small,.challenge-row small { color: var(--text-muted); }.challenge-row { display: grid; grid-template-columns: 48px minmax(0,1fr) auto auto; align-items: center; gap: .85rem; padding: .9rem 1rem; border-bottom: 1px solid var(--border-subtle); }.challenge-row:last-child { border-bottom: 0; }.challenge-row > span { display: grid; gap: .2rem; min-width: 0; }.challenge-row strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }.challenge-row b { color: var(--accent); }.challenge-row button { padding: .5rem .7rem; color: var(--danger); background: var(--danger-soft); border: 1px solid color-mix(in srgb,var(--danger) 35%,var(--border)); border-radius: 8px; font-weight: 750; cursor: pointer; }.challenge-row button:disabled { opacity: .55; cursor: default; }
.match-summary { display: grid; grid-template-columns: 1fr 1fr; gap: .75rem; }.match-summary > div { display: flex; align-items: center; gap: .7rem; padding: .9rem; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 10px; }.match-summary svg { color: var(--accent); }.match-summary span { display: grid; gap: .15rem; }.match-summary strong { font-size: .83rem; }
.duel-config { display: grid; align-content: start; gap: 1rem; padding: clamp(1.25rem,2.5vw,2rem); }.duel-config header span { font-size: .67rem; font-weight: 800; letter-spacing: .11em; }.duel-config h2 { margin: .35rem 0 .3rem; font-size: 1.55rem; }.duel-config header p { margin: 0; font-size: .86rem; }fieldset { min-width: 0; margin: .35rem 0 0; padding: 0; border: 0; }legend { margin-bottom: .7rem; font-size: .78rem; font-weight: 750; }.time-grid { display: grid; grid-template-columns: 1fr 1fr; gap: .6rem; }.time-grid label { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: .65rem; padding: .8rem; color: var(--text); background: var(--surface-strong); border: 1px solid var(--border); border-radius: 10px; cursor: pointer; }.time-grid label:hover,.time-grid label.selected { border-color: var(--accent); }.time-grid label.selected { background: color-mix(in srgb,var(--accent) 10%,var(--surface-strong)); }.time-grid input { position: absolute; width: 1px; height: 1px; opacity: 0; }.time-grid label > svg { color: var(--accent); }.time-grid span { display: grid; gap: .12rem; }.time-grid small { color: var(--text-muted); font-size: .68rem; }
.primary-action,.cancel-action,.friend-action { display: flex; width: 100%; align-items: center; justify-content: center; gap: .65rem; border-radius: 10px; cursor: pointer; }.primary-action { min-height: 50px; color: var(--accent-ink); background: var(--accent); border: 1px solid var(--accent); font-size: .95rem; font-weight: 800; }.primary-action:hover:not(:disabled) { background: var(--accent-hover); }.primary-action:disabled,.friend-action:disabled { opacity: .55; cursor: not-allowed; }.cancel-action { min-height: 50px; color: white; background: var(--danger); border: 1px solid var(--danger); font-weight: 800; }.friend-action { justify-content: flex-start; padding: .85rem 1rem; color: var(--text); background: var(--surface-strong); border: 1px solid var(--border); text-align: left; }.friend-action:hover:not(:disabled) { border-color: var(--accent); }.friend-action span { display: grid; gap: .2rem; }.friend-action small { font-size: .7rem; }.divider { display: flex; align-items: center; gap: .7rem; color: var(--text-muted); font-size: .7rem; }.divider::before,.divider::after { height: 1px; flex: 1; content: ''; background: var(--border-subtle); }
.search-status { display: flex; align-items: center; gap: .6rem; margin: 0; padding: .75rem; color: var(--text-muted); background: var(--surface-strong); border-radius: 9px; font-size: .78rem; }.search-status i { width: 8px; height: 8px; flex: 0 0 auto; background: var(--success); border-radius: 50%; box-shadow: 0 0 7px var(--success); animation: pulse 1.1s infinite; }@keyframes pulse { 50% { opacity: .35; transform: scale(.75); } }.error { margin: 0; padding: .75rem; color: var(--danger); background: var(--danger-soft); border-radius: 9px; font-size: .8rem; }
.invite-box { display: grid; gap: .7rem; padding: .85rem; background: var(--success-soft); border: 1px solid color-mix(in srgb,var(--success) 30%,var(--border)); border-radius: 10px; }.invite-box > div:first-child { display: flex; align-items: center; gap: .6rem; }.invite-box > div:first-child > span { display: grid; gap: .15rem; }.invite-box svg { color: var(--success); }.link-row { display: grid; grid-template-columns: minmax(0,1fr) auto; }.link-row input { min-width: 0; padding: .65rem; color: var(--text); background: var(--surface); border: 1px solid var(--border); border-radius: 8px 0 0 8px; }.link-row button { display: grid; width: 42px; place-items: center; background: var(--surface-strong); border: 1px solid var(--border); border-left: 0; border-radius: 0 8px 8px 0; cursor: pointer; }.players-link { display: flex; align-items: center; justify-content: center; gap: .5rem; padding: .55rem; color: var(--text-muted); font-size: .78rem; text-decoration: none; }.players-link:hover { color: var(--accent); }
@media (max-width: 900px) { .play-shell { grid-template-columns: 1fr; }.duel-preview h1 { font-size: 2.25rem; } }
@media (max-width: 560px) { .play-shell { padding: 1rem; }.duel-preview,.duel-config { padding: 1.1rem; border-radius: 12px; }.match-summary,.time-grid { grid-template-columns: 1fr; }.player { grid-template-columns: 50px minmax(0,1fr) auto; padding: 1rem; }.avatar-placeholder { width: 50px; height: 50px; }.challenge-stack > header { align-items: flex-start; flex-direction: column; }.challenge-row { grid-template-columns: 42px minmax(0,1fr) auto; }.challenge-row > b { grid-column: 3; grid-row: 1; }.challenge-row button { grid-column: 2 / -1; width: 100%; } }
@media (prefers-reduced-motion: reduce) { .search-status i { animation: none; } }
</style>
