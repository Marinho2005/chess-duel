<script setup lang="ts">
import type { Evaluation } from '~/types/game-review'

const props = withDefaults(
  defineProps<{
    evaluation?: Evaluation | null
    orientation?: 'white' | 'black'
  }>(),
  {
    evaluation: () => ({ type: 'cp', value: 0 }),
    orientation: 'white'
  }
)

const safeEval = computed<Evaluation>(() => props.evaluation || { type: 'cp', value: 0 })

const evaluationInPawns = computed(() => (
  safeEval.value.type === 'cp' ? (safeEval.value.value || 0) / 100 : null
))

const whitePercentage = computed(() => {
  if (safeEval.value.type === 'mate') {
    if (safeEval.value.value === 0) return 50
    return safeEval.value.value > 0 ? 98 : 2
  }

  const pawns = evaluationInPawns.value || 0
  // Sigmoid formula used by chess engines / Lichess: maps pawns smoothly to [2%, 98%]
  const percentage = 100 / (1 + Math.exp(-pawns / 2.2))
  return Math.min(98, Math.max(2, percentage))
})

const blackPercentage = computed(() => 100 - whitePercentage.value)

// Percentages adapted to board orientation:
// When orientation is 'white': Top is Black, Bottom is White
// When orientation is 'black': Top is White, Bottom is Black
const topPercentage = computed(() => (
  props.orientation === 'black' ? whitePercentage.value : blackPercentage.value
))
const bottomPercentage = computed(() => (
  props.orientation === 'black' ? blackPercentage.value : whitePercentage.value
))

const isWhiteWinning = computed(() => {
  if (safeEval.value.type === 'mate') return safeEval.value.value > 0
  return (evaluationInPawns.value || 0) >= 0
})

const label = computed(() => {
  if (safeEval.value.type === 'mate') {
    const val = safeEval.value.value
    if (val === 0) return '0.0'
    const sign = val < 0 ? '-' : '+'
    return `${sign}M${Math.abs(val)}`
  }

  const pawns = evaluationInPawns.value || 0
  if (pawns === 0) return '0.0'
  const sign = pawns > 0 ? '+' : '-'
  return `${sign}${Math.abs(pawns).toFixed(1)}`
})

// Determine whether the score badge is shown at top or bottom
const isLabelAtTop = computed(() => {
  if (props.orientation === 'white') {
    // If black is winning and white is bottom, label is placed at top (in black region)
    return !isWhiteWinning.value
  } else {
    // If white is winning and black is bottom, label is placed at top (in white region)
    return isWhiteWinning.value
  }
})

// Is the badge positioned on a dark background?
const isLabelDarkBg = computed(() => !isWhiteWinning.value)

const accessibleLabel = computed(() => {
  const advantage = safeEval.value.value === 0
    ? 'posição equilibrada'
    : isWhiteWinning.value ? 'vantagem das brancas' : 'vantagem das pretas'

  return `Avaliação ${label.value}: ${advantage}`
})
</script>

<template>
  <div
    class="eval-bar"
    :class="{ 'orientation-black': orientation === 'black' }"
    role="img"
    :aria-label="accessibleLabel"
  >
    <!-- Top fill -->
    <div
      class="eval-fill eval-top"
      :style="{ height: `${topPercentage}%` }"
    />

    <!-- Bottom fill -->
    <div
      class="eval-fill eval-bottom"
      :style="{ height: `${bottomPercentage}%` }"
    />

    <span
      class="eval-divider"
      :style="{ top: `${topPercentage}%` }"
      aria-hidden="true"
    />

    <!-- Score Label inside the bar (Lichess style) -->
    <div
      class="eval-score"
      :class="{
        'at-top': isLabelAtTop,
        'at-bottom': !isLabelAtTop,
        'dark-bg': isLabelDarkBg,
        'light-bg': !isLabelDarkBg
      }"
    >
      <span>{{ label }}</span>
    </div>
  </div>
</template>

<style scoped>
.eval-bar {
  position: relative;
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  min-height: 100%;
  isolation: isolate;
  border-radius: 7px;
  overflow: hidden;
  background: #302b27;
  border: 1px solid rgba(72, 57, 47, 0.72);
  box-shadow:
    inset 0 0 0 1px rgba(255, 255, 255, 0.1),
    0 6px 18px rgba(62, 40, 25, 0.18);
  user-select: none;
  box-sizing: border-box;
}

.eval-fill {
  width: 100%;
  position: absolute;
  left: 0;
  right: 0;
  transition: height 280ms cubic-bezier(0.22, 1, 0.36, 1);
}

/* Orientation White: Top is Black (#2b2825), Bottom is White (#f7f4ee) */
.eval-bar:not(.orientation-black) .eval-top {
  top: 0;
  background: linear-gradient(90deg, #292522, #38312c);
}
.eval-bar:not(.orientation-black) .eval-bottom {
  bottom: 0;
  background: linear-gradient(90deg, #f4eee3, #fffaf0);
}

/* Orientation Black: Top is White (#f7f4ee), Bottom is Black (#2b2825) */
.eval-bar.orientation-black .eval-top {
  top: 0;
  background: linear-gradient(90deg, #f4eee3, #fffaf0);
}
.eval-bar.orientation-black .eval-bottom {
  bottom: 0;
  background: linear-gradient(90deg, #292522, #38312c);
}

.eval-divider {
  position: absolute;
  right: 0;
  left: 0;
  z-index: 2;
  height: 2px;
  background: rgba(146, 91, 53, 0.72);
  box-shadow: 0 0 5px rgba(146, 91, 53, 0.36);
  transform: translateY(-1px);
  transition: top 280ms cubic-bezier(0.22, 1, 0.36, 1);
}

.eval-score {
  position: absolute;
  left: 0;
  right: 0;
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 3;
  pointer-events: none;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 0.67rem;
  font-weight: 800;
  letter-spacing: -0.045em;
  padding: 4px 2px;
  line-height: 1;
  font-variant-numeric: tabular-nums;
}

.eval-score.at-top {
  top: 6px;
}

.eval-score.at-bottom {
  bottom: 6px;
}

.eval-score.dark-bg {
  color: #f7f4ee;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.7);
}

.eval-score.light-bg {
  color: #2b2825;
  text-shadow: 0 1px 1px rgba(255, 255, 255, 0.8);
}

@media (prefers-reduced-motion: reduce) {
  .eval-fill,
  .eval-divider {
    transition: none;
  }
}
</style>
