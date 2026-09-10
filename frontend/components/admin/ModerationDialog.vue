<script setup lang="ts">
import type { AdminUser, ModerationAction } from '~/types/admin'
import { actionLabels, moderationPayload } from '~/utils/admin'
const props = defineProps<{ user: AdminUser; action: ModerationAction }>()
const emit = defineEmits<{ close: []; completed: [] }>()
const api = useApi()
const dialog = ref<HTMLDialogElement | null>(null)
const reason = ref(''), duration = ref('86400'), customDate = ref(''), confirmed = ref(false)
const busy = ref(false), error = ref('')
let trigger: HTMLElement | null = null
onMounted(() => { trigger = document.activeElement as HTMLElement; dialog.value?.showModal() })
onBeforeUnmount(() => { dialog.value?.close(); trigger?.focus() })
function close() { if (!busy.value) emit('close') }
async function submit() {
  error.value = ''
  try {
    if (props.action === 'ban' && !confirmed.value) throw new Error('Confirme que deseja banir esta conta.')
    const body = moderationPayload(props.action, reason.value, duration.value, customDate.value)
    busy.value = true
    const result = await api.request(`/api/admin/users/${props.user.id}/${props.action}`, { authenticated: true, method: 'POST', body })
    if (result.error) { error.value = result.error; return }
    emit('completed')
  } catch (err) { error.value = err instanceof Error ? err.message : 'Não foi possível concluir a ação.' }
  finally { busy.value = false }
}
</script>
<template>
  <dialog ref="dialog" class="moderation-dialog" aria-labelledby="moderation-title" aria-describedby="moderation-description" @cancel.prevent="close">
    <form :aria-busy="busy" @submit.prevent="submit">
      <h2 id="moderation-title">{{ actionLabels[action] }} {{ user.nickname }}</h2>
      <p id="moderation-description" class="admin-muted">{{ action === 'reactivate' ? 'O usuário voltará a acessar a conta.' : action === 'ban' ? 'O acesso será bloqueado por tempo indeterminado.' : 'O acesso será bloqueado até o fim da suspensão.' }} O motivo ficará registrado no histórico administrativo.</p>
      <label>Motivo obrigatório<textarea v-model="reason" required maxlength="2000" rows="4" autofocus :disabled="busy" :aria-invalid="!!error" aria-describedby="moderation-error" /></label>
      <template v-if="action === 'suspend'">
        <label>Duração<select v-model="duration" :disabled="busy"><option value="3600">1 hora</option><option value="86400">1 dia</option><option value="604800">7 dias</option><option value="2592000">30 dias</option><option value="custom">Personalizada</option></select></label>
        <label v-if="duration === 'custom'">Data e hora de término (seu horário local)<input v-model="customDate" type="datetime-local" required :disabled="busy" :aria-invalid="!!error" aria-describedby="moderation-error"></label>
      </template>
      <label v-if="action === 'ban'" class="ban-confirmation"><input v-model="confirmed" type="checkbox" required :disabled="busy">Confirmo o banimento de {{ user.nickname }}.</label>
      <p id="moderation-error" class="admin-error" role="alert" v-show="error">{{ error }}</p>
      <p v-if="busy" role="status" class="admin-muted">Registrando ação…</p>
      <div class="admin-actions"><button type="button" :disabled="busy" @click="close">Cancelar</button><button type="submit" :class="action === 'ban' ? 'danger' : 'primary'" :disabled="busy">{{ busy ? 'Salvando…' : `Confirmar: ${actionLabels[action].toLowerCase()}` }}</button></div>
    </form>
  </dialog>
</template>
<style scoped>
.moderation-dialog { width: min(520px, calc(100vw - 2rem)); max-height: calc(100dvh - 2rem); overflow: auto; box-sizing: border-box; padding: 1.4rem; border: 1px solid var(--border); border-radius: 14px; color: var(--text); background: var(--surface); box-shadow: var(--shadow); }
.moderation-dialog::backdrop { background: color-mix(in srgb, var(--text) 45%, transparent); }
.moderation-dialog form { display: grid; gap: 1rem; }
.moderation-dialog p { margin: 0; }
.ban-confirmation { display: flex; align-items: center; gap: .7rem; }
.ban-confirmation input { width: 20px; min-height: 20px; height: 20px; flex: none; }
</style>
