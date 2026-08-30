<script setup lang="ts">
import { Activity, ChevronFirst, ChevronLast, ChevronLeft, ChevronRight } from 'lucide-vue-next'
import type { AnalyzedMove, Evaluation, ReviewPlayer } from '~/types/game-review'

type DisplayMove = AnalyzedMove & { san: string }

const props = defineProps<{
  evaluation: Evaluation
  depth: number
  moves: DisplayMove[]
  currentPly: number
  whitePlayer: ReviewPlayer | null
  blackPlayer: ReviewPlayer | null
}>()

const emit = defineEmits<{ select: [ply: number] }>()

const activeMove = computed(() => props.currentPly ? props.moves[props.currentPly - 1] : null)
const evaluationLabel = computed(() => {
  if (props.evaluation.type === 'mate') {
    return `${props.evaluation.value < 0 ? '-' : ''}M${Math.abs(props.evaluation.value)}`
  }

  const pawns = props.evaluation.value / 100
  return `${pawns >= 0 ? '+' : ''}${pawns.toFixed(1)}`
})

const classificationLabels = {
  best: 'Melhor lance',
  good: 'Bom lance',
  inaccuracy: 'Imprecisão',
  mistake: 'Erro',
  blunder: 'Erro grave'
}
</script>

<template>
  <aside class="analysis-panel">
    <header class="engine-summary">
      <div class="engine-score">
        <span class="engine-status"><Activity :size="18" aria-hidden="true" /></span>
        <strong>{{ evaluationLabel }}</strong>
      </div>
      <div class="engine-meta">
        <b>Stockfish</b>
        <span>Profundidade {{ depth }}</span>
      </div>
    </header>

    <section class="players" aria-label="Jogadores da partida">
      <b><i class="white-piece" />{{ whitePlayer?.nickname || 'Brancas' }} <ProfileCountryFlag :code="whitePlayer?.country_code" /></b>
      <span>contra</span>
      <b><i class="black-piece" />{{ blackPlayer?.nickname || 'Pretas' }} <ProfileCountryFlag :code="blackPlayer?.country_code" /></b>
    </section>

    <section class="variation">
      <span>Linha sugerida</span>
      <code v-if="activeMove?.principal_variation.length">
        {{ activeMove.principal_variation.slice(0, 7).join(' ') }}
      </code>
      <small v-else>Selecione um lance para ver a variante calculada.</small>
    </section>

    <MoveList :moves="moves" :current-ply="currentPly" @select="emit('select', $event)" />

    <section v-if="activeMove" class="move-insight">
      <div>
        <span class="classification" :class="activeMove.classification">
          {{ classificationLabels[activeMove.classification] }}
        </span>
        <strong>{{ activeMove.san }}</strong>
      </div>
      <p>Perda de <b>{{ activeMove.centipawn_loss }}</b> centipawns</p>
      <small>Melhor lance nesta posição: <code>{{ activeMove.best_move }}</code></small>
    </section>

    <nav aria-label="Navegação pelos lances">
      <button type="button" title="Posição inicial" :disabled="currentPly === 0" @click="emit('select', 0)">
        <ChevronFirst :size="21" aria-hidden="true" />
      </button>
      <button type="button" title="Lance anterior" :disabled="currentPly === 0" @click="emit('select', currentPly - 1)">
        <ChevronLeft :size="23" aria-hidden="true" />
      </button>
      <span>{{ currentPly }} / {{ moves.length }}</span>
      <button type="button" title="Próximo lance" :disabled="currentPly === moves.length" @click="emit('select', currentPly + 1)">
        <ChevronRight :size="23" aria-hidden="true" />
      </button>
      <button type="button" title="Posição final" :disabled="currentPly === moves.length" @click="emit('select', moves.length)">
        <ChevronLast :size="21" aria-hidden="true" />
      </button>
    </nav>
  </aside>
</template>

<style scoped>
.analysis-panel { display: flex; min-height: 0; flex-direction: column; overflow: hidden; color: #3c2b20; background: #fffaf0f2; border: 1px solid #dccbb2; border-radius: 12px; box-shadow: 0 16px 38px #6f45281b; }
.engine-summary { display: flex; min-height: 72px; align-items: center; gap: .9rem; padding: .85rem 1rem; background: #f7eedf; border-top: 3px solid #6f9154; border-bottom: 1px solid #dccbb2; }
.engine-score { display: flex; align-items: center; gap: .65rem; }.engine-score strong { min-width: 66px; color: #3d332d; font: 700 1.8rem/1 ui-monospace, SFMono-Regular, monospace; }.engine-status { display: grid; width: 32px; height: 32px; place-items: center; color: white; background: #6f9154; border-radius: 7px; }.engine-meta { display: grid; gap: .15rem; }.engine-meta b { font-size: .9rem; }.engine-meta span { color: #8b7664; font-size: .75rem; }
.players { display: flex; padding: .75rem 1rem; align-items: center; justify-content: space-between; gap: .6rem; border-bottom: 1px solid #e3d5c1; font-size: .82rem; }.players b { display: flex; align-items: center; gap: .4rem; min-width: 0; }.players > span { color: #9a8573; font-size: .7rem; }.players i { width: 11px; height: 11px; flex: 0 0 auto; border: 1px solid #57463b; border-radius: 50%; }.white-piece { background: #fff; }.black-piece { background: #3d332d; }
.variation { display: grid; gap: .3rem; min-height: 68px; padding: .7rem 1rem; background: #f1e7d7; border-bottom: 1px solid #dccbb2; }.variation > span { color: #806d5d; font-size: .66rem; font-weight: 800; letter-spacing: .08em; text-transform: uppercase; }.variation code { overflow: hidden; color: #493a31; font-size: .78rem; text-overflow: ellipsis; white-space: nowrap; }.variation small { color: #9a8573; }
.move-insight { display: grid; gap: .45rem; margin-top: auto; padding: .9rem 1rem; border-top: 1px solid #dccbb2; }.move-insight > div { display: flex; align-items: center; gap: .65rem; }.move-insight > div > strong { font: 700 1.05rem ui-monospace, monospace; }.classification { padding: .3rem .55rem; color: white; background: #71865d; border-radius: 6px; font-size: .7rem; font-weight: 800; }.classification.inaccuracy { background: #c18a2e; }.classification.mistake { background: #c5643f; }.classification.blunder { background: #a94332; }.move-insight p { margin: 0; font-size: .8rem; }.move-insight small { color: #806d5d; }.move-insight code { color: #60432f; font-weight: 700; }
nav { display: grid; padding: .65rem; grid-template-columns: repeat(2, 1fr) 1.25fr repeat(2, 1fr); gap: .35rem; background: #efe3d1; border-top: 1px solid #dccbb2; }nav button { display: grid; min-height: 40px; place-items: center; color: #68462f; background: #fffaf0; border: 1px solid #d8c6ad; border-radius: 7px; cursor: pointer; }nav button:hover:not(:disabled) { color: white; background: #6f4528; border-color: #6f4528; }nav button:disabled { opacity: .35; cursor: default; }nav > span { display: grid; place-items: center; color: #806d5d; font-size: .72rem; }
</style>
