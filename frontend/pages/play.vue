<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'
import { Check, Clock3, Copy, Flame, Link2, Rocket, Search, ShieldCheck, Swords, UserRoundPlus, Users } from 'lucide-vue-next'

definePageMeta({ middleware: 'auth', layout: 'default' })

type TimeControlId = 'bullet_1_0' | 'blitz_3_0' | 'blitz_5_0' | 'rapid_10_0'
type TimeControl = { id: TimeControlId; label: string; detail: string; category: string; icon: typeof Rocket }
type PrivateRoom = { code: string; time_control: { label: string }; expires_at: string }
type MatchFound = { game_id: string }

const timeControls: TimeControl[] = [
  { id: 'bullet_1_0', label: '1 min', detail: '1+0', category: 'Bullet', icon: Rocket },
  { id: 'blitz_3_0', label: '3 min', detail: '3+0', category: 'Blitz', icon: Flame },
  { id: 'blitz_5_0', label: '5 min', detail: '5+0', category: 'Blitz', icon: Flame },
  { id: 'rapid_10_0', label: '10 min', detail: '10+0', category: 'Rapid', icon: Clock3 },
]

const auth = useAuthStore()
const config = useRuntimeConfig()
const selectedTimeControl = ref<TimeControlId>('blitz_3_0')
const connectionReady = ref(false)
const searching = ref(false)
const searchMessage = ref('')
const errorMessage = ref('')
const creatingRoom = ref(false)
const privateRoom = ref<PrivateRoom | null>(null)
const copyMessage = ref('')
let socket: Socket | null = null
let matchmakingChannel: Channel | null = null
let privateRoomChannel: Channel | null = null
let navigating = false

const selectedControl = computed(() => timeControls.find(control => control.id === selectedTimeControl.value) || timeControls[1]!)
const privateRoomLink = computed(() => privateRoom.value && import.meta.client
  ? `${window.location.origin}/room/${privateRoom.value.code}`
  : '')

