<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'
import { LoaderCircle, Search, Swords, UsersRound } from 'lucide-vue-next'

definePageMeta({ middleware: 'auth' })
useHead({ title: 'Amigos — ChessDuel' })

type Player = { id: string; nickname: string; avatar_url: string | null; status: 'online' | 'offline' | 'away' | 'dnd' | 'invisible' }
type Friendship = { id: string; status: 'pending' | 'accepted' | 'declined'; direction: 'incoming' | 'outgoing'; user: Player }
type AcceptedGame = { game_id: string; white_player: Player; black_player: Player }
const auth = useAuthStore()
const config = useRuntimeConfig()
const friendships = ref<Friendship[]>([])
const results = ref<Player[]>([])
const query = ref('')
const searched = ref(false)
const searching = ref(false)
const loading = ref(true)
const loaded = ref(false)
const busy = ref(false)
const error = ref('')
const notice = ref('')
let refreshTimer: ReturnType<typeof setInterval> | undefined
let searchTimer: ReturnType<typeof setTimeout> | undefined
let challengeSocket: Socket | null = null
let challengeChannel: Channel | null = null
let listVersion = 0
let searchVersion = 0
const sections = computed(() => [
  { title: 'Seus amigos', empty: 'Sua próxima amizade pode começar em uma partida. Busque um jogador para adicionar.', rows: friendships.value.filter(f => f.status === 'accepted') },
  { title: 'Pedidos recebidos', empty: 'Nenhum pedido recebido por enquanto.', rows: friendships.value.filter(f => f.status === 'pending' && f.direction === 'incoming') },
  { title: 'Pedidos enviados', empty: 'Nenhum pedido aguardando resposta.', rows: friendships.value.filter(f => f.status === 'pending' && f.direction === 'outgoing') },
])

function api<T>(path: string, method: 'GET' | 'POST' | 'PATCH' | 'DELETE' = 'GET', body?: Record<string, string>) {
  return $fetch<T>(path, { baseURL: config.public.api.baseURL, method, body, headers: { Authorization: `Bearer ${auth.token}` } })
}

function message(err: unknown) {
  return (err as { data?: { message?: string } })?.data?.message || 'Não foi possível concluir a operação. Tente novamente.'
}

async function refresh() {
  const version = ++listVersion
  try {
    const data = await api<{ friendships: Friendship[] }>('/api/friendships')
    if (version === listVersion) {
      friendships.value = data.friendships
      loaded.value = true
    }
  } catch (err) {
    if (version === listVersion) error.value = message(err)
  } finally {
    if (version === listVersion) loading.value = false
  }
}

async function search(term: string, version: number) {
  searching.value = true
  error.value = ''
  try {
    const data = await api<{ users: Player[] }>(`/api/users/search?q=${encodeURIComponent(term)}`)
    if (version === searchVersion) { results.value = data.users; searched.value = true }
  } catch (err) {
    if (version === searchVersion) error.value = message(err)
  } finally {
    if (version === searchVersion) searching.value = false
  }
}

watch(query, (value) => {
  clearTimeout(searchTimer)
  const version = ++searchVersion
  searching.value = false
  searched.value = false
  results.value = []
  const term = value.trim()
  if (term.length < 2) return
  searchTimer = setTimeout(() => { void search(term, version) }, 350)
})

function relationship(id: string) { return friendships.value.find(f => f.user.id === id && f.status !== 'declined') }
function requestLabel(id: string) {
  const f = relationship(id)
  return f?.status === 'accepted' ? 'Já são amigos' : f?.direction === 'outgoing' ? 'Pedido enviado' : f ? 'Aceitar pedido' : 'Adicionar'
}

async function mutate(path: string, method: 'POST' | 'PATCH' | 'DELETE', success: string, body?: Record<string, string>) {
  if (busy.value) return
  busy.value = true
  ++listVersion
  error.value = ''; notice.value = ''
  try {
    const data = await api<{ friendship?: Friendship } | undefined>(path, method, body)
    notice.value = method === 'POST' && data?.friendship?.status === 'accepted' ? 'Amizade aceita!' : success
    await refresh()
  } catch (err) {
    error.value = message(err)
    await refresh()
  } finally { busy.value = false }
}

