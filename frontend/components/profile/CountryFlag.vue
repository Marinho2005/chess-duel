<script setup lang="ts">
import { countryFlag, countryFlagAssetUrl, countryName, normalizeCountryCode } from '~/utils/countries'

const props = withDefaults(defineProps<{ code?: string | null; showName?: boolean }>(), { showName: false })
const normalized = computed(() => normalizeCountryCode(props.code))
const imageFailed = ref(false)

watch(normalized, () => { imageFailed.value = false })
</script>

<template>
  <span v-if="normalized" class="country" :title="countryName(normalized)">
    <img v-if="!imageFailed" class="flag" :src="countryFlagAssetUrl(normalized)" alt="" aria-hidden="true" @error="imageFailed = true">
    <span v-else class="flag fallback" aria-hidden="true">{{ countryFlag(normalized) }}</span>
    <span v-if="showName">{{ countryName(normalized) }}</span>
    <span v-else class="sr-only">{{ countryName(normalized) }}</span>
  </span>
</template>

<style scoped>
.country { display: inline-flex; align-items: center; gap: .3rem; color: inherit; vertical-align: -.08em; }.flag { display:inline-block;width:.95em;height:.95em;object-fit:contain;line-height:1;filter:saturate(.88) }.fallback { font-family:"Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji",sans-serif;font-size:.95em }.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; }
</style>
