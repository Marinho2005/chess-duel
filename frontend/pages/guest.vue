<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'

definePageMeta({ layout: false })

type TimeControlId = 'bullet_1_0' | 'blitz_3_0' | 'blitz_5_0' | 'rapid_10_0'
type PrivateRoom = { code: string; time_control: { label: string } }

const timeControls = [
  { id: 'bullet_1_0', label: 'Bullet 1+0' },
  { id: 'blitz_3_0', label: 'Blitz 3+0' },
  { id: 'blitz_5_0', label: 'Blitz 5+0' },
  { id: 'rapid_10_0', label: 'Rapid 10+0' }
] as const

const auth = useAuthStore()
const config = useRuntimeConfig()
const status = ref('Escolha como deseja jogar.')
const errorMessage = ref('')
const selectedTimeControl = ref<TimeControlId>('blitz_3_0')
const searching = ref(false)
const creatingRoom = ref(false)
const privateRoom = ref<PrivateRoom | null>(null)
const copyMessage = ref('')
let socket: Socket | null = null
let matchmakingChannel: Channel | null = null
let privateRoomChannel: Channel | null = null

const privateRoomLink = computed(() => privateRoom.value && import.meta.client
  ? `${window.location.origin}/room/${privateRoom.value.code}`
  : '')

