<script setup lang="ts">
import { useHealthStore } from '~/stores/health'

const api = useApi()
const health = useHealthStore()

onMounted(async () => {
  health.setLoading()
  const res = await api.request<{ status: string }>('/api/health')
  if (res.data?.status === 'ok') {
    health.setOk()
  } else {
    health.setError(res.error ?? 'Falha ao contacter o backend')
  }
})
</script>

<template>
  <main class="container">
    <h1>ChessDuel</h1>
    <p class="subtitle">Setup base — comunicação frontend &harr; backend</p>

    <section class="card">
      <h2>Health check do backend</h2>
      <p>
        Endpoint: <code>GET {{ useRuntimeConfig().public.api.baseURL }}/api/health</code>
      </p>

      <div v-if="health.status === 'loading'" class="state loading">
        <span class="dot" />{{ health.message }}
      </div>
      <div v-else-if="health.status === 'ok'" class="state ok">
        <span class="dot" />{{ health.message }}
      </div>
      <div v-else-if="health.status === 'error'" class="state error">
        <span class="dot" />{{ health.message }}
      </div>
      <div v-else class="state idle">
        <span class="dot" />Aguardando verificação...
      </div>
    </section>
  </main>
</template>

<style scoped>
.container {
  max-width: 720px;
  margin: 0 auto;
  padding: 2rem 1.5rem;
  font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
  color: #e8e8ee;
  background: #0f1115;
  min-height: 100vh;
}
h1 {
  margin: 0 0 0.25rem;
  font-size: 2.5rem;
  letter-spacing: -0.02em;
}
.subtitle {
  margin: 0 0 2rem;
  color: #9aa0aa;
}
.card {
  padding: 1.5rem;
  background: #171a21;
  border: 1px solid #232835;
  border-radius: 12px;
}
h2 {
  margin-top: 0;
  font-size: 1.1rem;
}
code {
  background: #0f1115;
  padding: 0.1rem 0.4rem;
  border-radius: 4px;
  font-size: 0.9rem;
}
.state {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  margin-top: 1rem;
  font-weight: 500;
}
.dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  display: inline-block;
  flex: 0 0 auto;
}
.loading .dot { background: #f0b429; box-shadow: 0 0 8px #f0b429; animation: pulse 1s infinite; }
.ok .dot { background: #3fb950; box-shadow: 0 0 8px #3fb950; }
.error .dot { background: #f85149; box-shadow: 0 0 8px #f85149; }
.idle .dot { background: #6e7681; }
@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}
</style>