function add(player: Player) { return mutate('/api/friendships', 'POST', 'Pedido enviado!', { user_id: player.id }) }
function act(f: Friendship, action: 'accept' | 'decline' | 'delete') {
  const messages = { accept: 'Amizade aceita!', decline: 'Pedido recusado.', delete: f.status === 'accepted' ? 'Amizade removida.' : 'Pedido cancelado.' }
  return mutate(`/api/friendships/${f.id}${action === 'delete' ? '' : `/${action}`}`, action === 'delete' ? 'DELETE' : 'PATCH', messages[action])
}

function connectChallengeChannel() {
  if (!auth.token || !auth.user || challengeSocket) return
  const websocketUrl = `${config.public.api.baseURL.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  challengeSocket = new Socket(websocketUrl, { params: { token: auth.token } })
  challengeSocket.connect()
  challengeChannel = challengeSocket.channel('games:lobby', { status: auth.presence })
  challengeChannel.join()
  challengeChannel.on('challenge_accepted', (game: AcceptedGame) => {
    if (game.white_player.id === auth.user?.id || game.black_player.id === auth.user?.id) {
      void navigateTo(`/game/${game.game_id}/live`)
    }
  })
}

function openChallenge(player: Player) {
  void navigateTo({ path: '/play', query: { opponent: player.nickname } })
}

onMounted(() => {
  void refresh()
  connectChallengeChannel()
  refreshTimer = setInterval(() => { if (!document.hidden && !busy.value) void refresh() }, 15000)
})
onBeforeUnmount(() => {
  clearInterval(refreshTimer)
  clearTimeout(searchTimer)
  challengeChannel?.leave()
  challengeSocket?.disconnect()
  ++listVersion
  ++searchVersion
})
</script>

<template>
  <main class="friends-page">
    <header class="page-heading">
      <div><p class="eyebrow">Social</p><h1>Amigos</h1><p>Encontre jogadores e mantenha suas conexões por perto.</p></div>
      <UsersRound :size="36" aria-hidden="true" />
    </header>
    <p v-if="error" class="feedback error" role="alert">{{ error }} <button type="button" :disabled="busy" @click="error = ''; refresh()">Atualizar lista</button></p>
    <p v-if="notice" class="feedback success" role="status">{{ notice }}</p>
    <section class="panel search-panel" aria-labelledby="search-title">
      <h2 id="search-title">Encontrar jogadores</h2>
      <form class="search-form" role="search" @submit.prevent>
        <label for="player-search">Apelido do jogador</label>
        <div class="search-field" :aria-busy="searching"><Search :size="18" aria-hidden="true" /><input id="player-search" v-model="query" type="search" minlength="2" maxlength="32" aria-describedby="search-hint" placeholder="Apelido do jogador" autocomplete="off"><LoaderCircle v-if="searching" class="spinner" :size="18" aria-label="Buscando jogadores" /></div>
        <p id="search-hint" class="empty">Digite pelo menos 2 caracteres para buscar.</p>
      </form>
      <p v-if="searched && !results.length" class="empty" role="status">Nenhum jogador encontrado.</p>
      <ul v-if="results.length" class="player-list" aria-label="Resultados da busca">
        <li v-for="player in results" :key="player.id">
          <NuxtLink class="player" :to="`/user/${encodeURIComponent(player.nickname)}`"><ProfilePresenceAvatar :name="player.nickname" :avatar-url="player.avatar_url" :status="player.status" /><strong>{{ player.nickname }}</strong></NuxtLink>
          <button type="button" :disabled="busy || !loaded || relationship(player.id)?.status === 'accepted' || relationship(player.id)?.direction === 'outgoing'" @click="add(player)">{{ requestLabel(player.id) }}</button>
        </li>
      </ul>
      <p v-if="results.length === 20" class="empty">Mostrando até 20 jogadores. Refine o apelido para encontrar mais.</p>
    </section>
    <p v-if="loading" class="empty" role="status">Carregando suas amizades…</p>
    <template v-else-if="loaded">
      <section v-for="section in sections" :key="section.title" class="panel" :aria-label="section.title">
        <h2>{{ section.title }} <span class="count">{{ section.rows.length }}</span></h2>
        <p v-if="!section.rows.length" class="empty">{{ section.empty }}</p>
        <ul v-else class="player-list">
          <li v-for="f in section.rows" :key="f.id">
            <NuxtLink class="player" :to="`/user/${encodeURIComponent(f.user.nickname)}`"><ProfilePresenceAvatar :name="f.user.nickname" :avatar-url="f.user.avatar_url" :status="f.user.status" /><span><strong>{{ f.user.nickname }}</strong><small v-if="f.status === 'pending'">{{ f.direction === 'incoming' ? 'Quer ser seu amigo' : 'Aguardando resposta' }}</small></span></NuxtLink>
            <div class="actions">
              <template v-if="f.status === 'pending' && f.direction === 'incoming'"><button type="button" class="primary" :disabled="busy" :aria-label="`Aceitar pedido de ${f.user.nickname}`" @click="act(f, 'accept')">Aceitar</button><button type="button" :disabled="busy" :aria-label="`Recusar pedido de ${f.user.nickname}`" @click="act(f, 'decline')">Recusar</button></template>
              <template v-else-if="f.status === 'accepted'"><button type="button" class="primary" :aria-label="`Desafiar ${f.user.nickname}`" @click="openChallenge(f.user)"><Swords :size="17" aria-hidden="true" />Desafiar</button><button type="button" :disabled="busy" :aria-label="`Remover amizade com ${f.user.nickname}`" @click="act(f, 'delete')">Remover</button></template>
              <button v-else type="button" :disabled="busy" :aria-label="`Cancelar pedido para ${f.user.nickname}`" @click="act(f, 'delete')">Cancelar pedido</button>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </main>
</template>

<style scoped>
.friends-page { width: min(960px, calc(100% - 2rem)); margin: auto; padding: 2.5rem 0 4rem; color: var(--text); }
.page-heading { display: flex; align-items: center; justify-content: space-between; gap: 1rem; margin-bottom: 2rem; }
.page-heading p { margin: 0; color: var(--text-muted); }.page-heading .eyebrow, .page-heading > svg { color: var(--accent); }.eyebrow { font-weight: 700; }
h1 { margin: .5rem 0; font-size: 2rem; }h2 { display: flex; align-items: center; gap: .7rem; margin: 0 0 1.25rem; font-size: 1.15rem; }
.panel { padding: 1.5rem; margin-bottom: 1.25rem; background: var(--surface); border: 1px solid var(--border); border-radius: 16px; }.count { padding: .15rem .5rem; color: var(--text-muted); background: var(--surface-strong); border-radius: 20px; font-size: .8rem; }
.search-form>label { display: block; margin-bottom: .5rem; color: var(--text-muted); font-size: .9rem; }.search-field{display:flex;align-items:center;gap:.65rem;padding:0 .8rem;color:var(--text-muted);background:var(--bg);border:1px solid var(--border);border-radius:8px}.search-field:focus-within{border-color:var(--accent);box-shadow:0 0 0 2px color-mix(in srgb,var(--accent) 20%,transparent)}.search-field input{min-width:0;flex:1;padding:.8rem 0;color:var(--text);background:transparent;border:0;outline:0}.search-field input::placeholder { color: var(--text-muted); }.spinner{flex:0 0 auto;color:var(--accent);animation:spin .8s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}
button { display: inline-flex; align-items: center; justify-content: center; gap: .5rem; min-height: 42px; padding: .65rem 1rem; color: var(--text); background: var(--surface-strong); border: 1px solid var(--border); border-radius: 8px; font-weight: 600; cursor: pointer; }button:hover:not(:disabled) { background: var(--surface-hover); }button.primary { color: var(--accent-ink); background: var(--accent); border-color: var(--accent); }button.primary:hover:not(:disabled) { background: var(--accent-hover); }button:disabled { opacity: .55; cursor: default; }
.player-list { padding: 0; margin: 0; list-style: none; }.search-panel .player-list { margin-top: 1rem; }.player-list li { display: flex; align-items: center; justify-content: space-between; gap: 1rem; padding: 1rem 0; border-top: 1px solid var(--border-subtle); }.player { display: flex; align-items: center; gap: .85rem; min-width: 0; color: var(--text); text-decoration: none; }.player:hover strong { text-decoration: underline; }.player strong { overflow-wrap: anywhere; }.player small { display: block; margin-top: .2rem; color: var(--text-muted); }.actions { display: flex; flex-shrink: 0; gap: .5rem; }.empty { margin: .5rem 0; color: var(--text-muted); line-height: 1.6; }.feedback { padding: 1rem; border-radius: 8px; }.error { color: var(--danger); background: var(--danger-soft); }.success { color: var(--success); background: var(--success-soft); }
@media (max-width: 540px) { .panel { padding: 1rem; }.player-list li { flex-wrap: wrap; }.actions { width: 100%; justify-content: flex-end; flex-wrap:wrap; } }
</style>
