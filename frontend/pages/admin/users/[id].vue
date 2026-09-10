<script setup lang="ts">
import type { UserDetail, ModerationAction } from '~/types/admin'
import { accountLabels, actionLabels, historyLabels, adminDate } from '~/utils/admin'
definePageMeta({ layout: 'admin', middleware: 'admin' })
const api = useApi(), auth = useAuthStore(), route = useRoute()
const data = ref<UserDetail | null>(null), loading = ref(true), error = ref(''), success = ref('')
const action = ref<ModerationAction | null>(null)
const actions = computed<ModerationAction[]>(() => {
  if (!data.value || data.value.user.id === auth.user?.id) return []
  return { active: ['suspend', 'ban'], suspended: ['reactivate', 'ban'], banned: ['reactivate'] }[data.value.user.account_status] as ModerationAction[]
})
let version = 0
async function load() {
  const current = ++version
  loading.value = true; error.value = ''
  const result = await api.request<UserDetail>(`/api/admin/users/${encodeURIComponent(String(route.params.id))}`, { authenticated: true })
  if (current !== version) return
  data.value = result.data; error.value = result.error || ''; loading.value = false
}
async function completed() { action.value = null; success.value = 'Ação registrada com sucesso.'; await load() }
watch(() => route.params.id, () => { action.value = null; success.value = ''; void load() })
onMounted(load)
onBeforeUnmount(() => { ++version })
</script>
<template>
  <NuxtLink class="admin-link" to="/admin/users">← Usuários</NuxtLink>
  <p v-if="error" class="admin-error" role="alert">{{ error }} <button @click="load">Tentar novamente</button></p>
  <p v-if="success" class="admin-success" role="status">{{ success }}</p>
  <p v-if="loading" class="admin-state" role="status">Carregando usuário…</p>
  <template v-else-if="data">
    <section class="admin-panel">
      <div class="admin-title"><h2>{{ data.user.nickname }}</h2><span class="admin-badge" :class="data.user.account_status">{{ accountLabels[data.user.account_status] }}</span></div>
      <dl class="admin-details"><div><dt>E-mail</dt><dd>{{ data.user.email }}</dd></div><div><dt>Identificador</dt><dd>{{ data.user.id }}</dd></div><div><dt>Acesso</dt><dd>{{ data.user.role === 'admin' ? 'Administrador' : 'Usuário' }}</dd></div><div><dt>Cadastro</dt><dd>{{ adminDate(data.user.inserted_at) }}</dd></div><div><dt>E-mail confirmado</dt><dd>{{ data.user.confirmed_at ? 'Sim' : 'Não' }}</dd></div><div><dt>País</dt><dd><ProfileCountryFlag v-if="data.user.country_code" :code="data.user.country_code" show-name /><span v-else>{{ data.user.country || 'Não informado' }}</span></dd></div><div v-if="data.user.suspended_until"><dt>Fim da suspensão registrada</dt><dd>{{ adminDate(data.user.suspended_until) }}</dd></div></dl>
    </section>
    <div class="admin-grid"><ProfileStatCard title="Ratings" :rows="[['Bullet', data.user.ratings.bullet], ['Blitz', data.user.ratings.blitz], ['Rapid', data.user.ratings.rapid], ['Puzzles', data.user.puzzle_rating], ['Battle', data.user.battle_rating]]" /><ProfileStatCard title="Partidas" :rows="[['Total', data.game_summary.total_games], ['Finalizadas', data.game_summary.finished_games], ['Contra bots', data.game_summary.bot_games], ['Vitórias', data.game_summary.wins]]" /></div>
    <section class="admin-panel"><h2>Moderação</h2><p v-if="!actions.length" class="admin-muted">Você não pode moderar a própria conta.</p><p v-else class="admin-muted">As ações alteram o acesso à conta e são registradas no histórico.</p><div class="admin-actions" style="justify-content: flex-start"><button v-for="item in actions" :key="item" :class="{ danger: item === 'ban' }" @click="action = item; success = ''">{{ actionLabels[item] }}</button></div></section>
    <section class="admin-panel"><h2>Histórico de moderação</h2><p class="admin-muted">Até 50 ações mais recentes. O histórico completo permanece armazenado.</p><p v-if="!data.moderation_actions.length" class="admin-state">Nenhuma ação registrada.</p><ol v-else class="moderation-history"><li v-for="entry in data.moderation_actions" :key="entry.id"><div class="admin-toolbar"><strong>{{ historyLabels[entry.action] }} · {{ entry.admin.nickname }}</strong><time class="admin-muted">{{ adminDate(entry.inserted_at) }}</time></div><p>{{ entry.reason }}</p><small v-if="entry.suspended_until" class="admin-muted">Até {{ adminDate(entry.suspended_until) }}</small></li></ol></section>
    <AdminModerationDialog v-if="action" :user="data.user" :action="action" @close="action = null" @completed="completed" />
  </template>
</template>
<style scoped>
.moderation-history { padding: 0; margin-bottom: 0; list-style: none; }
.moderation-history li { padding: 1rem 0; border-top: 1px solid var(--border-subtle); }
.moderation-history p { white-space: pre-wrap; overflow-wrap: anywhere; line-height: 1.5; }
</style>
