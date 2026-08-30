<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'default' })
</script>

<template>
  <main class="future-shell">
    <section class="future-card">
      <span class="eyebrow">COMPETIÇÃO</span>
      <div class="piece" aria-hidden="true">♛</div>
      <h1>Ranking</h1>
      <p>A listagem de jogadores não está disponível nesta branch. A navegação foi preservada enquanto a API correspondente é reintegrada.</p>
      <NuxtLink to="/lobby">Voltar aos desafios</NuxtLink>
    </section>
  </main>
</template>

<style scoped>
.future-shell { display: grid; min-height: 100vh; place-items: center; padding: 2rem; color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e35 .7px, transparent .7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
.future-card { width: min(620px, 100%); padding: clamp(2rem, 6vw, 4rem); text-align: center; background: #fffaf0e8; border: 1px solid #eadcc7; border-radius: 22px; box-shadow: 0 20px 45px #60401f1c; }
.eyebrow { color: #925b35; font-size: .72rem; font-weight: 800; letter-spacing: .13em; }.piece { margin: 1rem 0; color: #925b35; font-size: 4rem; }.future-card h1 { margin: 0; font: 500 3rem Georgia, serif; }.future-card p { margin: 1rem auto 1.6rem; color: #806d5d; line-height: 1.6; }.future-card a { display: inline-block; padding: .8rem 1rem; color: white; font-weight: 700; text-decoration: none; background: #925b35; border-radius: 9px; }
</style>
