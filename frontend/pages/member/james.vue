<script setup lang="ts">
definePageMeta({ layout: false })

const member = {
  username: 'james',
  name: 'James',
  rating: 1240,
}
</script>

<template>
  <main class="container">
    <h1>@{{ member.username }}</h1>
    <p class="subtitle">Perfil de membro</p>

    <section class="card">
      <p><strong>Nome:</strong> {{ member.name }}</p>
      <p><strong>Rating:</strong> {{ member.rating }}</p>
    </section>
  </main>
</template>

<style scoped>
.container {
  max-width: 720px;
  margin: 0 auto;
  padding: 2rem 1.5rem;
  font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
  color: #e8e8ee;
  background: #0f1115;
  min-height: 100vh;
}
h1 {
  margin: 0 0 0.25rem;
  font-size: 2.5rem;
  letter-spacing: -0.02em;
}
.subtitle {
  margin: 0 0 2rem;
  color: #9aa0aa;
}
.card {
  padding: 1.5rem;
  background: #171a21;
  border: 1px solid #232835;
  border-radius: 12px;
}
.card p {
  margin: 0.5rem 0;
}
</style>
