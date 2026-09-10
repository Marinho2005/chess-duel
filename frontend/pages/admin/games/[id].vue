<script setup lang="ts">
import type { AdminGame } from '~/types/admin'
import { adminDate, adminLabel } from '~/utils/admin'
definePageMeta({ layout: 'admin', middleware: 'admin' })
const api = useApi(), route = useRoute()
const game = ref<AdminGame | null>(null), loading = ref(true), error = ref('')
let version = 0
async function load() {
  const current = ++version
  loading.value = true; error.value = ''
  const result = await api.request<{ game: AdminGame }>(`/api/admin/games/${encodeURIComponent(String(route.params.id))}`, { authenticated: true })
  if (current !== version) return
  game.value = result.data?.game || null; error.value = result.error || ''; loading.value = false
}
watch(() => route.params.id, load)
onMounted(load)
onBeforeUnmount(() => { ++version })
</script>
<template>
  <NuxtLink class="admin-link" to="/admin/games">← Partidas</NuxtLink>
  <div class="admin-title"><h2>Detalhe da partida</h2><button :disabled="loading" @click="load">Atualizar</button></div>
  <p v-if="error" class="admin-error" role="alert">{{ error }}</p>
  <p v-if="loading" class="admin-state" role="status">Carregando partida…</p>
  <template v-else-if="game">
    <section class="admin-panel"><h3>{{ game.game_id }}</h3><dl class="admin-details"><div><dt>Identificador do registro</dt><dd>{{ game.id }}</dd></div><div><dt>Tipo</dt><dd>{{ game.type === 'bot' ? 'Humano × bot' : 'Humano × humano' }}</dd></div><div><dt>Status</dt><dd>{{ adminLabel(game.status) }}</dd></div><div><dt>Resultado</dt><dd>{{ adminLabel(game.result) }}</dd></div><div><dt>Motivo do término</dt><dd>{{ adminLabel(game.end_reason) }}</dd></div><div><dt>Controle de tempo</dt><dd>{{ game.time_control.label }}</dd></div><div><dt>Criada em</dt><dd>{{ adminDate(game.inserted_at) }}</dd></div><div><dt>Finalizada em</dt><dd>{{ adminDate(game.finished_at) }}</dd></div></dl></section>
    <div class="admin-grid"><section v-for="(player, color) in { white: game.white, black: game.black }" :key="color" class="admin-panel"><h3>{{ color === 'white' ? 'Brancas' : 'Pretas' }}</h3><NuxtLink v-if="player.id" class="admin-link" :to="`/admin/users/${player.id}`">{{ player.nickname }}</NuxtLink><strong v-else>{{ player.nickname }}</strong><dl class="admin-details"><div><dt>Rating antes</dt><dd>{{ player.rating_before ?? 'Não registrado' }}</dd></div><div><dt>Rating depois</dt><dd>{{ player.rating_after ?? 'Não registrado' }}</dd></div><div><dt>{{ player.bot ? 'Nível do bot' : 'Rating atual' }}</dt><dd>{{ player.rating ?? '—' }}</dd></div></dl></section></div>
    <section class="admin-panel"><h3>Análise</h3><p>{{ game.analysis ? adminLabel(game.analysis.status) : 'Nenhuma análise solicitada.' }}</p><p v-if="game.analysis" class="admin-muted">Atualizada em {{ adminDate(game.analysis.updated_at) }}.</p></section>
    <section class="admin-panel"><h3>Posição e lances registrados</h3><p class="admin-muted">Consulta do estado persistido. Durante uma partida, a gravação pode estar alguns instantes atrás do jogo ao vivo.</p><div v-if="game.final_fen" class="admin-board"><GameReadonlyBoard :fen="game.final_fen" /></div><p v-if="!game.moves?.length" class="admin-muted">Nenhum lance registrado.</p><ol v-else class="admin-moves"><li v-for="(move, index) in game.moves" :key="index">{{ move.san || `${move.from || ''}–${move.to || ''}` }}</li></ol></section>
  </template>
</template>
<style scoped>
.admin-board { max-width: 460px; margin: 1rem auto; }
.admin-moves { display: flex; flex-wrap: wrap; gap: .6rem 2rem; padding-left: 2rem; line-height: 1.7; }
</style>
