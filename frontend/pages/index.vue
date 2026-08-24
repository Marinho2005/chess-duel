<script setup lang="ts">
const auth = useAuthStore()
const route = useRoute()
const mode = ref<'login' | 'register'>('login')
const nickname = ref('')
const email = ref('')
const password = ref('')
const submitting = ref(false)
const confirmationPending = ref(false)
const sessionExpired = computed(() => route.query.session === 'expired')
const config = useRuntimeConfig()
const oauthError = computed(() => {
  if (route.query.oauth_error === 'oauth_not_configured') {
    return 'O login social ainda não foi configurado no servidor.'
  }

  return route.query.oauth_error
    ? 'Não foi possível entrar com a conta social. Tente novamente.'
    : ''
})

onMounted(async () => {
  auth.restoreSession()

  if (auth.token && (await auth.fetchCurrentUser())) {
    await navigateTo('/lobby')
  }
})

async function submit() {
  submitting.value = true

  if (mode.value === 'register') {
    confirmationPending.value = await auth.register(email.value, password.value, nickname.value)
    submitting.value = false

    if (confirmationPending.value) {
      password.value = ''
      mode.value = 'login'
    }

    return
  }

  const authenticated = await auth.logIn(email.value, password.value)
  submitting.value = false

  if (authenticated) {
    await navigateTo('/lobby')
  }
}

function socialLogin(provider: 'google') {
  window.location.assign(`${config.public.api.baseURL.replace(/\/$/, '')}/auth/${provider}`)
}
</script>

<template>
  <main class="auth-shell">
    <section class="brand">
      <div class="brand-title"><span aria-hidden="true">♟</span> ChessDuel</div>
      <p>arena de xadrez online</p>
    </section>

    <form class="auth-card" @submit.prevent="submit">
      <p v-if="sessionExpired" class="session-message">Sua sessão expirou. Entre novamente para continuar.</p>
      <p v-if="confirmationPending" class="success-message">
        Conta criada! Verifique seu e-mail e confirme a conta antes de entrar. No ambiente de desenvolvimento, o link aparece no terminal do backend.
      </p>
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
      <template v-if="mode === 'login'">
        <div class="divider"><span>ou continue com</span></div>
        <button class="social google" type="button" @click="socialLogin('google')">
          <svg class="google-icon" viewBox="0 0 24 24" aria-hidden="true">
            <path fill="#4285F4" d="M21.6 12.23c0-.71-.06-1.4-.18-2.07H12v3.92h5.38a4.6 4.6 0 0 1-2 3.02v2.55h3.24c1.9-1.75 2.98-4.33 2.98-7.42Z"/>
            <path fill="#34A853" d="M12 22c2.7 0 4.97-.9 6.62-2.35l-3.24-2.55c-.9.6-2.05.96-3.38.96-2.61 0-4.82-1.76-5.61-4.13H3.04v2.62A10 10 0 0 0 12 22Z"/>
            <path fill="#FBBC05" d="M6.39 13.93A6.02 6.02 0 0 1 6.07 12c0-.67.11-1.32.32-1.93V7.45H3.04A10 10 0 0 0 2 12c0 1.61.39 3.14 1.04 4.55l3.35-2.62Z"/>
            <path fill="#EA4335" d="M12 5.94c1.47 0 2.79.5 3.83 1.5l2.87-2.87A9.64 9.64 0 0 0 12 2a10 10 0 0 0-8.96 5.45l3.35 2.62C7.18 7.7 9.39 5.94 12 5.94Z"/>
          </svg>
          <span>Continuar com Google</span>
        </button>
      </template>
      <p v-if="auth.error || oauthError" class="error">{{ auth.error || oauthError }}</p>
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
.divider { display: flex; align-items: center; gap: 0.75rem; color: #9a8471; font-size: 0.8rem; }
.divider::before, .divider::after { content: ''; flex: 1; height: 1px; background: #dfd2c1; }
.social { display: inline-flex; align-items: center; justify-content: center; gap: 0.7rem; font-weight: 700; background: #fff; }
.social.google { color: #65452f; }
.google-icon { width: 1.25rem; height: 1.25rem; flex: 0 0 auto; }
.social:hover { transform: translateY(-1px); box-shadow: 0 5px 12px #60401f1c; }
.hint { margin: -0.4rem 0 0; color: #8b7664; font-size: 0.82rem; }
.error { margin: 0; color: #b33e2e; text-align: center; }
.session-message { margin: 0; padding: 0.8rem; color: #74472e; text-align: center; background: #efe2ce; border-radius: 10px; }
.success-message { margin: 0; padding: 0.8rem; color: #345b36; text-align: center; background: #e4f0df; border: 1px solid #c6ddbf; border-radius: 10px; }
.tagline { max-width: 520px; margin: 0; color: #806d5d; text-align: center; }
</style>
