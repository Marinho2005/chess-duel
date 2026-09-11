<script setup lang="ts">
import type { AdminUser, Pagination } from '~/types/admin'
import { accountLabels, adminDate } from '~/utils/admin'
definePageMeta({ layout: 'admin', middleware: 'admin' })
const api = useApi()
const query = ref(''), status = ref(''), page = ref(1)
const users = ref<AdminUser[]>([]), pagination = ref<Pagination | null>(null)
const loading = ref(true), error = ref('')
let timer: ReturnType<typeof setTimeout> | undefined
let version = 0
async function load(nextPage = 1) {
  clearTimeout(timer)
  const current = ++version
  loading.value = true; error.value = ''; page.value = nextPage
  const result = await api.request<{ users: AdminUser[]; pagination: Pagination }>('/api/admin/users', {
    authenticated: true, query: { q: query.value, status: status.value, page: nextPage },
  })
  if (current !== version) return
  users.value = result.data?.users || []; pagination.value = result.data?.pagination || null
  error.value = result.error || ''; loading.value = false
}
watch([query, status], () => { ++version; clearTimeout(timer); loading.value = true; timer = setTimeout(() => void load(), 350) })
onMounted(() => load())
onBeforeUnmount(() => { ++version; clearTimeout(timer) })
</script>
<template>
  <div class="admin-title"><h2>Usuários</h2><button :disabled="loading" @click="load(page)">Atualizar</button></div>
  <form class="admin-panel admin-filters" @submit.prevent="load()">
    <label>Buscar por apelido ou e-mail<input v-model="query" type="search" maxlength="160" autocomplete="off" placeholder="Nome ou e-mail do usuário"></label>
    <label>Status
      <select v-model="status">
        <option value="">Todos</option>
        <option v-for="(label, value) in accountLabels" :key="value" :value="value">{{ label }}</option>
      </select>
    </label>
  </form>
  <p v-if="error" class="admin-error" role="alert">{{ error }}</p>
  <section class="admin-panel" :aria-busy="loading">
    <p v-if="loading" class="admin-state" role="status">Buscando usuários…</p>
    <p v-else-if="!users.length" class="admin-state">Nenhum usuário encontrado.</p>
    <div v-else class="admin-table-scroll"><table class="admin-table"><caption class="admin-muted">Contas cadastradas · rating Blitz</caption><thead><tr><th scope="col">Usuário</th><th scope="col">E-mail</th><th scope="col">Rating</th><th scope="col">Status</th><th scope="col">Cadastro</th></tr></thead>
      <tbody><tr v-for="user in users" :key="user.id"><td><NuxtLink :to="`/admin/users/${user.id}`">{{ user.nickname }}</NuxtLink><small v-if="user.role === 'admin'">Administrador</small></td><td>{{ user.email }}</td><td>{{ user.rating }}</td><td><span class="admin-badge" :class="user.account_status">{{ accountLabels[user.account_status] }}</span></td><td><time>{{ adminDate(user.inserted_at) }}</time></td></tr></tbody>
    </table></div>
    <AdminPagination v-if="pagination" :pagination="pagination" :busy="loading" @change="load" />
  </section>
</template>
