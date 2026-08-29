<script setup lang="ts">
definePageMeta({ middleware: 'auth' })
const auth = useAuthStore()
async function logOut() { await auth.logOut(); await navigateTo('/') }
</script>

<template>
  <main class="page-shell">
    <NavigationAppSidebar active="puzzles" @logout="logOut" />
    <div class="content"><NavigationComingSoonCard title="Puzzles" description="Desafios táticos e modos cronometrados chegarão em uma próxima fase do ChessDuel." /></div>
  </main>
</template>

<style scoped>
.page-shell { display: grid; grid-template-columns: 240px 1fr; min-height: 100vh; background-color: #f4eddf; background-image: radial-gradient(#bba98e35 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }.content { display: grid; place-items: center; padding: 2rem; }@media (max-width: 760px) { .page-shell { grid-template-columns: 1fr; }.content { padding: 1rem; } }
</style>
