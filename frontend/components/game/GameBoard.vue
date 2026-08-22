<script setup lang="ts">
import { Chess, type Square } from 'chess.js'
import type { Api } from '@lichess-org/chessground/api'
import type { Color, Dests, Key } from '@lichess-org/chessground/types'

const props = defineProps<{
  fen: string
  orientation: Color
  turnColor: Color
  lastMove?: [Key, Key] | null
  check?: boolean
  disabled?: boolean
}>()

const emit = defineEmits<{
  move: [move: { from: Key; to: Key; promotion?: 'q'; premove: boolean }]
}>()

const boardElement = ref<HTMLElement | null>(null)
let ground: Api | null = null

onMounted(async () => {
  if (!boardElement.value) return

  const { Chessground } = await import('@lichess-org/chessground')
  ground = Chessground(boardElement.value, boardConfig())
})

watch(
  () => [props.fen, props.orientation, props.turnColor, props.lastMove, props.check],
  () => {
    if (!ground) return

    const shouldPlayPremove = ground.state.premovable.current && props.turnColor === props.orientation
    ground.set(boardConfig())

    if (shouldPlayPremove && !props.disabled) queueMicrotask(() => ground?.playPremove())
  }
)

watch(() => props.disabled, (disabled) => {
  if (!ground) return

  if (disabled) {
    ground.set({
      movable: { color: undefined },
      premovable: { enabled: false },
      draggable: { enabled: false },
      selectable: { enabled: false }
    })
  } else {
    ground.set(boardConfig())
  }
})

onBeforeUnmount(() => ground?.destroy())

function boardConfig() {
  return {
    fen: props.fen,
    orientation: props.orientation,
    turnColor: props.turnColor,
    lastMove: props.lastMove || undefined,
    check: props.check ? props.turnColor : false,
    coordinates: true,
    coordinatesOnSquares: true,
    disableContextMenu: true,
    animation: { enabled: true, duration: 180 },
    movable: {
      free: false,
      color: props.disabled ? undefined : props.orientation,
      dests: props.turnColor === props.orientation ? legalDestinations() : undefined,
      showDests: true,
      events: { after: handleMove }
    },
    premovable: {
      enabled: !props.disabled,
      showDests: true,
      castle: true
    },
    draggable: { enabled: !props.disabled, showGhost: true },
    selectable: { enabled: !props.disabled }
  }
}

function legalDestinations(): Dests {
  const destinations: Dests = new Map()

  try {
    const chess = new Chess(props.fen)

    for (const square of chess.board().flat()) {
      if (!square || square.color !== chess.turn()) continue

      const moves = chess.moves({ square: square.square as Square, verbose: true })
      if (moves.length) destinations.set(square.square as Key, moves.map(move => move.to as Key))
    }
  } catch {
    // O FEN oficial sera reaplicado pelo servidor; sem destinos o tabuleiro fica bloqueado.
  }

  return destinations
}

function handleMove(from: Key, to: Key, metadata: { premove: boolean }) {
  const movedPiece = ground?.state.pieces.get(to)
  const promotion = movedPiece?.role === 'pawn' && (to.endsWith('1') || to.endsWith('8')) ? 'q' : undefined
  emit('move', { from, to, promotion, premove: metadata.premove })
}
</script>

<template>
  <div ref="boardElement" class="cg-wrap chess-board" aria-label="Tabuleiro da partida" />
</template>

<style scoped>
.chess-board {
  width: 100%;
  aspect-ratio: 1;
  overflow: hidden;
  border-radius: 8px;
  box-shadow: 0 18px 45px #3f2a1938;
}
</style>
