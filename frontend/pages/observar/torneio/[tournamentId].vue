<script setup lang="ts">
import { ArrowLeft, Radio, RefreshCw, Trophy } from 'lucide-vue-next'
import type { BroadcastLiveGame, BroadcastsApiResponse } from '~/types/live-games'

definePageMeta({ middleware: 'auth', layout: 'default' })
const route = useRoute()
const api = useApi()
const tournamentId = computed(() => String(route.params.tournamentId || ''))
const games = ref<BroadcastLiveGame[]>([])
const loading = ref(true)
const error = ref('')
let timer: ReturnType<typeof setInterval> | null = null
const tournamentName = computed(() => games.value[0]?.tournament || 'Torneio ao vivo')
const tournamentImage = computed(() => games.value[0]?.tournament_image || null)

async function refresh() {
  loading.value = true
  const result = await api.request<BroadcastsApiResponse>(`/api/broadcasts/tournaments/${encodeURIComponent(tournamentId.value)}/games`)
  if (result.data) games.value = result.data.games
  error.value = result.error ? 'Não foi possível carregar as partidas deste torneio.' : ''
  loading.value = false
}
onMounted(() => { void refresh(); timer = setInterval(() => void refresh(), 20_000) })
onBeforeUnmount(() => { if (timer) clearInterval(timer) })
</script>

<template>
  <main class="tournament-page"><div class="content">
    <NuxtLink class="back" to="/observar"><ArrowLeft :size="17" aria-hidden="true" /> Todos os torneios</NuxtLink>
    <header><img v-if="tournamentImage" class="hero-image" :src="tournamentImage" :alt="`Imagem do torneio ${tournamentName}`"><div><span><Radio :size="14" aria-hidden="true" /> AO VIVO</span><h1>{{ tournamentName }}</h1><p>{{ games.length }} {{ games.length === 1 ? 'partida em andamento' : 'partidas em andamento' }}</p></div><button type="button" :disabled="loading" @click="refresh"><RefreshCw :size="18" :class="{ spinning: loading }" aria-hidden="true" /> Atualizar</button></header>
    <section v-if="loading && !games.length" class="grid skeleton" aria-label="Carregando"><i v-for="i in 6" :key="i" /></section>
    <section v-else-if="error" class="state"><strong>{{ error }}</strong><button type="button" @click="refresh">Tentar novamente</button></section>
    <section v-else-if="!games.length" class="state"><Trophy :size="42" aria-hidden="true" /><strong>Não há partidas ao vivo neste torneio.</strong><p>O round pode ter terminado recentemente.</p></section>
    <section v-else class="grid" aria-label="Partidas do torneio"><LiveBroadcastLiveCard v-for="game in games" :key="game.game_id" :game="game" /></section>
  </div></main>
</template>

<style scoped>
.tournament-page { min-height: calc(100vh - 76px); color: var(--text); }.content { display: grid; width: min(1440px,100%); gap: 1.2rem; margin: auto; padding: clamp(1.25rem,3vw,3rem); }.back { display: inline-flex; width: max-content; align-items: center; gap: .4rem; color: var(--accent); font-weight: 700; text-decoration: none; }.back:hover { color: var(--accent-hover); }.content > header { display: grid; grid-template-columns: auto minmax(0,1fr) auto; align-items: center; gap: 1.2rem; padding-bottom: 1rem; border-bottom: 1px solid var(--border-subtle); }.hero-image { width: clamp(140px,20vw,260px); aspect-ratio: 2 / 1; object-fit: cover; border: 1px solid var(--border-subtle); border-radius: 12px; box-shadow: var(--shadow); }.content > header span { display: flex; align-items: center; gap: .35rem; color: var(--danger); font-size: .72rem; font-weight: 800; letter-spacing: .08em; }.content > header h1 { margin: .55rem 0 .3rem; font-size: clamp(1.6rem,4vw,2.4rem); letter-spacing: -.04em; }.content > header p { margin: 0; color: var(--text-muted); }.content button { display: flex; align-items: center; gap: .4rem; padding: .65rem .8rem; color: var(--text); background: var(--surface); border: 1px solid var(--border); border-radius: 8px; cursor: pointer; }.content button:disabled { opacity: .65; }.spinning { animation: spin .8s linear infinite; }@keyframes spin { to { transform: rotate(360deg); } }.grid { display: grid; grid-template-columns: repeat(auto-fill,minmax(280px,1fr)); gap: 1rem; }.skeleton i { min-height: 340px; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; animation: fade 1.3s ease-in-out infinite; }@keyframes fade { 50% { opacity: .4; } }.state { display: grid; min-height: 340px; place-items: center; align-content: center; gap: .65rem; color: var(--text-muted); text-align: center; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; }.state strong { color: var(--text); }.state p { margin: 0; }.state svg { color: var(--accent); }
@media (max-width: 640px) { .content > header { grid-template-columns: 1fr; align-items: flex-start; }.hero-image { width: 100%; }.content > header button { width: 100%; justify-content: center; }.grid { grid-template-columns: 1fr; } }
</style>
