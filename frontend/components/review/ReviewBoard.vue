<script setup lang="ts">
import type { Color, Key } from '@lichess-org/chessground/types'
defineProps<{ fen: string; orientation: Color; turnColor: Color; lastMove: [Key, Key] | null }>()
</script>
<template><GameReadonlyBoard :fen="fen" :orientation="orientation" :last-move="lastMove" label="Tabuleiro da análise" /></template>