onMounted(() => {
  if (!auth.token || !auth.user) return

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

  socket.onError(() => {
    connectionReady.value = false
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
    .receive('error', (error: { reason?: string }) => showError(error.reason || 'queue_unavailable'))
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
          <h1 id="play-title">Prepare sua próxima partida</h1>
          <p>Escolha o ritmo e encontre um adversário com rating próximo ao seu.</p>
        </header>

        <div class="versus-card">
          <div class="player opponent">
            <span class="avatar-placeholder"><Search :size="28" aria-hidden="true" /></span>
            <span><small>Seu adversário</small><strong>{{ searching ? 'Procurando…' : 'Aguardando busca' }}</strong></span>
            <b>?</b>
          </div>
          <div class="versus-line"><span>VS</span></div>
          <div class="player">
            <ProfilePresenceAvatar :name="auth.user?.nickname || 'Você'" :avatar-url="auth.user?.avatar_url" :status="auth.presence" :size="58" />
            <span><small>Você</small><strong>{{ auth.user?.nickname }}</strong></span>
            <b>{{ auth.user?.rating }}</b>
          </div>
        </div>

        <div class="match-summary">
          <div><component :is="selectedControl.icon" :size="21" aria-hidden="true" /><span><small>Ritmo escolhido</small><strong>{{ selectedControl.category }} {{ selectedControl.detail }}</strong></span></div>
          <div><ShieldCheck :size="21" aria-hidden="true" /><span><small>Tipo de partida</small><strong>Valendo rating</strong></span></div>
        </div>
      </section>

      <section class="duel-config" aria-label="Configurar duelo">
        <header><span>CONFIGURAÇÃO</span><h2>Nova partida</h2><p>Selecione quanto tempo cada jogador terá.</p></header>

        <fieldset :disabled="searching || creatingRoom">
          <legend>Ritmo da partida</legend>
          <div class="time-grid">
            <label v-for="control in timeControls" :key="control.id" :class="{ selected: selectedTimeControl === control.id }">
              <input v-model="selectedTimeControl" type="radio" name="time-control" :value="control.id">
              <component :is="control.icon" :size="20" aria-hidden="true" />
              <span><strong>{{ control.label }}</strong><small>{{ control.category }} · {{ control.detail }}</small></span>
              <Check v-if="selectedTimeControl === control.id" :size="17" aria-hidden="true" />
            </label>
          </div>
        </fieldset>

        <button v-if="!searching" class="primary-action" type="button" :disabled="!connectionReady || creatingRoom" @click="startMatchmaking">
          <Search :size="20" aria-hidden="true" /> Começar partida
        </button>
        <button v-else class="cancel-action" type="button" @click="cancelMatchmaking">Cancelar busca</button>

        <p v-if="searchMessage" class="search-status" role="status"><i /><span>{{ searchMessage }}</span></p>
        <p v-if="errorMessage" class="error" role="alert">{{ errorMessage }}</p>

        <div class="divider"><span>ou</span></div>

        <button class="friend-action" type="button" :disabled="!connectionReady || creatingRoom || searching" @click="createPrivateRoom">
          <UserRoundPlus :size="21" aria-hidden="true" />
          <span><strong>{{ creatingRoom ? 'Criando convite…' : 'Jogar com um amigo' }}</strong><small>Crie uma sala privada e compartilhe o link</small></span>
        </button>

        <div v-if="privateRoom" class="invite-box" aria-live="polite">
          <div><Link2 :size="18" aria-hidden="true" /><span><strong>Convite criado</strong><small>Aguardando seu amigo entrar</small></span></div>
          <div class="link-row"><input :value="privateRoomLink" readonly aria-label="Link da sala privada" @focus="($event.target as HTMLInputElement).select()"><button type="button" :aria-label="copyMessage || 'Copiar link'" @click="copyPrivateRoomLink"><Check v-if="copyMessage === 'Link copiado'" :size="17" /><Copy v-else :size="17" /></button></div>
          <small v-if="copyMessage">{{ copyMessage }}</small>
        </div>

        <NuxtLink class="players-link" to="/lobby"><Users :size="19" aria-hidden="true" /> Desafiar um jogador do lobby</NuxtLink>
      </section>
    </div>
  </main>
</template>

<style scoped>
.play-page { min-height: calc(100vh - 60px); color: var(--text); background-color: var(--bg); background-image: radial-gradient(color-mix(in srgb, var(--text-muted) 16%, transparent) .7px, transparent .7px); background-size: 5px 5px; }
.play-shell { display: grid; width: min(1180px, 100%); grid-template-columns: minmax(0, 1.05fr) minmax(390px, .8fr); gap: 1.4rem; margin: auto; padding: clamp(1.25rem, 3vw, 2.5rem); }
.duel-preview,.duel-config { background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 16px; box-shadow: var(--shadow); }
.duel-preview { display: grid; align-content: start; gap: 1.5rem; padding: clamp(1.5rem, 3vw, 2.5rem); background: linear-gradient(145deg,var(--surface),color-mix(in srgb,var(--surface-strong) 58%,var(--surface))); }
.duel-preview header { max-width: 560px; }.eyebrow { display: inline-flex; align-items: center; gap: .4rem; color: var(--accent); font-size: .7rem; font-weight: 800; letter-spacing: .1em; }.duel-preview h1 { margin: .7rem 0 .5rem; font-size: clamp(2rem,4vw,3.2rem); line-height: 1.05; letter-spacing: -.05em; }.duel-preview header p { margin: 0; color: var(--text-muted); line-height: 1.6; }
.versus-card { display: grid; overflow: hidden; background: var(--surface); border: 1px solid var(--border); border-radius: 14px; }.player { display: grid; grid-template-columns: 58px minmax(0,1fr) auto; align-items: center; gap: 1rem; padding: 1.25rem; }.player.opponent { background: var(--surface-strong); }.player > span:nth-child(2) { display: grid; gap: .25rem; }.player small,.match-summary small,.duel-config header span,.duel-config header p,.friend-action small,.invite-box small { color: var(--text-muted); }.player strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }.player > b { color: var(--accent); font-size: 1.05rem; }.avatar-placeholder { display: grid; width: 58px; height: 58px; place-items: center; color: var(--text-muted); background: var(--surface); border: 1px dashed var(--border); border-radius: 50%; }.versus-line { position: relative; height: 1px; background: var(--border); }.versus-line span { position: absolute; top: 50%; left: 50%; padding: .3rem .45rem; color: var(--text-muted); background: var(--surface); border: 1px solid var(--border); border-radius: 999px; font-size: .62rem; font-weight: 800; transform: translate(-50%,-50%); }
.match-summary { display: grid; grid-template-columns: 1fr 1fr; gap: .75rem; }.match-summary > div { display: flex; align-items: center; gap: .7rem; padding: .9rem; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 10px; }.match-summary svg { color: var(--accent); }.match-summary span { display: grid; gap: .15rem; }.match-summary strong { font-size: .83rem; }
.duel-config { display: grid; align-content: start; gap: 1rem; padding: clamp(1.25rem,2.5vw,2rem); }.duel-config header span { font-size: .67rem; font-weight: 800; letter-spacing: .11em; }.duel-config h2 { margin: .35rem 0 .3rem; font-size: 1.55rem; }.duel-config header p { margin: 0; font-size: .86rem; }fieldset { min-width: 0; margin: .35rem 0 0; padding: 0; border: 0; }legend { margin-bottom: .7rem; font-size: .78rem; font-weight: 750; }.time-grid { display: grid; grid-template-columns: 1fr 1fr; gap: .6rem; }.time-grid label { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: .65rem; padding: .8rem; color: var(--text); background: var(--surface-strong); border: 1px solid var(--border); border-radius: 10px; cursor: pointer; }.time-grid label:hover,.time-grid label.selected { border-color: var(--accent); }.time-grid label.selected { background: color-mix(in srgb,var(--accent) 10%,var(--surface-strong)); }.time-grid input { position: absolute; width: 1px; height: 1px; opacity: 0; }.time-grid label > svg { color: var(--accent); }.time-grid span { display: grid; gap: .12rem; }.time-grid small { color: var(--text-muted); font-size: .68rem; }
.primary-action,.cancel-action,.friend-action { display: flex; width: 100%; align-items: center; justify-content: center; gap: .65rem; border-radius: 10px; cursor: pointer; }.primary-action { min-height: 50px; color: var(--accent-ink); background: var(--accent); border: 1px solid var(--accent); font-size: .95rem; font-weight: 800; }.primary-action:hover:not(:disabled) { background: var(--accent-hover); }.primary-action:disabled,.friend-action:disabled { opacity: .55; cursor: not-allowed; }.cancel-action { min-height: 50px; color: white; background: var(--danger); border: 1px solid var(--danger); font-weight: 800; }.friend-action { justify-content: flex-start; padding: .85rem 1rem; color: var(--text); background: var(--surface-strong); border: 1px solid var(--border); text-align: left; }.friend-action:hover:not(:disabled) { border-color: var(--accent); }.friend-action span { display: grid; gap: .2rem; }.friend-action small { font-size: .7rem; }.divider { display: flex; align-items: center; gap: .7rem; color: var(--text-muted); font-size: .7rem; }.divider::before,.divider::after { height: 1px; flex: 1; content: ''; background: var(--border-subtle); }
.search-status { display: flex; align-items: center; gap: .6rem; margin: 0; padding: .75rem; color: var(--text-muted); background: var(--surface-strong); border-radius: 9px; font-size: .78rem; }.search-status i { width: 8px; height: 8px; flex: 0 0 auto; background: var(--success); border-radius: 50%; box-shadow: 0 0 7px var(--success); animation: pulse 1.1s infinite; }@keyframes pulse { 50% { opacity: .35; transform: scale(.75); } }.error { margin: 0; padding: .75rem; color: var(--danger); background: var(--danger-soft); border-radius: 9px; font-size: .8rem; }
.invite-box { display: grid; gap: .7rem; padding: .85rem; background: var(--success-soft); border: 1px solid color-mix(in srgb,var(--success) 30%,var(--border)); border-radius: 10px; }.invite-box > div:first-child { display: flex; align-items: center; gap: .6rem; }.invite-box > div:first-child > span { display: grid; gap: .15rem; }.invite-box svg { color: var(--success); }.link-row { display: grid; grid-template-columns: minmax(0,1fr) auto; }.link-row input { min-width: 0; padding: .65rem; color: var(--text); background: var(--surface); border: 1px solid var(--border); border-radius: 8px 0 0 8px; }.link-row button { display: grid; width: 42px; place-items: center; background: var(--surface-strong); border: 1px solid var(--border); border-left: 0; border-radius: 0 8px 8px 0; cursor: pointer; }.players-link { display: flex; align-items: center; justify-content: center; gap: .5rem; padding: .55rem; color: var(--text-muted); font-size: .78rem; text-decoration: none; }.players-link:hover { color: var(--accent); }
@media (max-width: 900px) { .play-shell { grid-template-columns: 1fr; }.duel-preview h1 { font-size: 2.25rem; } }
@media (max-width: 560px) { .play-shell { padding: 1rem; }.duel-preview,.duel-config { padding: 1.1rem; border-radius: 12px; }.match-summary,.time-grid { grid-template-columns: 1fr; }.player { grid-template-columns: 50px minmax(0,1fr) auto; padding: 1rem; }.avatar-placeholder { width: 50px; height: 50px; } }
@media (prefers-reduced-motion: reduce) { .search-status i { animation: none; } }
</style>
