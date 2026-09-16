<script setup lang="ts">
import { Shield } from 'lucide-vue-next'
const props = withDefaults(defineProps<{ name: string; avatarUrl?: string | null; size?: number }>(), { avatarUrl: null, size: 64 })
const config = useRuntimeConfig()
const imageUrl = computed(() => resolveAvatarUrl(props.avatarUrl, config.public.api.baseURL))
</script>
<template><span class="club-avatar" :style="{ '--size': `${size}px` }"><img v-if="imageUrl" :src="imageUrl" :alt="`Avatar do clube ${name}`"><Shield v-else :size="Math.round(size*.52)" aria-hidden="true"/></span></template>
<style scoped>.club-avatar{display:grid;width:var(--size);height:var(--size);flex:0 0 var(--size);place-items:center;overflow:hidden;color:var(--accent);background:var(--surface-strong);border:1px solid var(--border);border-radius:18px}.club-avatar img{width:100%;height:100%;object-fit:cover}</style>
