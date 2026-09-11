<script setup lang="ts">
import { ExternalLink } from 'lucide-vue-next'
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
    <a class="card-link" :href="game.lichess_url" target="_blank" rel="noopener noreferrer" :aria-label="`Ver ${game.white.name} contra ${game.black.name} no Lichess (nova aba)`">
      <header><span>{{ game.tournament }} · {{ game.round }}</span><span>{{ game.result && game.result !== '*' ? `Resultado: ${game.result}` : 'Em andamento' }}</span></header>
      <div class="players">
        <p><strong :title="game.white.name">{{ game.white.name }} <ProfileCountryFlag :code="game.white.country_code" /></strong><small>{{ playerMeta(game.white.title, game.white.rating) }}</small></p>
        <p><strong :title="game.black.name">{{ game.black.name }} <ProfileCountryFlag :code="game.black.country_code" /></strong><small>{{ playerMeta(game.black.title, game.black.rating) }}</small></p>
      </div>
      <GameReadonlyBoard :animation-duration="0" :fen="game.fen" :last-move="lastMove" :label="`Posição de ${game.white.name} contra ${game.black.name}`" />
      <span class="external-action">Ver no Lichess <ExternalLink :size="14" aria-hidden="true" /></span>
    </a>
  </article>
</template>

<style scoped>
.external-action { display: flex; align-items: center; justify-content: flex-end; gap: .35rem; color: var(--accent); font-size: .76rem; font-weight: 700; }
.live-card { position: relative; min-width: 0; padding: 1rem; background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px; box-shadow: var(--shadow); }
.card-link { display: grid; gap: .85rem; color: var(--text); text-decoration: none; }.card-link:hover header > span:last-child { color: var(--accent); }
header { display: grid; gap: .35rem; min-width: 0; } header > span { overflow: hidden; font-size: .76rem; font-weight: 700; text-overflow: ellipsis; white-space: nowrap; transition: color 160ms ease; }
.players { display: grid; gap: .45rem; font-size: .84rem; }.players p { display: flex; min-width: 0; align-items: baseline; justify-content: space-between; gap: .5rem; margin: 0; }.players strong { overflow: hidden; font-size: .84rem; text-overflow: ellipsis; white-space: nowrap; }.players small { flex: none; color: var(--text-muted); font-size: .74rem; }
</style>
