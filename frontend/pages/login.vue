<script setup lang="ts">
const auth = useAuthStore()
const email = ref('')
const password = ref('')
const submitting = ref(false)

async function submit() {
  submitting.value = true
  const authenticated = await auth.logIn(email.value, password.value)
  submitting.value = false

  if (authenticated) {
    await navigateTo('/lobby')
  }
}
</script>

<template>
  <main class="auth-page">
    <form class="auth-card" @submit.prevent="submit">
      <h1>Entrar no ChessDuel</h1>
      <label>Email <input v-model="email" type="email" required autocomplete="email"></label>
      <label>Senha <input v-model="password" type="password" required autocomplete="current-password"></label>
      <button type="submit" :disabled="submitting">{{ submitting ? 'Entrando...' : 'Entrar' }}</button>
      <p v-if="auth.error" class="error">{{ auth.error }}</p>
      <NuxtLink to="/register">Ainda nao tenho conta</NuxtLink>
    </form>
  </main>
</template>

<style scoped>
.auth-page { display: grid; min-height: 100vh; place-items: center; color: #e8e8ee; background: #0f1115; font-family: system-ui, sans-serif; }
.auth-card { display: grid; width: min(380px, calc(100% - 2rem)); gap: 1rem; padding: 2rem; background: #171a21; border: 1px solid #232835; border-radius: 12px; }
label { display: grid; gap: 0.4rem; }
input, button { padding: 0.7rem 0.8rem; color: inherit; background: #0f1115; border: 1px solid #3a4150; border-radius: 6px; }
button { cursor: pointer; background: #2855b6; }
a { color: #8ab4ff; }
.error { color: #ff7b72; }
</style>
