<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'default' })

type GameHistoryItem = {
  id: string
  opponent: { id: string | null; nickname: string }
  color: 'white' | 'black'
  result: 'win' | 'loss' | 'draw'
  end_reason: string | null
  rating_change: number | null
  time_control: { id: string; label: string; initial_time_ms: number; increment_ms: number }
  finished_at: string
}

type HistoryResponse = {
  games: GameHistoryItem[]
  pagination: {
    page: number
    per_page: number
    total: number
    total_pages: number
    has_more: boolean
  }
}

const auth = useAuthStore()
const config = useRuntimeConfig()
const games = ref<GameHistoryItem[]>([])
const page = ref(1)
const total = ref(0)
const hasMore = ref(false)
const loading = ref(true)
const loadingMore = ref(false)
const error = ref('')

onMounted(() => loadGames(1))

async function loadGames(nextPage: number) {
  if (!auth.token) return

  nextPage === 1 ? loading.value = true : loadingMore.value = true
  error.value = ''

  try {
    const response = await $fetch<HistoryResponse>('/api/users/me/games', {
      baseURL: config.public.api.baseURL,
      headers: { Authorization: `Bearer ${auth.token}` },
      query: { page: nextPage, per_page: 10 }
    })

    games.value = nextPage === 1 ? response.games : [...games.value, ...response.games]
    page.value = response.pagination.page
    total.value = response.pagination.total
    hasMore.value = response.pagination.has_more
  } catch {
    error.value = 'Não foi possível carregar seu histórico agora.'
  } finally {
    loading.value = false
    loadingMore.value = false
  }
}

const resultLabels = { win: 'Vitória', loss: 'Derrota', draw: 'Empate' }
const colorLabels = { white: 'Brancas', black: 'Pretas' }
const reasonLabels: Record<string, string> = {
  checkmate: 'Xeque-mate',
  timeout: 'Tempo esgotado',
  stalemate: 'Afogamento',
  draw: 'Empate',
  abandonment: 'Abandono'
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'medium',
    timeStyle: 'short'
  }).format(new Date(value))
}

function ratingLabel(change: number | null) {
  if (change === null) return 'Sem variação'
  return change > 0 ? `+${change}` : String(change)
}
</script>

<template>
  <main class="history-shell">
    <header class="page-header">
      <div>
        <NuxtLink class="back" :to="auth.user ? `/profile/${encodeURIComponent(auth.user.nickname)}` : '/lobby'">← Voltar ao perfil</NuxtLink>
        <span class="eyebrow">FASE 2.5</span>
        <h1>Histórico de partidas</h1>
        <p v-if="total">{{ total }} {{ total === 1 ? 'partida finalizada' : 'partidas finalizadas' }}</p>
        <p v-else>Acompanhe seus duelos, resultados e evolução de rating.</p>
      </div>
      <span class="piece" aria-hidden="true">♟</span>
    </header>

    <section v-if="loading" class="status-card">Carregando suas partidas...</section>
    <section v-else-if="error" class="status-card error">{{ error }}</section>
    <section v-else-if="games.length === 0" class="status-card empty">
      <span>♙</span>
      <h2>Nenhuma partida finalizada</h2>
      <p>Complete seu primeiro duelo para ele aparecer aqui.</p>
      <NuxtLink to="/lobby">Encontrar um oponente</NuxtLink>
    </section>

    <section v-else class="game-list" aria-label="Partidas finalizadas">
      <article v-for="game in games" :key="game.id" class="game-card">
        <div class="result-mark" :class="game.result">{{ resultLabels[game.result] }}</div>
        <div class="opponent">
          <span class="avatar">{{ game.opponent.nickname.charAt(0).toUpperCase() }}</span>
          <div>
            <small>Contra</small>
            <NuxtLink :to="`/profile/${encodeURIComponent(game.opponent.nickname)}`">{{ game.opponent.nickname }}</NuxtLink>
            <span>{{ colorLabels[game.color] }} · {{ game.time_control.label }} · {{ reasonLabels[game.end_reason || ''] || game.end_reason || 'Motivo não informado' }}</span>
          </div>
        </div>
        <div class="details">
          <strong :class="{ positive: (game.rating_change || 0) > 0, negative: (game.rating_change || 0) < 0 }">{{ ratingLabel(game.rating_change) }}</strong>
          <small>Rating</small>
          <time :datetime="game.finished_at">{{ formatDate(game.finished_at) }}</time>
          <NuxtLink class="review-link" :to="`/game/${game.id}/review`">Analisar partida</NuxtLink>
        </div>
      </article>

      <button v-if="hasMore" class="load-more" type="button" :disabled="loadingMore" @click="loadGames(page + 1)">
        {{ loadingMore ? 'Carregando...' : 'Carregar mais partidas' }}
      </button>
    </section>
  </main>
