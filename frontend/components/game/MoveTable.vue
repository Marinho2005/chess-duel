<script setup lang="ts">
import { groupMoveRows, type StoredMove } from '~/utils/chessMoves'

const props = defineProps<{ moves: StoredMove[]; currentPly: number }>()
const emit = defineEmits<{ select: [ply: number] }>()
const rows = computed(() => groupMoveRows(props.moves))
</script>

<template>
  <div class="move-table" aria-label="Planilha da partida">
    <div class="table-head" aria-hidden="true"><span>Nº</span><b>Brancas</b><b>Pretas</b></div>
    <ol>
      <li v-for="row in rows" :key="row.number">
        <span>{{ row.number }}.</span>
        <button type="button" :class="{ active: currentPly === row.number * 2 - 1 }" @click="emit('select', row.number * 2 - 1)">{{ row.white }}</button>
        <button v-if="row.black" type="button" :class="{ active: currentPly === row.number * 2 }" @click="emit('select', row.number * 2)">{{ row.black }}</button><span v-else />
      </li>
    </ol>
  </div>
</template>

<style scoped>
.move-table { min-height: 0; overflow: hidden; border: 1px solid #eadfce; border-radius: 10px; background: #fffaf0; }.table-head,.move-table li { display: grid; grid-template-columns: 38px 1fr 1fr; align-items: center; }.table-head { padding: .5rem .55rem; color: #876f5d; background: #eee2d0; font-size: .68rem; letter-spacing: .03em; }.table-head b { padding-left: .65rem; }.move-table ol { max-height: 330px; margin: 0; padding: 0; overflow-y: auto; list-style: none; }.move-table li { min-height: 38px; padding: 0 .55rem; }.move-table li:nth-child(even) { background: #7d553308; }.move-table li > span { color: #9a816e; font-size: .72rem; text-align: right; }.move-table button { min-width: 0; padding: .55rem .65rem; overflow: hidden; color: #3c2b20; text-align: left; background: transparent; border: 0; border-radius: 6px; font: 700 .86rem ui-monospace, monospace; text-overflow: ellipsis; white-space: nowrap; cursor: pointer; }.move-table button:hover { background: #eadcc7; }.move-table button.active { color: white; background: #6f4528; }.move-table button:focus-visible { outline: 2px solid #d0a45d; outline-offset: 1px; }
</style>
