<script setup lang="ts">
import { Eye, ImageIcon, Radio, RefreshCw, Trophy } from 'lucide-vue-next'
import type {
  BroadcastTournament,
  BroadcastTournamentsApiResponse,
  ChessDuelLiveApiResponse,
  ChessDuelLiveGame,
} from '~/types/live-games'

definePageMeta({ middleware: 'auth', layout: 'default' })

type WatchTab = 'tournaments' | 'chessduel'
type LiveCategory = '' | ChessDuelLiveGame['category']

const api = useApi()
const activeTab = ref<WatchTab>('tournaments')
const category = ref<LiveCategory>('')
const tournaments = ref<BroadcastTournament[]>([])
const games = ref<ChessDuelLiveGame[]>([])
const loading = ref(true)
const error = ref('')
let timer: ReturnType<typeof setInterval> | null = null

const categories: Array<{ value: LiveCategory; label: string }> = [
  { value: '', label: 'Todos' },
  { value: 'bullet', label: 'Bullet 1+0' },
  { value: 'blitz', label: 'Blitz 3+0' },
  { value: 'blitz_increment', label: 'Blitz 5+0' },
  { value: 'rapid', label: 'Rapid 10+0' },
]

async function loadTournaments() {
  const result = await api.request<BroadcastTournamentsApiResponse>('/api/broadcasts/tournaments')
  if (result.data) tournaments.value = result.data.tournaments
  return result.error
}

async function loadGames() {
  const result = await api.request<ChessDuelLiveApiResponse>('/api/games/live', {
    query: category.value ? { category: category.value } : {},
  })
  if (result.data) games.value = result.data.games
  return result.error
}

async function refresh() {
  loading.value = true
  const currentError = activeTab.value === 'tournaments' ? await loadTournaments() : await loadGames()
  error.value = currentError ? 'Não foi possível atualizar as partidas ao vivo.' : ''
  loading.value = false
}

watch(activeTab, () => void refresh())
watch(category, () => activeTab.value === 'chessduel' && void refresh())
onMounted(() => {
  void refresh()
  timer = setInterval(() => void refresh(), 20_000)
})
onBeforeUnmount(() => { if (timer) clearInterval(timer) })
</script>

<template>
  <main class="watch-page">
    <div class="watch-content">
      <header class="page-heading">
        <div><span class="eyebrow"><Radio :size="14" aria-hidden="true" /> AO VIVO</span><h1>Observar partidas</h1><p>Acompanhe torneios profissionais ou duelos acontecendo agora no ChessDuel.</p></div>
        <button type="button" :disabled="loading" aria-label="Atualizar partidas" @click="refresh"><RefreshCw :size="18" :class="{ spinning: loading }" aria-hidden="true" /> Atualizar</button>
      </header>

      <div class="main-tabs" role="tablist" aria-label="Tipos de partida">
        <button type="button" role="tab" :aria-selected="activeTab === 'tournaments'" :class="{ active: activeTab === 'tournaments' }" @click="activeTab = 'tournaments'"><Trophy :size="18" aria-hidden="true" /> Torneios</button>
        <button type="button" role="tab" :aria-selected="activeTab === 'chessduel'" :class="{ active: activeTab === 'chessduel' }" @click="activeTab = 'chessduel'"><Eye :size="18" aria-hidden="true" /> ChessDuel</button>
      </div>

      <div v-if="activeTab === 'chessduel'" class="filters" aria-label="Filtrar por categoria">
        <button v-for="item in categories" :key="item.value" type="button" :class="{ active: category === item.value }" @click="category = item.value">{{ item.label }}</button>
      </div>

      <div v-if="loading && !(activeTab === 'tournaments' ? tournaments.length : games.length)" class="skeleton-grid" aria-label="Carregando"><span v-for="i in 6" :key="i" /></div>
      <section v-else-if="error" class="state error-state"><strong>Não foi possível carregar esta lista.</strong><button type="button" @click="refresh">Tentar novamente</button></section>
      <section v-else-if="activeTab === 'tournaments' && !tournaments.length" class="state"><Trophy :size="42" aria-hidden="true" /><strong>Nenhum torneio ativo agora.</strong><p>Os próximos broadcasts aparecerão aqui automaticamente.</p></section>
      <section v-else-if="activeTab === 'chessduel' && !games.length" class="state"><Eye :size="42" aria-hidden="true" /><strong>Nenhuma partida nesta categoria.</strong><p>Tente outro formato ou volte em alguns instantes.</p></section>

      <section v-else-if="activeTab === 'tournaments'" class="tournament-grid" aria-label="Torneios ativos">
        <NuxtLink v-for="tournament in tournaments" :key="tournament.tournament_id" :to="`/observar/torneio/${encodeURIComponent(tournament.tournament_id)}`" class="tournament-card">
          <span class="tournament-image"><img v-if="tournament.image_url" :src="tournament.image_url" :alt="`Imagem do torneio ${tournament.name}`"><ImageIcon v-else :size="32" aria-hidden="true" /></span>
          <span class="card-content"><span class="live-count"><i aria-hidden="true" /> {{ tournament.live_games }} {{ tournament.live_games === 1 ? 'partida ao vivo' : 'partidas ao vivo' }}</span><strong>{{ tournament.name }}</strong><span class="open-label">Ver partidas <b aria-hidden="true">→</b></span></span>
        </NuxtLink>
      </section>
      <section v-else class="games-grid" aria-label="Partidas ChessDuel ao vivo"><LiveChessDuelLiveCard v-for="game in games" :key="game.game_id" :game="game" /></section>
    </div>
  </main>
