<script setup lang="ts">
import type { SystemStatus } from '~/types/admin'
import { adminDate } from '~/utils/admin'
definePageMeta({ layout: 'admin', middleware: 'admin' })
const api = useApi()
const data = ref<SystemStatus | null>(null), loading = ref(true), error = ref('')
async function load() {
  loading.value = true
  const result = await api.request<SystemStatus>('/api/admin/system', { authenticated: true })
  data.value = result.data; error.value = result.error || ''; loading.value = false
}
onMounted(load)
</script>
<template>
  <div class="admin-title"><h2>Sistema</h2><button :disabled="loading" @click="load">Atualizar</button></div>
  <p v-if="error" class="admin-error" role="alert">{{ error }}</p>
  <p v-if="loading" class="admin-state" role="status">Consultando sistema…</p>
  <template v-else-if="data">
    <section class="admin-panel"><h3>Banco de dados</h3><p>{{ data.database === 'available' ? 'Conexão disponível' : 'Indisponível' }}</p><p class="admin-muted">Verificado em {{ adminDate(data.observed_at) }}.</p></section>
    <section class="admin-panel"><h3>Fila de análise</h3><dl class="admin-details"><div><dt>Aguardando execução ou nova tentativa</dt><dd>{{ data.analysis_jobs.pending_analysis_jobs }}</dd></div><div><dt>Em execução</dt><dd>{{ data.analysis_jobs.executing_analysis_jobs }}</dd></div><div><dt>Descartados após falhas</dt><dd>{{ data.analysis_jobs.failed_analysis_jobs }}</dd></div><div><dt>Concorrência configurada</dt><dd>{{ data.analysis_queue_concurrency ?? 'Fila desativada nesta configuração' }}</dd></div></dl><p class="admin-muted">Contagens dos jobs de análise existentes no Oban. A concorrência configurada não indica a saúde do processo Stockfish.</p></section>
  </template>
</template>
