<script setup lang="ts">
type PresenceStatus = 'online' | 'offline' | 'away' | 'dnd' | 'invisible'

const props = withDefaults(defineProps<{ status?: PresenceStatus }>(), { status: 'offline' })

const labels: Record<PresenceStatus, string> = {
  online: 'Online',
  offline: 'Offline',
  away: 'Ausente',
  dnd: 'Não perturbar',
  invisible: 'Invisível',
}
</script>

<template>
  <span class="presence-status" :class="status">
    <span class="presence-dot" aria-hidden="true" />
    {{ labels[status] }}
  </span>
</template>

<style scoped>
.presence-status { display: inline-flex; align-items: center; gap: .38rem; width: fit-content; color: var(--text-muted); font-size: .76rem; font-weight: 750; line-height: 1.2; }
.presence-dot { width: .55rem; height: .55rem; flex: 0 0 .55rem; background: var(--text-muted); border-radius: 50%; }
.presence-status.online { color: var(--success); }.presence-status.online .presence-dot { background: var(--success); box-shadow: 0 0 0 3px color-mix(in srgb, var(--success) 16%, transparent); }
.presence-status.away { color: var(--accent); }.presence-status.away .presence-dot { background: var(--accent); }
.presence-status.dnd { color: var(--danger); }.presence-status.dnd .presence-dot { background: var(--danger); }
.presence-status.invisible .presence-dot { background: var(--surface); border: 2px solid var(--text-muted); }
</style>
