<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'default' })
</script>

<template>
  <main class="page-shell">
    <NavigationComingSoonCard title="Bots" description="Adversários controlados pelo computador estão nos planos e serão implementados em uma etapa futura dedicada." />
  </main>
</template>

<style scoped>
.page-shell { display: grid; min-height: 100vh; place-items: center; padding: 2rem; background-color: #f4eddf; background-image: radial-gradient(#bba98e35 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
@media (max-width: 760px) { .page-shell { padding: 1rem; } }
</style>
