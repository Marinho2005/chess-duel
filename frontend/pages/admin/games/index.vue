<script setup lang="ts">
import type { AdminGame, Pagination } from '~/types/admin'
import { adminDate, adminLabel } from '~/utils/admin'
definePageMeta({ layout: 'admin', middleware: 'admin' })
const api = useApi()
const filters = reactive({ q: '', status: '', type: '', result: '', from: '', to: '' })
const games = ref<AdminGame[]>([]), pagination = ref<Pagination | null>(null)
const page = ref(1), loading = ref(true), error = ref('')
let timer: ReturnType<typeof setTimeout> | undefined
let version = 0
async function load(nextPage = 1) {
  clearTimeout(timer)
  const current = ++version
  loading.value = true; error.value = ''; page.value = nextPage
  const result = await api.request<{ games: AdminGame[]; pagination: Pagination }>('/api/admin/games', { authenticated: true, query: { ...filters, page: nextPage } })
  if (current !== version) return
  games.value = result.data?.games || []; pagination.value = result.data?.pagination || null
  error.value = result.error || ''; loading.value = false
}
watch(filters, () => { ++version; clearTimeout(timer); loading.value = true; timer = setTimeout(() => void load(), 350) })
onMounted(() => load())
onBeforeUnmount(() => { ++version; clearTimeout(timer) })
</script>
<template>
  <div class="admin-title"><h2>Partidas</h2><button :disabled="loading" @click="load(page)">Atualizar</button></div>
  <form class="admin-panel admin-filters" @submit.prevent="load()">
    <label>Jogador ou identificador público<input v-model="filters.q" type="search" maxlength="160" placeholder="Buscar partida"></label>
    <label>Status<select v-model="filters.status"><option value="">Todos</option><option v-for="value in ['waiting', 'in_progress', 'finished']" :key="value" :value="value">{{ adminLabel(value) }}</option></select></label>
    <label>Tipo<select v-model="filters.type"><option value="">Todos</option><option value="human">Humano × humano</option><option value="bot">Humano × bot</option></select></label>
    <label>Resultado<select v-model="filters.result"><option value="">Todos</option><option v-for="value in ['white_wins', 'black_wins', 'draw', 'abandoned']" :key="value" :value="value">{{ adminLabel(value) }}</option></select></label>
    <label>De (UTC)<input v-model="filters.from" type="date"></label><label>Até (UTC)<input v-model="filters.to" type="date"></label>
  </form>
  <p class="admin-muted">Partidas persistidas. Ratings exibem o valor anterior à partida quando registrado; nos demais casos, o valor atual é identificado.</p>
  <p v-if="error" class="admin-error" role="alert">{{ error }}</p>
  <section class="admin-panel" :aria-busy="loading">
    <p v-if="loading" class="admin-state" role="status">Buscando partidas…</p>
    <p v-else-if="!games.length" class="admin-state">Nenhuma partida encontrada.</p>
    <div v-else class="admin-table-scroll"><table class="admin-table"><thead><tr><th scope="col">Partida</th><th scope="col">Jogadores / rating</th><th scope="col">Tipo / ritmo</th><th scope="col">Status / resultado</th><th scope="col">Término</th><th scope="col">Data</th><th scope="col">Análise</th></tr></thead>
      <tbody><tr v-for="game in games" :key="game.id">
        <td><NuxtLink :to="`/admin/games/${game.id}`">{{ game.game_id }}</NuxtLink></td>
        <td><div v-for="(player, color) in { white: game.white, black: game.black }" :key="color">{{ color === 'white' ? 'B' : 'P' }}: {{ player.nickname }} <small>{{ player.rating_before ?? player.rating ?? '—' }}{{ player.rating_before === null && player.rating !== null ? (player.bot ? ' · nível do bot' : ' · atual') : '' }}</small></div></td>
        <td>{{ game.type === 'bot' ? 'Humano × bot' : 'Humano × humano' }}<small>{{ game.time_control.label }}</small></td>
        <td>{{ adminLabel(game.status) }}<small>{{ adminLabel(game.result) }}</small></td><td>{{ adminLabel(game.end_reason) }}</td><td><time>{{ adminDate(game.inserted_at) }}</time></td><td>{{ adminLabel(game.analysis?.status) }}</td>
      </tr></tbody>
    </table></div>
    <AdminPagination v-if="pagination" :pagination="pagination" :busy="loading" @change="load" />
  </section>
</template>
