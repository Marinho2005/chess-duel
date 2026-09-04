<script setup lang="ts">
import { resolveAvatarUrl } from '~/utils/avatar'

type PresenceStatus = 'online' | 'offline' | 'away' | 'dnd' | 'invisible'

const props = withDefaults(defineProps<{
  name: string
  avatarUrl?: string | null
  status?: PresenceStatus
  size?: number
}>(), { avatarUrl: null, status: 'offline', size: 44 })

const config = useRuntimeConfig()
const imageUrl = computed(() => resolveAvatarUrl(props.avatarUrl, config.public.api.baseURL))
const statusLabels: Record<PresenceStatus, string> = {
  online: 'Online',
  offline: 'Offline',
  away: 'Ausente',
  dnd: 'Não perturbar',
  invisible: 'Offline',
}
</script>

<template>
  <span class="presence-avatar" :style="{ '--avatar-size': `${size}px` }">
    <img v-if="imageUrl" :src="imageUrl" :alt="`Foto de ${name}`">
    <span v-else class="fallback" aria-hidden="true">{{ name.charAt(0).toUpperCase() || '?' }}</span>
    <span class="status-dot" :class="status" role="img" :aria-label="statusLabels[status]" :title="statusLabels[status]" />
  </span>
</template>

<style scoped>
.presence-avatar { position: relative; display: inline-block; width: var(--avatar-size); min-width: var(--avatar-size); max-width: var(--avatar-size); height: var(--avatar-size); min-height: var(--avatar-size); max-height: var(--avatar-size); flex: 0 0 var(--avatar-size); vertical-align: middle; }.presence-avatar img { display: block; width: var(--avatar-size); min-width: var(--avatar-size); max-width: var(--avatar-size); height: var(--avatar-size); min-height: var(--avatar-size); max-height: var(--avatar-size); object-fit: cover; object-position: center; border-radius: 50%; }.fallback { display: grid; width: var(--avatar-size); min-width: var(--avatar-size); max-width: var(--avatar-size); height: var(--avatar-size); min-height: var(--avatar-size); max-height: var(--avatar-size); place-items: center; color: var(--accent-ink); background: var(--accent); border-radius: 50%; font-weight: 800; }.status-dot { position: absolute; right: 0; bottom: 0; width: clamp(9px, calc(var(--avatar-size) * .22), 12px); height: clamp(9px, calc(var(--avatar-size) * .22), 12px); background: var(--text-muted); border: 2px solid var(--surface); border-radius: 50%; box-sizing: border-box; }.status-dot.online { background: var(--success); }.status-dot.away { background: var(--accent); }.status-dot.dnd { background: var(--danger); }.status-dot.offline,.status-dot.invisible { background: var(--text-muted); }
</style>