</template>

<style scoped>
.watch-page { min-height: calc(100vh - 76px); color: var(--text); }.watch-content { display: grid; width: min(1440px, 100%); gap: 1.25rem; margin: auto; padding: clamp(1.25rem, 3vw, 3rem); }.page-heading { display: flex; align-items: end; justify-content: space-between; gap: 1rem; }.page-heading h1 { margin: .55rem 0 .35rem; font-size: clamp(1.7rem, 4vw, 2.5rem); letter-spacing: -.04em; }.page-heading p { margin: 0; color: var(--text-muted); }.eyebrow { display: inline-flex; align-items: center; gap: .35rem; color: var(--danger); font-size: .72rem; font-weight: 800; letter-spacing: .08em; }.page-heading button,.state button { display: flex; align-items: center; gap: .45rem; padding: .65rem .8rem; color: var(--text); background: var(--surface); border: 1px solid var(--border); border-radius: 8px; cursor: pointer; }.page-heading button:disabled { opacity: .65; }.spinning { animation: spin .8s linear infinite; }@keyframes spin { to { transform: rotate(360deg); } }
.main-tabs { display: flex; gap: .45rem; padding-bottom: .8rem; border-bottom: 1px solid var(--border-subtle); }.main-tabs button,.filters button { display: flex; align-items: center; gap: .4rem; padding: .65rem .9rem; color: var(--text-muted); background: transparent; border: 1px solid transparent; border-radius: 9px; cursor: pointer; }.main-tabs button.active { color: var(--text); background: var(--surface); border-color: var(--border); }.filters { display: flex; flex-wrap: wrap; gap: .4rem; }.filters button { padding: .48rem .75rem; background: var(--surface); border-color: var(--border-subtle); border-radius: 999px; font-size: .82rem; }.filters button.active { color: var(--accent-ink); background: var(--accent); border-color: var(--accent); }
.tournament-grid,.games-grid,.skeleton-grid { display: grid; grid-template-columns: repeat(auto-fill,minmax(280px,1fr)); gap: 1rem; }.tournament-card { display: grid; min-height: 250px; grid-template-rows: 140px 1fr; overflow: hidden; color: var(--text); background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; box-shadow: var(--shadow); text-decoration: none; transition: transform 160ms ease,border-color 160ms ease; }.tournament-card:hover { border-color: var(--accent); transform: translateY(-2px); }.tournament-image { display: grid; min-width: 0; place-items: center; overflow: hidden; color: var(--accent); background: var(--surface-strong); }.tournament-image img { width: 100%; height: 100%; object-fit: cover; }.card-content { display: grid; align-content: start; gap: .55rem; padding: 1rem; }.card-content > strong { display: -webkit-box; overflow: hidden; font-size: 1.02rem; line-height: 1.35; -webkit-box-orient: vertical; -webkit-line-clamp: 2; }.live-count { display: flex; align-items: center; gap: .45rem; color: var(--success); font-size: .72rem; font-weight: 800; }.live-count b { display: inline-grid; min-width: 1.4rem; min-height: 1.4rem; place-items: center; padding: 0 .35rem; color: var(--accent-ink); background: var(--success); border-radius: 999px; font-size: .68rem; }.open-label { display: flex; justify-content: space-between; color: var(--text-muted); font-size: .78rem; }.open-label b { color: var(--accent); }.state { display: grid; min-height: 340px; place-items: center; align-content: center; gap: .65rem; padding: 2rem; color: var(--text-muted); text-align: center; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; }.state strong { color: var(--text); }.state p { margin: 0; }.state svg { color: var(--accent); }.error-state strong { color: var(--danger); }.skeleton-grid span { min-height: 250px; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; animation: fade 1.3s ease-in-out infinite; }@keyframes fade { 50% { opacity: .4; } }
@media (max-width: 640px) { .page-heading { align-items: flex-start; flex-direction: column; }.page-heading button { align-self: stretch; justify-content: center; }.tournament-grid,.games-grid,.skeleton-grid { grid-template-columns: 1fr; } }
.live-count i { width: 7px; height: 7px; background: var(--success); border-radius: 50%; box-shadow: 0 0 7px var(--success); }
</style>
