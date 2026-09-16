<script setup lang="ts">
import type { Api } from '@lichess-org/chessground/api'
import type { Color, Key } from '@lichess-org/chessground/types'

const props = withDefaults(defineProps<{
  fen: string
  orientation?: Color
  lastMove?: [Key, Key] | null
  animationDuration?: number
  label?: string
}>(), { animationDuration: 180, orientation: 'white', lastMove: null, label: 'Tabuleiro de xadrez somente leitura' })

const element = ref<HTMLElement | null>(null)
let ground: Api | null = null

onMounted(async () => {
  const { Chessground } = await import('@lichess-org/chessground')
  if (element.value) ground = Chessground(element.value, config())
})
watch(() => [props.fen, props.orientation, props.lastMove, props.animationDuration], () => ground?.set(config()))
onBeforeUnmount(() => ground?.destroy())

function config() {
  return {
    fen: props.fen,
    orientation: props.orientation,
    turnColor: props.fen.split(' ')[1] === 'b' ? 'black' as const : 'white' as const,
    lastMove: props.lastMove || undefined,
    coordinates: false,
    coordinatesOnSquares: false,
    animation: { enabled: props.animationDuration > 0, duration: props.animationDuration },
    movable: { color: undefined },
    premovable: { enabled: false },
    draggable: { enabled: false },
    selectable: { enabled: false },
    disableContextMenu: true,
  }
}
</script>

<template><div ref="element" class="cg-wrap readonly-board" :aria-label="label" /></template>

<style scoped>
.readonly-board { width: 100%; aspect-ratio: 1; overflow: hidden; border-radius: 8px; box-shadow: 0 14px 34px rgb(0 0 0 / 18%); cursor: default; }
</style>
