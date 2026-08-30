<script setup lang="ts">
import { countryFlag, countryName, normalizeCountryCode } from '~/utils/countries'

const props = withDefaults(defineProps<{ code?: string | null; showName?: boolean }>(), { showName: false })
const normalized = computed(() => normalizeCountryCode(props.code))
</script>

<template>
  <span v-if="normalized" class="country" :title="countryName(normalized)">
    <span class="flag" aria-hidden="true">{{ countryFlag(normalized) }}</span>
    <span v-if="showName">{{ countryName(normalized) }}</span>
    <span v-else class="sr-only">{{ countryName(normalized) }}</span>
  </span>
</template>

<style scoped>
.country { display: inline-flex; align-items: center; gap: .38rem; color: inherit; }.flag { font-size: 1.05em; line-height: 1; filter: saturate(.88); }.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; }
</style>
