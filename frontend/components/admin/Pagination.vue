<script setup lang="ts">
import type { Pagination } from '~/types/admin'
defineProps<{ pagination: Pagination; busy: boolean }>()
defineEmits<{ change: [page: number] }>()
</script>
<template>
  <nav class="admin-pagination" aria-label="Paginação">
    <button :disabled="busy || pagination.page <= 1" @click="$emit('change', pagination.page - 1)">Anterior</button>
    <span>{{ pagination.page }} de {{ pagination.total_pages }} · {{ pagination.total }} registros</span>
    <button :disabled="busy || !pagination.has_more" @click="$emit('change', pagination.page + 1)">Próxima</button>
  </nav>
</template>
