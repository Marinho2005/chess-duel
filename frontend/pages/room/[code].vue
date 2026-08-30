<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'

definePageMeta({ middleware: 'game-session', layout: false })

const auth = useAuthStore()
const route = useRoute()
const config = useRuntimeConfig()
const status = ref('Entrando na sala privada...')
const errorMessage = ref('')
let socket: Socket | null = null
let channel: Channel | null = null
let navigating = false

const code = computed(() => String(route.params.code || '').trim().toUpperCase())

onMounted(async () => {
  auth.restoreSession()
  if (!auth.token || (!auth.isGuest && !(await auth.fetchCurrentUser())) || !auth.identityId) return

  const websocketUrl = `${config.public.api.baseURL.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  socket = new Socket(websocketUrl, { params: { token: auth.token } })
  socket.connect()
  channel = socket.channel(`private_rooms:${auth.identityId}`, {})
  channel.join()
    .receive('ok', joinRoom)
    .receive('error', () => showError('unauthorized'))
  channel.on('match_found', enterGame)
  socket.onError(() => { status.value = 'Reconectando à sala...' })
})

onBeforeUnmount(() => {
  channel?.leave()
  socket?.disconnect()
})

function joinRoom() {
  channel?.push('join_room', { code: code.value })
    .receive('ok', (response: { state: 'waiting' | 'matched'; game_id?: string }) => {
      if (response.state === 'matched' && response.game_id) {
        enterGame({ game_id: response.game_id })
      } else {
        status.value = 'Sala criada. Aguardando o segundo jogador...'
      }
    })
    .receive('error', (error: { reason?: string }) => showError(error.reason || 'room_unavailable'))
}

async function enterGame(match: { game_id: string }) {
  if (navigating) return
  navigating = true
  status.value = 'Oponente encontrado! Iniciando a partida...'
  await navigateTo(`/game/${match.game_id}/live`)
}

function showError(reason: string) {
  const messages: Record<string, string> = {
    room_not_found: 'Esta sala não existe ou já expirou.',
    room_full: 'Esta sala já está cheia e a partida começou.',
    identity_mismatch: auth.isGuest
      ? 'Esta sala foi criada para usuários autenticados. Entre com uma conta para participar.'
      : 'Esta sala foi criada para convidados. Abra o link em uma sessão de convidado.',
    unauthorized: 'Sua sessão não tem permissão para acessar esta sala.',
    room_unavailable: 'Não foi possível acessar a sala privada.'
  }
  errorMessage.value = messages[reason] || messages.room_unavailable
  status.value = 'Não foi possível entrar'
}

async function goBack() {
  await navigateTo(auth.isGuest ? '/guest' : '/lobby')
}
</script>

<template>
  <main class="room-shell">
    <section class="room-card">
      <span class="badge">SALA {{ code }}</span>
      <div class="piece" aria-hidden="true">♞</div>
      <h1>{{ status }}</h1>
      <template v-if="!errorMessage">
        <div class="searching" aria-label="Aguardando oponente"><i /><i /><i /></div>
        <p>Mantenha esta página aberta. Você será levado automaticamente para a partida.</p>
      </template>
      <template v-else>
        <p class="error" role="alert">{{ errorMessage }}</p>
        <button type="button" @click="goBack">{{ auth.isGuest ? 'Voltar ao modo convidado' : 'Voltar ao lobby' }}</button>
      </template>
    </section>
  </main>
</template>

<style scoped>
.room-shell { display: grid; min-height: 100vh; place-items: center; padding: 1rem; color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e40 .7px, transparent .7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
.room-card { display: grid; width: min(480px, 100%); justify-items: center; gap: 1rem; padding: 2.2rem; text-align: center; background: #fffaf0e8; border: 1px solid #e8dac4; border-radius: 18px; box-shadow: 0 20px 45px #6f45281c; }.badge { padding: .35rem .65rem; color: #7f5130; background: #ead7bc; border-radius: 999px; font-size: .7rem; font-weight: 800; letter-spacing: .1em; }.piece { color: #6f4528; font-size: 4rem; line-height: 1; }.room-card h1 { margin: 0; font: 500 1.8rem Georgia, serif; }.room-card p { margin: 0; color: #806d5d; }.room-card button { padding: .75rem 1rem; color: white; background: #6f4528; border: 1px solid #6f4528; border-radius: 9px; cursor: pointer; }.error { padding: .9rem; color: #a23f30 !important; background: #f9ded5; border-radius: 10px; }.searching { display: flex; gap: .5rem; padding: .8rem; }.searching i { width: 10px; height: 10px; background: #668a57; border-radius: 50%; animation: pulse 1.2s infinite; }.searching i:nth-child(2) { animation-delay: .2s; }.searching i:nth-child(3) { animation-delay: .4s; }@keyframes pulse { 50% { opacity: .25; transform: scale(.75); } }
</style>
