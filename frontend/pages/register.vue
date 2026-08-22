<script setup lang="ts">
const auth = useAuthStore()
const nickname = ref('')
const email = ref('')
const password = ref('')
const submitting = ref(false)

async function submit() {
  submitting.value = true
  const registered = await auth.register(email.value, password.value, nickname.value)
  submitting.value = false

  if (registered) {
    await navigateTo('/lobby')
  }
}
</script>

<template>
  <main class="auth-page">
    <form class="auth-card" @submit.prevent="submit">
      <h1>Criar conta</h1>
      <label>Apelido <input v-model="nickname" required minlength="3" maxlength="32" autocomplete="nickname"></label>
      <label>Email <input v-model="email" type="email" required autocomplete="email"></label>
      <label>Senha <input v-model="password" type="password" required minlength="12" autocomplete="new-password"></label>
      <p class="hint">A senha deve ter pelo menos 12 caracteres.</p>
      <button type="submit" :disabled="submitting">{{ submitting ? 'Criando...' : 'Criar conta' }}</button>
      <p v-if="auth.error" class="error">{{ auth.error }}</p>
      <NuxtLink to="/login">Ja tenho uma conta</NuxtLink>
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
.hint { margin: 0; color: #9aa0aa; font-size: 0.9rem; }
.error { color: #ff7b72; }
</style>