</template>

<style scoped>
.history-shell { min-height: 100vh; padding: clamp(1.2rem, 5vw, 4rem); color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e35 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
.page-header { display: flex; width: min(920px, 100%); margin: 0 auto 2rem; align-items: flex-end; justify-content: space-between; }.back { display: block; margin-bottom: 2rem; color: #815638; text-decoration: none; }.back:hover { text-decoration: underline; }.eyebrow { color: #925b35; font-size: .72rem; font-weight: 800; letter-spacing: .12em; }.page-header h1 { margin: .35rem 0; font: 500 clamp(2.2rem, 6vw, 3.7rem) Georgia, serif; }.page-header p { margin: 0; color: #806d5d; }.piece { color: #925b35; font-size: 4.5rem; }
.game-list, .status-card { width: min(920px, 100%); margin: 0 auto; }.game-list { display: grid; gap: .85rem; }.game-card { display: grid; grid-template-columns: 110px 1fr auto; align-items: center; gap: 1.2rem; padding: 1.15rem; background: #fffaf0e8; border: 1px solid #eadcc7; border-radius: 16px; box-shadow: 0 8px 24px #60401f12; }.result-mark { padding: .65rem .8rem; text-align: center; font-weight: 800; border-radius: 10px; }.result-mark.win { color: #42663d; background: #dfeeda; }.result-mark.loss { color: #93402f; background: #f3ddd7; }.result-mark.draw { color: #715d49; background: #e9dfd0; }
.opponent { display: flex; min-width: 0; align-items: center; gap: .9rem; }.avatar { display: grid; width: 46px; height: 46px; flex: 0 0 auto; place-items: center; color: white; background: #925b35; border-radius: 50%; font: 700 1.1rem Georgia, serif; }.opponent div { display: grid; min-width: 0; gap: .15rem; }.opponent small, .opponent span, .details small, .details time { color: #857060; font-size: .78rem; }.opponent a { overflow: hidden; color: #3c2b20; font-weight: 800; text-overflow: ellipsis; text-decoration: none; white-space: nowrap; }.opponent a:hover { color: #925b35; text-decoration: underline; }
.details { display: grid; min-width: 145px; justify-items: end; gap: .15rem; }.details strong { color: #715d49; }.details strong.positive { color: #4e7748; }.details strong.negative { color: #ae4b37; }.details time { margin-top: .25rem; }.status-card { padding: 3rem 1.5rem; text-align: center; background: #fffaf0e8; border: 1px solid #eadcc7; border-radius: 18px; }.empty span { color: #925b35; font-size: 3rem; }.empty h2 { font-family: Georgia, serif; }.empty p { color: #806d5d; }.empty a, .load-more { display: inline-block; padding: .85rem 1.2rem; color: white; font-weight: 700; text-decoration: none; background: #925b35; border: 0; border-radius: 10px; }.error { color: #a53e2e; }.load-more { margin: 1rem auto 0; cursor: pointer; }.load-more:disabled { opacity: .65; cursor: wait; }
.details .review-link { margin-top: .45rem; padding: .42rem .65rem; color: #fffaf0; font-size: .75rem; font-weight: 700; text-decoration: none; background: #925b35; border-radius: 7px; }
@media (max-width: 680px) { .piece { display: none; }.game-card { grid-template-columns: 1fr auto; }.result-mark { grid-column: 1 / -1; }.details { min-width: auto; }.details time { max-width: 100px; text-align: right; } }
</style>
