<script setup lang="ts">
const auth = useAuthStore()
const mode = ref<'login' | 'register'>('login')
const nickname = ref('')
const email = ref('')
const password = ref('')
const submitting = ref(false)

onMounted(async () => {
  auth.restoreSession()

  if (auth.token && (await auth.fetchCurrentUser())) {
    await navigateTo('/lobby')
  }
})

async function submit() {
  submitting.value = true

  const authenticated =
    mode.value === 'login'
      ? await auth.logIn(email.value, password.value)
      : await auth.register(email.value, password.value, nickname.value)

  submitting.value = false

  if (authenticated) {
    await navigateTo('/lobby')
  }
}
</script>

<template>
  <main class="auth-shell">
    <section class="brand">
      <div class="brand-title"><span aria-hidden="true">♟</span> ChessDuel</div>
      <p>arena de xadrez online</p>
    </section>

    <form class="auth-card" @submit.prevent="submit">
      <div class="tabs" role="tablist">
        <button type="button" :class="{ active: mode === 'login' }" @click="mode = 'login'">Entrar</button>
        <button type="button" :class="{ active: mode === 'register' }" @click="mode = 'register'">Criar conta</button>
      </div>

      <label v-if="mode === 'register'">
        <span>Apelido</span>
        <input v-model="nickname" required minlength="3" maxlength="32" autocomplete="nickname" placeholder="Como voce sera conhecido">
      </label>
      <label>
        <span>E-mail</span>
        <input v-model="email" type="email" required autocomplete="email" placeholder="voce@email.com">
      </label>
      <label>
        <span>Senha</span>
        <input v-model="password" type="password" required :minlength="mode === 'register' ? 12 : undefined" :autocomplete="mode === 'login' ? 'current-password' : 'new-password'" placeholder="Sua senha">
      </label>

      <p v-if="mode === 'register'" class="hint">Use pelo menos 12 caracteres.</p>
      <button class="primary" type="submit" :disabled="submitting">
        {{ submitting ? 'Aguarde...' : mode === 'login' ? 'Entrar' : 'Criar minha conta' }}
      </button>
      <p v-if="auth.error" class="error">{{ auth.error }}</p>
    </form>

    <p class="tagline">Entre, encontre um oponente e comece seu duelo.</p>
  </main>
</template>

<style scoped>
.auth-shell {
  --ink: #3c2b20;
  --brown: #925b35;
  display: grid;
  min-height: 100vh;
  place-content: center;
  justify-items: center;
  gap: 2rem;
  padding: 2rem 1rem;
  color: var(--ink);
  background-color: #f4eddf;
  background-image: radial-gradient(#bba98e40 0.7px, transparent 0.7px);
  background-size: 5px 5px;
  font-family: Inter, system-ui, sans-serif;
}
.brand { text-align: center; }
.brand-title { font: 700 clamp(3rem, 8vw, 5rem)/1 Georgia, serif; color: var(--brown); }
.brand-title span { font-size: 0.75em; }
.brand p { margin: 0.65rem 0 0; color: #8d684d; font: italic 1.25rem Georgia, serif; letter-spacing: 0.08em; }
.auth-card { display: grid; width: min(420px, calc(100vw - 2rem)); gap: 1rem; padding: 2rem; background: #fffaf0dd; border: 1px solid #e8dac4; border-radius: 18px; box-shadow: 0 20px 45px #60401f1c; }
.tabs { display: grid; grid-template-columns: 1fr 1fr; gap: 0.3rem; padding: 0.3rem; background: #efe2ce; border-radius: 12px; }
.tabs button { border: 0; background: transparent; box-shadow: none; }
.tabs button.active { color: var(--ink); background: #fffaf1; }
label { display: grid; gap: 0.45rem; color: #6e5847; font-size: 0.9rem; }
input, button { padding: 0.9rem 1rem; color: inherit; background: #fff; border: 1px solid #dfd2c1; border-radius: 10px; font: inherit; }
button { cursor: pointer; }
.primary { color: white; font-weight: 700; background: var(--brown); border-color: var(--brown); box-shadow: 0 8px 16px #7b472a30; }
.primary:disabled { opacity: 0.65; cursor: wait; }
.hint { margin: -0.4rem 0 0; color: #8b7664; font-size: 0.82rem; }
.error { margin: 0; color: #b33e2e; text-align: center; }
.tagline { max-width: 520px; margin: 0; color: #806d5d; text-align: center; }
</style>
