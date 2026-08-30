<script setup lang="ts">
import type { Api } from '@lichess-org/chessground/api'
import type { Color, Key } from '@lichess-org/chessground/types'
const props = defineProps<{ fen: string; orientation: Color; turnColor: Color; lastMove: [Key, Key] | null }>()
const element = ref<HTMLElement | null>(null)
let ground: Api | null = null
onMounted(async () => { const { Chessground } = await import('@lichess-org/chessground'); if (element.value) ground = Chessground(element.value, config()) })
watch(() => [props.fen, props.orientation, props.turnColor, props.lastMove], () => ground?.set(config()))
onBeforeUnmount(() => ground?.destroy())
function config() { return { fen: props.fen, orientation: props.orientation, turnColor: props.turnColor, lastMove: props.lastMove || undefined, coordinates: true, coordinatesOnSquares: true, animation: { enabled: true, duration: 180 }, movable: { color: undefined }, premovable: { enabled: false }, draggable: { enabled: false }, selectable: { enabled: false } } }
</script>
<template><div ref="element" class="cg-wrap review-board" aria-label="Tabuleiro da análise" /></template>
<style scoped>.review-board { width: 100%; aspect-ratio: 1; overflow: hidden; border-radius: 8px; box-shadow: 0 18px 45px #3f2a1938; }</style>
