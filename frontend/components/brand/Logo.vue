<script setup lang="ts">
withDefaults(defineProps<{ showWord?: boolean }>(), { showWord: true })
</script>

<template>
  <span class="brand-logo">
    <svg class="brand-logo__mark" viewBox="0 0 48 48" aria-hidden="true">
      <circle cx="24" cy="9" r="6.5" />
      <path d="M17.2 17.5h13.6c.8 0 1.4.7 1.2 1.5l-1 3.5c-.3 1.1.1 2.2.8 3.1 2.7 3.2 4.2 6.6 4.5 10.3H11.7c.3-3.7 1.8-7.1 4.5-10.3.7-.9 1.1-2 .8-3.1L16 19c-.2-.8.4-1.5 1.2-1.5Z" />
      <path d="M10 38h28a3 3 0 0 1 3 3v3H7v-3a3 3 0 0 1 3-3Z" />
    </svg>
    <span v-if="showWord" class="brand-logo__word">ChessDuel</span>
  </span>
</template>

<style scoped>
.brand-logo {
  display: inline-flex;
  align-items: center;
  gap: .38em;
  color: inherit;
  line-height: 1;
  white-space: nowrap;
}
.brand-logo__mark {
  width: .82em;
  height: .82em;
  flex: 0 0 auto;
  overflow: visible;
  color: var(--brand-mark-color, var(--accent));
  fill: currentColor;
  filter: none;
}
.brand-logo__word {
  font-family: var(--font-brand);
  font-weight: 700;
  letter-spacing: -.035em;
}
</style>
