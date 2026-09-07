<script setup lang="ts">
withDefaults(defineProps<{
  category: 'bullet' | 'blitz' | 'rapid'
  size?: number
}>(), { size: 30 })
</script>

<template>
  <span
    class="game-category-icon"
    :style="{ '--category-icon': `url(/icons/${category}.svg)`, width: `${size}px`, height: `${size}px` }"
    aria-hidden="true"
  >
  </span>
</template>

<style scoped>
.game-category-icon { display: inline-block; flex: 0 0 auto; background: currentColor; mask: var(--category-icon) center / contain no-repeat; -webkit-mask: var(--category-icon) center / contain no-repeat; }
</style>
