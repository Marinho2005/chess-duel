<script setup lang="ts">
import type { Dashboard } from '~/types/admin'
definePageMeta({ layout: 'admin', middleware: 'admin' })
const api = useApi()
const data = ref<Dashboard | null>(null)
const loading = ref(true)
const error = ref('')
const metrics = computed(() => data.value ? [
  ['Usuários cadastrados', data.value.total_users], ['Partidas ativas', data.value.active_games],
  ['Partidas criadas hoje', data.value.games_today], ['Contra bots hoje', data.value.bot_games_today],
  ['Análises na fila', data.value.pending_analysis_jobs], ['Jobs de análise com falha definitiva', data.value.failed_analysis_jobs],
] as const : [])
async function load() {
  loading.value = true
  const result = await api.request<Dashboard>('/api/admin/dashboard', { authenticated: true })
  data.value = result.data; error.value = result.error || ''; loading.value = false
}
onMounted(load)
</script>
<template>
  <div class="admin-title"><h2>Visão geral</h2><button :disabled="loading" @click="load">Atualizar</button></div>
  <p class="admin-muted">Os totais do dia consideram a criação da partida em UTC. Partidas ativas incluem humanos, bots e convidados no servidor atual.</p>
  <p v-if="error" class="admin-error" role="alert">{{ error }}</p>
  <p v-if="loading" class="admin-state" role="status">Carregando métricas…</p>
  <section v-else-if="data" class="admin-grid" aria-label="Métricas operacionais">
    <article v-for="[label, value] in metrics" :key="label" class="admin-panel admin-metric"><h3>{{ label }}</h3><strong>{{ value }}</strong></article>
  </section>
  <p class="admin-muted">Análises na fila incluem novas tentativas. Falhas definitivas contam jobs descartados pelo Oban.</p>
</template>