onMounted(async () => {
  if (!auth.token || !auth.guest) {
    await navigateTo('/?session=expired')
    return
  }

  const websocketUrl = `${config.public.api.baseURL.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  socket = new Socket(websocketUrl, { params: { token: auth.token } })
  socket.connect()

  matchmakingChannel = socket.channel(`guest_matchmaking:${auth.guest.id}`, {})
  matchmakingChannel.join().receive('error', () => showError('Não foi possível acessar a fila de convidados.'))
  matchmakingChannel.on('match_found', enterGame)

  privateRoomChannel = socket.channel(`private_rooms:${auth.guest.id}`, {})
  privateRoomChannel.join().receive('error', () => showError('Não foi possível acessar as salas privadas.'))
  privateRoomChannel.on('match_found', enterGame)

  socket.onError(() => { status.value = 'Reconectando...' })
  socket.onClose(() => { errorMessage.value = 'A conexão foi interrompida.' })
})

onBeforeUnmount(() => {
  if (searching.value) matchmakingChannel?.push('leave_queue', {})
  matchmakingChannel?.leave()
  privateRoomChannel?.leave()
  socket?.disconnect()
})

function startSearch() {
  if (!matchmakingChannel || searching.value) return
  errorMessage.value = ''
  status.value = 'Procurando outro convidado...'
  matchmakingChannel.push('join_queue', {})
    .receive('ok', () => { searching.value = true })
    .receive('error', () => showError('Não foi possível entrar na fila de convidados.'))
}

function cancelSearch() {
  matchmakingChannel?.push('leave_queue', {})
    .receive('ok', () => {
      searching.value = false
      status.value = 'Busca cancelada. Escolha como deseja jogar.'
    })
}

function createPrivateRoom() {
  if (!privateRoomChannel || creatingRoom.value) return
  creatingRoom.value = true
  errorMessage.value = ''
  copyMessage.value = ''
  privateRoomChannel.push('create_room', { time_control: selectedTimeControl.value })
    .receive('ok', (room: PrivateRoom) => {
      privateRoom.value = room
      creatingRoom.value = false
      status.value = 'Sala criada. Compartilhe o link com outro convidado.'
    })
    .receive('error', () => {
      creatingRoom.value = false
      showError('Não foi possível criar a sala privada.')
    })
}

async function copyPrivateRoomLink() {
  if (!privateRoomLink.value) return
  try {
    await navigator.clipboard.writeText(privateRoomLink.value)
    copyMessage.value = 'Link copiado!'
  } catch {
    copyMessage.value = 'Selecione o link e copie manualmente.'
  }
}

async function enterGame(match: { game_id: string }) {
  status.value = 'Oponente encontrado! Entrando na partida...'
  await navigateTo(`/game/${match.game_id}/live`)
}

function showError(message: string) {
  errorMessage.value = message
}

async function leave() {
  await auth.logOut()
  await navigateTo('/')
}
</script>

<template>
  <main class="guest-shell">
    <section class="guest-card">
      <span class="badge">CONVIDADO</span>
      <BrandLogo class="piece" :show-word="false" aria-hidden="true" />
      <h1>Olá, {{ auth.guest?.nickname }}</h1>
      <p>{{ status }}</p>

      <label class="time-control">
        <span>Formato da sala privada</span>
        <select v-model="selectedTimeControl" :disabled="creatingRoom || searching">
          <option v-for="control in timeControls" :key="control.id" :value="control.id">{{ control.label }}</option>
        </select>
      </label>

      <div class="choices">
        <button v-if="!searching" class="primary" type="button" :disabled="creatingRoom" @click="startSearch">Buscar convidado</button>
        <button v-else class="danger" type="button" @click="cancelSearch">Cancelar busca</button>
        <button class="secondary" type="button" :disabled="creatingRoom || searching" @click="createPrivateRoom">
          {{ creatingRoom ? 'Criando...' : 'Criar sala privada' }}
        </button>
      </div>

      <div v-if="searching" class="searching" aria-label="Busca em andamento"><i /><i /><i /></div>

      <div v-if="privateRoom" class="room-waiting">
        <p><span class="waiting-dot" /> Aguardando seu amigo em {{ privateRoom.time_control.label }}...</p>
        <div class="room-link-row">
          <input :value="privateRoomLink" readonly aria-label="Link da sala privada" @focus="($event.target as HTMLInputElement).select()">
          <button type="button" @click="copyPrivateRoomLink">Copiar link</button>
        </div>
        <small>{{ copyMessage || 'A sala expira em aproximadamente 20 minutos.' }}</small>
      </div>

      <p v-if="errorMessage" class="error">{{ errorMessage }}</p>
      <small>Partidas casuais não salvam histórico nem alteram rating.</small>
      <button class="leave" type="button" @click="leave">Encerrar sessão e voltar</button>
    </section>
  </main>
</template>

<style scoped>
.guest-shell { display: grid; min-height: 100vh; place-items: center; padding: 1rem; color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e40 .7px, transparent .7px); background-size: 5px 5px; font-family: var(--font-sans); }
.guest-card { display: grid; width: min(540px, 100%); justify-items: center; gap: 1rem; padding: 2.2rem; text-align: center; background: #fffaf0e8; border: 1px solid #e8dac4; border-radius: 18px; box-shadow: 0 20px 45px rgb(0 0 0 / 14%); }
.badge { padding: .35rem .65rem; color: #7f5130; background: #ead7bc; border-radius: 999px; font-size: .7rem; font-weight: 800; letter-spacing: .1em; }
.piece { color: #6f4528; font-size: 4rem; line-height: 1; }.guest-card h1 { margin: 0; font: 500 1.8rem var(--font-serif); }.guest-card p { margin: 0; color: #806d5d; }.guest-card > small, .room-waiting small { color: #8b7664; }
.time-control { display: grid; width: 100%; gap: .45rem; color: #806d5d; font-size: .85rem; text-align: left; }.time-control select, .room-link-row input { min-width: 0; padding: .75rem; color: #3c2b20; background: #fffaf0; border: 1px solid #d9c7ae; border-radius: 9px; font: inherit; }
.choices { display: grid; width: 100%; grid-template-columns: 1fr 1fr; gap: .7rem; }.choices button, .room-link-row button, .leave { padding: .75rem 1rem; border: 1px solid #d9c7ae; border-radius: 9px; cursor: pointer; }.choices button:disabled { opacity: .6; cursor: default; }.primary { color: white; background: #6f4528; }.secondary { color: #7f5130; background: #f7eedf; }.danger { color: white; background: #a74c35; }
.searching { display: flex; gap: .5rem; padding: .8rem; }.searching i { width: 10px; height: 10px; background: #668a57; border-radius: 50%; animation: pulse 1.2s infinite; }.searching i:nth-child(2) { animation-delay: .2s; }.searching i:nth-child(3) { animation-delay: .4s; }@keyframes pulse { 50% { opacity: .25; transform: scale(.75); } }
.room-waiting { display: grid; width: 100%; gap: .7rem; padding: 1rem; background: #efe3cf; border: 1px solid #d9c7ae; border-radius: 12px; }.room-waiting p { display: flex; align-items: center; justify-content: center; gap: .5rem; }.waiting-dot { width: 9px; height: 9px; background: #668a57; border-radius: 50%; box-shadow: none; animation: pulse 1.2s infinite; }.room-link-row { display: grid; grid-template-columns: 1fr auto; gap: .6rem; }.room-link-row button { color: #7f5130; background: #fffaf0; }
.leave { color: #7f5130; background: transparent; }.error { color: #a23f30 !important; }
@media (max-width: 520px) { .guest-card { padding: 1.4rem; }.choices, .room-link-row { grid-template-columns: 1fr; } }

.guest-shell { color:var(--text); background:var(--bg); }
.guest-card { color:var(--text); background:color-mix(in srgb,var(--surface) 96%,transparent); border-color:var(--border); box-shadow:var(--shadow); }
.badge { color:var(--accent); background:color-mix(in srgb,var(--accent) 14%,var(--surface-strong)); }
.piece { color:var(--accent); }
.guest-card p,.guest-card>small,.room-waiting small,.time-control { color:var(--text-muted); }
.time-control select,.room-link-row input { color:var(--text); background:var(--surface-strong); border-color:var(--border); }
.choices button,.room-link-row button,.leave { border-color:var(--border); }
.primary { color:var(--accent-ink); background:var(--accent); border-color:var(--accent) !important; }
.primary:hover { background:var(--accent-hover); }
.secondary,.room-link-row button,.leave { color:var(--text); background:var(--surface-strong); }
.secondary:hover,.room-link-row button:hover,.leave:hover { color:var(--accent); background:var(--surface-hover); }
.danger { color:var(--accent-ink); background:var(--danger); border-color:var(--danger) !important; }
.room-waiting { background:var(--surface-strong); border-color:var(--border); }
.searching i,.waiting-dot { background:var(--success); box-shadow: none; }
.error { color:var(--danger) !important; }
</style>
