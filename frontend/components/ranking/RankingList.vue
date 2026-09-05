<script setup lang="ts">
import { Medal } from 'lucide-vue-next'

export type RankedPlayer = {
  id: string
  nickname: string
  avatar_url: string | null
  country_code?: string | null
  position?: number
  rating: number
  status: 'online' | 'offline' | 'away' | 'dnd'
}

defineProps<{
  players: RankedPlayer[]
  firstPosition: number
}>()
</script>

<template>
  <div class="ranking-list">
    <article v-for="(player, index) in players" :key="player.id" class="ranking-row">
      <div class="position" :class="{ podium: firstPosition + index <= 3 }">
        <Medal v-if="firstPosition + index <= 3" :size="18" aria-hidden="true" />
        <span>{{ firstPosition + index }}</span>
      </div>
      <ProfilePresenceAvatar
        :name="player.nickname"
        :avatar-url="player.avatar_url"
        :status="player.status"
        :size="44"
      />
      <NuxtLink :to="`/user/${encodeURIComponent(player.nickname)}`">{{ player.nickname }}</NuxtLink>
      <strong>{{ player.rating }} <small>rating</small></strong>
    </article>
  </div>
</template>

<style scoped>
.ranking-list { display: grid; gap: .65rem; }
.ranking-row { display: grid; grid-template-columns: 54px 44px minmax(0, 1fr) auto; align-items: center; gap: 1rem; padding: .85rem 1rem; background: #f5ead8; border: 1px solid #dfcfb8; border-radius: 13px; }
.position { display: flex; align-items: center; justify-content: center; gap: .3rem; color: #806d5d; font-variant-numeric: tabular-nums; }
.position.podium { color: #6f4528; font-weight: 700; }
a { overflow: hidden; color: #3c2b20; font-weight: 700; text-decoration: none; text-overflow: ellipsis; }
a:hover { color: #6f4528; text-decoration: underline; }
strong { color: #6f4528; font-size: 1.05rem; font-variant-numeric: tabular-nums; }
small { color: #8b7664; font-size: .72rem; font-weight: 500; }
@media (max-width: 520px) { .ranking-row { grid-template-columns: 40px 44px minmax(0, 1fr) auto; gap: .65rem; padding-inline: .7rem; }.position svg { display: none; } }
.ranking-row { background: var(--surface-strong); border-color: var(--border); }.position { color: var(--text-muted); }.position.podium, strong { color: var(--accent); }a { color: var(--text); }a:hover { color: var(--accent); }small { color: var(--text-muted); }
</style>
