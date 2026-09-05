<script setup lang="ts">
import type { AnalyzedMove } from '~/types/game-review'
type DisplayMove = AnalyzedMove & { san: string }
const props = defineProps<{ moves: DisplayMove[]; currentPly: number }>()
const emit = defineEmits<{ select: [ply: number] }>()
const rows = computed(() => Array.from({ length: Math.ceil(props.moves.length / 2) }, (_, i) => ({ number: i + 1, white: props.moves[i * 2], black: props.moves[i * 2 + 1] })))
const symbols = { best: '★', good: '✓', inaccuracy: '?!', mistake: '?', blunder: '??' }
</script>
<template>
  <div class="move-list" aria-label="Lances da partida">
    <div v-for="row in rows" :key="row.number" class="move-row">
      <span>{{ row.number }}.</span>
      <button
        v-for="move in [row.white, row.black]"
        :key="move?.ply || `empty-${row.number}`"
        type="button"
        :disabled="!move"
        :class="[move?.classification, { active: move?.ply === currentPly }]"
        @click="move && emit('select', move.ply)"
      >
        <template v-if="move"><b>{{ move.san }}</b><small>{{ symbols[move.classification] }}</small></template>
      </button>
    </div>
  </div>
</template>

<style scoped>
.move-list { min-height: 150px; max-height: 330px; flex: 1; padding: .35rem 0; overflow: auto; background: var(--surface); }
.move-row { display: grid; grid-template-columns: 36px 1fr 1fr; align-items: stretch; }.move-row > span { padding: .68rem .4rem; color: var(--text-muted); font-size: .72rem; text-align: right; }.move-row button { display: flex; min-width: 0; align-items: center; justify-content: space-between; padding: .62rem .8rem; color: var(--text); background: transparent; border: 0; border-radius: 4px; cursor: pointer; }.move-row:nth-child(odd) { background: color-mix(in srgb, var(--surface-strong) 45%, transparent); }.move-row button:hover,.move-row button.active { background: var(--surface-hover); }.move-row button.active { box-shadow: inset 3px 0 var(--accent); }.move-row button:disabled { cursor: default; }.move-row small { margin-left: .3rem; font-weight: 900; }.best small { color: var(--success); }.good small { color: var(--success); }.inaccuracy small { color: #d59a37; }.mistake small { color: #e27850; }.blunder small { color: var(--danger); }
</style>
