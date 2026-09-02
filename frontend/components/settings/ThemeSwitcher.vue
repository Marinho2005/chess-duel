<script setup lang="ts">
import { Check } from 'lucide-vue-next'
import type { AppTheme } from '~/composables/useTheme'
const { theme, applyTheme } = useTheme()
const options: { value: AppTheme; label: string; description: string; swatches: string[] }[] = [
  { value: 'navy', label: 'Azul-marinho', description: 'Midnight premium', swatches: ['#07111f', '#0d1b2d', '#dfa84f'] },
  { value: 'black', label: 'Preto', description: 'Grafite clássico', swatches: ['#111210', '#1b1c19', '#dba54d'] },
  { value: 'white', label: 'Branco', description: 'Creme ChessDuel', swatches: ['#f3ecdf', '#fffaf1', '#a96f29'] }
]
</script>
<template>
  <fieldset class="theme-switcher"><legend>Tema</legend><div class="theme-options">
    <button v-for="option in options" :key="option.value" type="button" :class="{ selected: theme === option.value }" :aria-pressed="theme === option.value" @click="applyTheme(option.value)">
      <span class="swatches" aria-hidden="true"><i v-for="color in option.swatches" :key="color" :style="{ background: color }" /></span>
      <span><strong>{{ option.label }}</strong><small>{{ option.description }}</small></span><Check v-if="theme === option.value" :size="18" aria-hidden="true" />
    </button>
  </div></fieldset>
</template>
<style scoped>
.theme-switcher{min-width:0;margin:0;padding:0;border:0}.theme-switcher legend{margin-bottom:.7rem;color:var(--text);font-weight:700}.theme-options{display:grid;grid-template-columns:repeat(3,1fr);gap:.7rem}.theme-options button{display:grid;grid-template-columns:auto 1fr auto;align-items:center;gap:.75rem;padding:.8rem;color:var(--text);background:var(--surface-strong);border:1px solid var(--border);text-align:left}.theme-options button.selected{border-color:var(--accent);box-shadow:inset 0 0 0 1px var(--accent)}.theme-options button>span:nth-child(2){display:grid;gap:.15rem}.theme-options small{color:var(--text-muted)}.theme-options svg{color:var(--accent)}.swatches{display:flex;overflow:hidden;border:1px solid var(--border);border-radius:7px}.swatches i{width:10px;height:34px}@media(max-width:680px){.theme-options{grid-template-columns:1fr}}
</style>
