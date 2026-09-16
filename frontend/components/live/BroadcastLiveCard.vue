<script setup lang="ts">
import type { Key } from '@lichess-org/chessground/types'
import type { BroadcastLiveGame } from '~/types/live-games'

const props = defineProps<{ game: BroadcastLiveGame }>()
const lastMove = computed<[Key, Key] | null>(() => props.game.last_move
  ? [props.game.last_move.from as Key, props.game.last_move.to as Key]
  : null)
function playerMeta(title: string | null, rating: number | null) {
  return [title, rating].filter(value => value !== null && value !== '').join(' · ') || 'Sem rating informado'
}
</script>

<template>
  <article class="live-card broadcast-card">
    <NuxtLink class="card-link" :to="{ path: `/watch/broadcast/${encodeURIComponent(game.game_id)}`, query: game.round_id ? { round: game.round_id } : {} }" :aria-label="`Assistir ${game.white.name} contra ${game.black.name}`">
      <header><span>{{ game.tournament }} · {{ game.round }}</span><span>{{ game.result && game.result !== '*' ? `Resultado: ${game.result}` : 'Em andamento' }}</span></header>
      <div class="players">
        <p><strong :title="game.white.name">{{ game.white.name }} <ProfileCountryFlag :code="game.white.country_code" /></strong><small>{{ playerMeta(game.white.title, game.white.rating) }}</small></p>
        <p><strong :title="game.black.name">{{ game.black.name }} <ProfileCountryFlag :code="game.black.country_code" /></strong><small>{{ playerMeta(game.black.title, game.black.rating) }}</small></p>
      </div>
      <GameReadonlyBoard :animation-duration="300" :fen="game.fen" :last-move="lastMove" :label="`Posição de ${game.white.name} contra ${game.black.name}`" />
    </NuxtLink>
  </article>
</template>

<style scoped>
.live-card { position: relative; min-width: 0; padding: 1rem; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; }
.card-link { display: grid; min-width: 0; gap: .85rem; color: var(--text); text-decoration: none; }
.card-link:hover header > span:first-child { text-decoration: underline; text-underline-offset: .2em; }
.card-link:focus-visible { outline: 2px solid var(--accent); outline-offset: 5px; border-radius: 4px; }
header { display: grid; gap: .35rem; min-width: 0; }
header > span { font-size: .875rem; font-weight: 700; line-height: 1.45; overflow-wrap: anywhere; text-wrap: pretty; }
header > span:last-child { color: var(--text-muted); font-weight: 400; }
.players { display: grid; gap: .5rem; }
.players p { display: flex; flex-wrap: wrap; min-width: 0; align-items: baseline; justify-content: space-between; gap: .25rem .5rem; margin: 0; }
.players strong { min-width: 0; font-size: .875rem; line-height: 1.45; overflow-wrap: anywhere; }
.players small { color: var(--text-muted); font-size: .8125rem; font-variant-numeric: tabular-nums; }
.card-link :deep(.readonly-board) { box-shadow: none; }
</style>
