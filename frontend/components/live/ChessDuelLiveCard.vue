<script setup lang="ts">
import type { ChessDuelLiveGame } from '~/types/live-games'
import { formatClock } from '~/utils/liveGames'
defineProps<{ game: ChessDuelLiveGame }>()
</script>

<template>
  <article class="live-card" aria-label="Preview de partida ChessDuel ao vivo">
    <header><span class="live-badge">● AO VIVO</span><span>ChessDuel</span></header>
    <div class="players">
      <p><ProfilePresenceAvatar :name="game.white.nickname" :avatar-url="game.white.avatar_url" :status="game.white.status" :size="36" /><span><strong :title="game.white.nickname">{{ game.white.nickname }} <ProfileCountryFlag :code="game.white.country_code" /></strong><small>{{ game.white.rating }}</small></span><b>{{ formatClock(game.white_time_remaining_ms) }}</b></p>
      <p><ProfilePresenceAvatar :name="game.black.nickname" :avatar-url="game.black.avatar_url" :status="game.black.status" :size="36" /><span><strong :title="game.black.nickname">{{ game.black.nickname }} <ProfileCountryFlag :code="game.black.country_code" /></strong><small>{{ game.black.rating }}</small></span><b>{{ formatClock(game.black_time_remaining_ms) }}</b></p>
    </div>
    <GameReadonlyBoard :fen="game.fen" :label="`Posição de ${game.white.nickname} contra ${game.black.nickname}`" />
  </article>
</template>

<style scoped>
.live-card { display: grid; min-width: 0; gap: .85rem; padding: 1rem; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; }
.live-card :deep(.readonly-board) { box-shadow: none; }
header { display: flex; align-items: center; justify-content: space-between; color: var(--text-muted); font-size: .74rem; font-weight: 700; }.live-badge { padding: .25rem .45rem; color: var(--danger); background: var(--danger-soft); border-radius: 999px; font-size: .65rem; font-weight: 800; letter-spacing: .06em; }
.players { display: grid; gap: .6rem; }.players p { display: grid; min-width: 0; grid-template-columns: auto minmax(0,1fr) auto; align-items: center; gap: .65rem; margin: 0; }.players p > span { display: grid; min-width: 0; gap: .12rem; }.players strong { overflow: hidden; color: var(--text); text-overflow: ellipsis; white-space: nowrap; }.players small { color: var(--text-muted); }.players b { flex: none; color: var(--text); font-variant-numeric: tabular-nums; }
</style>
