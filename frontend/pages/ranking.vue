<script setup lang="ts">
import type { RankedPlayer } from '~/components/ranking/RankingList.vue'

definePageMeta({ middleware: 'auth', layout: 'default' })

type RankingResponse = {
  players: RankedPlayer[]
  pagination: { page: number; page_size: number; total: number; total_pages: number }
}

const route = useRoute()
const { request, baseURL } = useApi()
const players = ref<RankedPlayer[]>([])
const pagination = ref({ page: 1, page_size: 50, total: 0, total_pages: 1 })
const loading = ref(true)
const errorMessage = ref('')
const categories = [
  { id: 'bullet', label: 'Bullet' }, { id: 'blitz', label: 'Blitz' },
  { id: 'rapid', label: 'Rapid' }
] as const
const selectedCategory = computed(() => categories.some(item => item.id === route.query.category) ? String(route.query.category) : 'blitz')
const requestedPage = computed(() => {
  const value = Number(route.query.page)
  return Number.isInteger(value) && value > 0 ? value : 1
})
const firstPosition = computed(() => (pagination.value.page - 1) * pagination.value.page_size + 1)

watch([requestedPage, selectedCategory], ([page]) => loadRanking(page), { immediate: true })

async function loadRanking(page: number) {
  loading.value = true
  errorMessage.value = ''
  const result = await request<RankingResponse>('/api/ranking', { query: { page, category: selectedCategory.value } })
  loading.value = false

  if (!result.data) {
    errorMessage.value = 'Não foi possível carregar o ranking agora. Tente novamente em instantes.'
    return
  }

  players.value = result.data.players
  pagination.value = result.data.pagination
}

async function changePage(page: number) {
  if (page < 1 || page > pagination.value.total_pages) return
  await navigateTo({ path: '/ranking', query: { category: selectedCategory.value, ...(page === 1 ? {} : { page }) } })
}

async function selectCategory(category: string) { await navigateTo({ path: '/ranking', query: { category } }) }
</script>

<template>
  <main class="page-shell">
    <div class="content">
      <header>
        <p>CLASSIFICAÇÃO GERAL</p>
        <h1>Ranking de jogadores</h1>
        <span>Os duelistas são classificados pelo rating atual, do maior para o menor.</span>
      </header>

      <section class="panel" aria-live="polite">
        <nav class="categories" aria-label="Modalidade do ranking">
          <button v-for="category in categories" :key="category.id" :class="{ active: selectedCategory === category.id }" @click="selectCategory(category.id)">{{ category.label }}</button>
        </nav>
        <div class="summary"><strong>{{ pagination.total }}</strong> jogador(es) no ranking</div>
        <p v-if="loading" class="state">Carregando classificação...</p>
        <p v-else-if="errorMessage" class="state error">{{ errorMessage }}</p>
        <p v-else-if="!players.length" class="state">Ainda não há jogadores classificados.</p>
        <RankingList v-else :players="players" :first-position="firstPosition" :api-base-url="baseURL" />

        <nav v-if="!loading && pagination.total_pages > 1" class="pagination" aria-label="Paginação do ranking">
          <button :disabled="pagination.page === 1" @click="changePage(pagination.page - 1)">Anterior</button>
          <span>Página {{ pagination.page }} de {{ pagination.total_pages }}</span>
          <button :disabled="pagination.page === pagination.total_pages" @click="changePage(pagination.page + 1)">Próxima</button>
        </nav>
      </section>
    </div>
  </main>
</template>

<style scoped>
.page-shell { min-height: 100vh; color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e35 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
.content { display: grid; width: min(980px, 100%); align-content: start; gap: 1.4rem; padding: 2rem; }
header, .panel { padding: 1.6rem; background: #fffaf0e8; border: 1px solid #eadcc7; border-radius: 18px; box-shadow: 0 14px 30px #6f452812; }
header p { margin: 0 0 .55rem; color: #6f4528; font-size: .72rem; font-weight: 800; letter-spacing: .12em; }
h1 { margin: 0; font: 500 clamp(2rem, 5vw, 3rem)/1.1 Georgia, serif; }
header span { display: block; margin-top: .65rem; color: #806d5d; }
.summary { margin-bottom: 1rem; color: #806d5d; font-size: .88rem; }.summary strong { color: #6f4528; }
.state { margin: 0; padding: 2rem; color: #806d5d; text-align: center; border: 1px dashed #dfcfb8; border-radius: 12px; }.state.error { color: #9e3828; background: #f9ded5; border-style: solid; }
.pagination { display: flex; align-items: center; justify-content: center; gap: 1rem; margin-top: 1.2rem; color: #806d5d; font-size: .88rem; }
button { padding: .7rem 1rem; color: #3c2b20; background: #f7eedf; border: 1px solid #dfcfb8; border-radius: 9px; cursor: pointer; }button:disabled { opacity: .5; cursor: default; }
.categories { display:grid; grid-template-columns:repeat(3,1fr); gap:.4rem; margin-bottom:1.2rem; }.categories button.active { color:var(--accent-ink); background:var(--accent); border-color:var(--accent); }
@media (max-width: 760px) { .content { padding: 1rem; }.pagination { justify-content: space-between; gap: .5rem; } }
@media (max-width:600px) { .categories { grid-template-columns:repeat(2,1fr); } }
.page-shell { color: var(--text); background: var(--bg); }.content { width: min(1120px, 100%); margin: auto; }header, .panel { background: var(--surface); border-color: var(--border-subtle); border-radius: 12px; box-shadow: var(--shadow); }header p, .summary strong { color: var(--accent); }h1 { font-family: inherit; font-weight: 700; letter-spacing: -.035em; }header span, .summary, .state, .pagination { color: var(--text-muted); }.state { border-color: var(--border); }.state.error { color: var(--danger); background: var(--danger-soft); }button { color: var(--text); background: var(--surface-strong); border-color: var(--border); }
</style>
