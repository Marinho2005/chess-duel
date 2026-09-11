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
        <NuxtLink class="back" :to="auth.user ? `/user/${encodeURIComponent(auth.user.nickname)}` : '/lobby'">← Voltar ao perfil</NuxtLink>
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
.history-shell { min-height: 100vh; padding: clamp(1.2rem, 5vw, 4rem); color: var(--text); background-color: var(--bg); background-image: radial-gradient(var(--pattern-dot) 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: var(--font-sans); }
.page-header { display: flex; width: min(920px, 100%); margin: 0 auto 2rem; align-items: flex-end; justify-content: space-between; }.back { display: block; margin-bottom: 2rem; color: var(--accent); text-decoration: none; }.back:hover { text-decoration: underline; }.eyebrow { color: var(--accent); font-size: .72rem; font-weight: 800; letter-spacing: .12em; }.page-header h1 { margin: .35rem 0; color: var(--text); font: 500 clamp(2.2rem, 6vw, 3.7rem) var(--font-serif); }.page-header p { margin: 0; color: var(--text-muted); }.piece { color: var(--accent); font-size: 4.5rem; }
.game-list, .status-card { width: min(920px, 100%); margin: 0 auto; }.game-list { display: grid; gap: .85rem; }.game-card { display: grid; grid-template-columns: 110px 1fr auto; align-items: center; gap: 1.2rem; padding: 1.15rem; background: color-mix(in srgb, var(--surface) 96%, transparent); border: 1px solid var(--border); border-radius: 16px; box-shadow: var(--shadow); }.result-mark { padding: .65rem .8rem; text-align: center; font-weight: 800; border-radius: 10px; }.result-mark.win { color: var(--success); background: var(--success-soft); }.result-mark.loss { color: var(--danger); background: var(--danger-soft); }.result-mark.draw { color: var(--text-muted); background: var(--surface-strong); }
.opponent { display: flex; min-width: 0; align-items: center; gap: .9rem; }.avatar { display: grid; width: 46px; height: 46px; flex: 0 0 auto; place-items: center; color: var(--accent-ink); background: var(--accent); border-radius: 50%; font: 700 1.1rem var(--font-serif); }.opponent div { display: grid; min-width: 0; gap: .15rem; }.opponent small, .opponent span, .details small, .details time { color: var(--text-muted); font-size: .78rem; }.opponent a { overflow: hidden; color: var(--text); font-weight: 800; text-overflow: ellipsis; text-decoration: none; white-space: nowrap; }.opponent a:hover { color: var(--accent); text-decoration: underline; }
.details { display: grid; min-width: 145px; justify-items: end; gap: .15rem; }.details strong { color: var(--text-muted); }.details strong.positive { color: var(--success); }.details strong.negative { color: var(--danger); }.details time { margin-top: .25rem; }.status-card { padding: 3rem 1.5rem; color: var(--text); text-align: center; background: color-mix(in srgb, var(--surface) 96%, transparent); border: 1px solid var(--border); border-radius: 18px; }.empty span { color: var(--accent); font-size: 3rem; }.empty h2 { font-family: var(--font-serif); }.empty p { color: var(--text-muted); }.empty a, .load-more { display: inline-block; padding: .85rem 1.2rem; color: var(--accent-ink); font-weight: 700; text-decoration: none; background: var(--accent); border: 0; border-radius: 10px; }.empty a:hover, .load-more:hover { background: var(--accent-hover); }.error { color: var(--danger); }.load-more { margin: 1rem auto 0; cursor: pointer; }.load-more:disabled { opacity: .65; cursor: wait; }
.details .review-link { margin-top: .45rem; padding: .42rem .65rem; color: var(--accent-ink); font-size: .75rem; font-weight: 700; text-decoration: none; background: var(--accent); border-radius: 7px; }.details .review-link:hover { background: var(--accent-hover); }
@media (max-width: 680px) { .piece { display: none; }.game-card { grid-template-columns: 1fr auto; }.result-mark { grid-column: 1 / -1; }.details { min-width: auto; }.details time { max-width: 100px; text-align: right; } }
</style>
