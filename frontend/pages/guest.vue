<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'

const auth = useAuthStore()
const config = useRuntimeConfig()
const status = ref('Preparando sua sessão temporária...')
const errorMessage = ref('')
let socket: Socket | null = null
let channel: Channel | null = null

onMounted(async () => {
  if (!auth.token || !auth.guest) {
    await navigateTo('/?session=expired')
    return
  }

  const websocketUrl = `${config.public.api.baseURL.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  socket = new Socket(websocketUrl, { params: { token: auth.token } })
  socket.connect()

  channel = socket.channel(`guest_matchmaking:${auth.guest.id}`, {})
  channel.join()
    .receive('ok', () => {
      status.value = 'Procurando outro convidado...'
      channel?.push('join_queue', {})
        .receive('error', showError)
    })
    .receive('error', showError)

  channel.on('match_found', async (match: { game_id: string }) => {
    status.value = 'Oponente encontrado! Entrando na partida...'
    await navigateTo(`/game/${match.game_id}`)
  })

  socket.onError(() => { status.value = 'Reconectando à fila...' })
  socket.onClose(() => { errorMessage.value = 'A conexão com a fila foi interrompida.' })
})

onBeforeUnmount(() => {
  channel?.push('leave_queue', {})
  channel?.leave()
  socket?.disconnect()
})

function showError() {
  errorMessage.value = 'Não foi possível entrar na fila de convidados.'
}

async function leave() {
  await auth.logOut()
  await navigateTo('/')
}
</script>

<template>
  <main class="guest-shell">
    <section class="search-card">
      <span class="badge">CONVIDADO</span>
      <div class="piece" aria-hidden="true">♟</div>
      <h1>Olá, {{ auth.guest?.nickname }}</h1>
      <p>{{ status }}</p>
      <div class="searching" aria-label="Busca em andamento"><i /><i /><i /></div>
      <p v-if="errorMessage" class="error">{{ errorMessage }}</p>
      <small>Partidas casuais não salvam histórico nem alteram rating.</small>
      <button type="button" @click="leave">Cancelar e voltar</button>
    </section>
  </main>
</template>

<style scoped>
.guest-shell { display: grid; min-height: 100vh; place-items: center; padding: 1rem; color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e40 .7px, transparent .7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
.search-card { display: grid; width: min(440px, 100%); justify-items: center; gap: 1rem; padding: 2.2rem; text-align: center; background: #fffaf0e8; border: 1px solid #e8dac4; border-radius: 18px; box-shadow: 0 20px 45px #60401f1c; }
.badge { padding: .35rem .65rem; color: #765039; background: #ead7bc; border-radius: 999px; font-size: .7rem; font-weight: 800; letter-spacing: .1em; }
.piece { color: #925b35; font-size: 4rem; line-height: 1; }.search-card h1 { margin: 0; font: 500 1.8rem Georgia, serif; }.search-card p { margin: 0; color: #806d5d; }.search-card small { color: #8b7664; }
.searching { display: flex; gap: .5rem; padding: .8rem; }.searching i { width: 10px; height: 10px; background: #668a57; border-radius: 50%; animation: pulse 1.2s infinite; }.searching i:nth-child(2) { animation-delay: .2s; }.searching i:nth-child(3) { animation-delay: .4s; }@keyframes pulse { 50% { opacity: .25; transform: scale(.75); } }
button { padding: .75rem 1rem; color: #765039; background: transparent; border: 1px solid #d9c7ae; border-radius: 9px; cursor: pointer; }.error { color: #a23f30 !important; }
</style>
