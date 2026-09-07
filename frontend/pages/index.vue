<script setup lang="ts">
definePageMeta({ layout: false })

const auth = useAuthStore()
const route = useRoute()
const mode = ref<'login' | 'register'>('login')
const nickname = ref('')
const email = ref('')
const password = ref('')
const passwordConfirmation = ref('')
const birthDate = ref('')
const registrationError = ref('')
const submitting = ref(false)
const startingGuest = ref(false)
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

  if (auth.isGuest) {
    await navigateTo('/guest')
    return
  }

  if (auth.token && (await auth.fetchCurrentUser())) {
    await navigateTo('/lobby')
  }
})

async function submit() {
  if (mode.value === 'register') {
    registrationError.value = ''
    if (password.value !== passwordConfirmation.value) {
      registrationError.value = 'As senhas não coincidem. Digite a mesma senha nos dois campos.'
      return
    }
    submitting.value = true
    confirmationPending.value = await auth.register(email.value, password.value, nickname.value, birthDate.value)
    submitting.value = false

    if (confirmationPending.value) {
      password.value = ''
      passwordConfirmation.value = ''
      birthDate.value = ''
      mode.value = 'login'
    }

    return
  }

  submitting.value = true

  const authenticated = await auth.logIn(email.value, password.value)
  submitting.value = false

  if (authenticated) {
    await navigateTo('/lobby')
  }
}

async function playAsGuest() {
  startingGuest.value = true
  const started = await auth.startGuestSession()
  startingGuest.value = false

  if (started) await navigateTo('/guest')
}

function socialLogin(provider: 'google' | 'discord' | 'github') {
  window.location.assign(`${config.public.api.baseURL.replace(/\/$/, '')}/auth/${provider}`)
}
</script>

<template>
  <main class="auth-shell">
    <section class="brand">
      <div class="brand-title">
        <span class="brand-pawn" aria-hidden="true">♟</span>
        <span>ChessDuel</span>
      </div>
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
      <div class="password-row" :class="{ single: mode === 'login' }"><label>
        <span>Senha</span>
        <input v-model="password" type="password" required :minlength="mode === 'register' ? 12 : undefined" :autocomplete="mode === 'login' ? 'current-password' : 'new-password'" placeholder="Sua senha">
      </label><label v-if="mode === 'register'">
        <span>Confirmar senha</span>
        <input v-model="passwordConfirmation" type="password" required minlength="12" autocomplete="new-password" placeholder="Repita sua senha">
      </label></div>
      <label v-if="mode === 'register'">
        <span>Data de nascimento <small>(opcional e privada)</small></span>
        <input v-model="birthDate" type="date" :max="new Date().toISOString().slice(0,10)" autocomplete="bday">
      </label>

      <p v-if="mode === 'register'" class="hint">Use pelo menos 12 caracteres.</p>
      <button class="primary" type="submit" :disabled="submitting">
        {{ submitting ? 'Aguarde...' : mode === 'login' ? 'Entrar' : 'Criar minha conta' }}
      </button>
      <template v-if="mode === 'login'">
        <div class="divider"><span>ou continue com</span></div>
        <div class="social-grid">
        <button class="social google" type="button" aria-label="Continuar com Google" @click="socialLogin('google')">
          <svg class="google-icon" viewBox="0 0 24 24" aria-hidden="true">
            <path fill="#4285F4" d="M21.6 12.23c0-.71-.06-1.4-.18-2.07H12v3.92h5.38a4.6 4.6 0 0 1-2 3.02v2.55h3.24c1.9-1.75 2.98-4.33 2.98-7.42Z"/>
            <path fill="#34A853" d="M12 22c2.7 0 4.97-.9 6.62-2.35l-3.24-2.55c-.9.6-2.05.96-3.38.96-2.61 0-4.82-1.76-5.61-4.13H3.04v2.62A10 10 0 0 0 12 22Z"/>
            <path fill="#FBBC05" d="M6.39 13.93A6.02 6.02 0 0 1 6.07 12c0-.67.11-1.32.32-1.93V7.45H3.04A10 10 0 0 0 2 12c0 1.61.39 3.14 1.04 4.55l3.35-2.62Z"/>
            <path fill="#EA4335" d="M12 5.94c1.47 0 2.79.5 3.83 1.5l2.87-2.87A9.64 9.64 0 0 0 12 2a10 10 0 0 0-8.96 5.45l3.35 2.62C7.18 7.7 9.39 5.94 12 5.94Z"/>
          </svg>
          <span>Google</span>
        </button>
        <button class="social discord" type="button" aria-label="Continuar com Discord" @click="socialLogin('discord')">
          <svg class="social-icon" viewBox="0 0 24 24" aria-hidden="true">
            <path fill="currentColor" d="M19.54 5.34A16.3 16.3 0 0 0 15.44 4l-.5 1.03a15.2 15.2 0 0 0-5.86 0L8.56 4c-1.43.25-2.8.7-4.1 1.35C1.87 9.2 1.17 12.96 1.52 16.67a16.6 16.6 0 0 0 5.03 2.54l1.22-1.66a10.6 10.6 0 0 1-1.92-.92l.47-.36a11.7 11.7 0 0 0 11.36 0l.48.36c-.62.36-1.26.66-1.93.92l1.22 1.66a16.5 16.5 0 0 0 5.03-2.54c.42-4.3-.72-8.03-2.94-11.33ZM8.7 14.4c-1.1 0-2-1.02-2-2.28 0-1.25.88-2.28 2-2.28 1.12 0 2.02 1.03 2 2.28 0 1.26-.88 2.28-2 2.28Zm6.6 0c-1.1 0-2-1.02-2-2.28 0-1.25.88-2.28 2-2.28 1.12 0 2.02 1.03 2 2.28 0 1.26-.88 2.28-2 2.28Z"/>
          </svg>
          <span>Discord</span>
        </button>
        <button class="social github" type="button" aria-label="Continuar com GitHub" @click="socialLogin('github')">
          <svg class="social-icon" viewBox="0 0 24 24" aria-hidden="true">
            <path fill="currentColor" d="M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.87c-2.78.6-3.37-1.18-3.37-1.18-.45-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.61.07-.61 1 .07 1.53 1.03 1.53 1.03.9 1.53 2.34 1.09 2.91.83.09-.65.35-1.09.64-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.64 0 0 .84-.27 2.75 1.02A9.6 9.6 0 0 1 12 6.82a9.6 9.6 0 0 1 2.5.34c1.91-1.3 2.75-1.02 2.75-1.02.55 1.37.2 2.39.1 2.64.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.69-4.57 4.94.36.31.68.92.68 1.85V21c0 .27.18.58.69.48A10 10 0 0 0 12 2Z"/>
          </svg>
          <span>GitHub</span>
        </button>
        </div>
        <button class="guest-link" type="button" :disabled="startingGuest" @click="playAsGuest">
          {{ startingGuest ? 'Preparando sessão...' : 'Jogar como convidado' }}
        </button>
      </template>
      <p v-if="registrationError || auth.error || oauthError" class="error">{{ registrationError || auth.error || oauthError }}</p>
    </form>

   
  </main>
</template>

<style scoped>
.auth-shell {
  --ink: #3c2b20;
  --brown: #6f4528;
  display: grid;
  box-sizing: border-box;
  width: 100%;
  height: 100dvh;
  align-content: safe center;
  justify-content: center;
  justify-items: center;
  gap: 2rem;
  padding: 2rem 1rem;
  overflow-x: hidden;
  overflow-y: auto;
  color: var(--ink);
  background-color: #f4eddf;
  background-image: radial-gradient(#bba98e40 0.7px, transparent 0.7px);
  background-size: 5px 5px;
  font-family: Inter, system-ui, sans-serif;
}
.brand { text-align: center; }
.brand-title { font: 700 clamp(3rem, 8vw, 5rem)/1 Georgia, serif; color: var(--brown); }
.brand-title span { font-size: 0.75em; }
.brand p { margin: 0.65rem 0 0; color: #5f4a37; font: italic 1.25rem Georgia, serif; letter-spacing: 0.08em; }
.auth-card { display: grid; box-sizing: border-box; width: min(560px, calc(100vw - 2rem)); gap: 1rem; padding: 2rem; background: #fffaf0dd; border: 1px solid #e8dac4; border-radius: 18px; box-shadow: 0 20px 45px #6f45281c; }
.tabs { display: grid; grid-template-columns: 1fr 1fr; gap: 0.3rem; padding: 0.3rem; background: #efe2ce; border: 1px solid #dfd2c1; border-radius: 12px; }
.tabs button { border: 0; background: transparent; box-shadow: none; }
.tabs button.active { color: #fffaf0; background: var(--brown); box-shadow: 0 6px 14px #6f452822; }
label { display: grid; min-width: 0; gap: 0.45rem; color: #6e5847; font-size: 0.9rem; }
.password-row { display:grid; min-width:0; grid-template-columns:minmax(0,1fr) minmax(0,1fr); gap:.7rem; }.password-row.single { grid-template-columns:minmax(0,1fr); }label small { color:var(--text-muted); font-weight:500; }
input, button { box-sizing:border-box; min-width:0; max-width:100%; padding: 0.9rem 1rem; color: inherit; background: #fff; border: 1px solid #dfd2c1; border-radius: 10px; font: inherit; transition: background 160ms ease, border-color 160ms ease, color 160ms ease, box-shadow 160ms ease, transform 160ms ease; }
input { width:100%; }
button { cursor: pointer; }
.primary { color: white; font-weight: 700; background: var(--brown); border-color: var(--brown); box-shadow: 0 8px 16px #6f45282b; }
.primary:hover:not(:disabled) { background: #7f5130; border-color: #7f5130; transform: translateY(-1px); }
.primary:disabled { opacity: 0.65; cursor: wait; }
.divider { display: flex; align-items: center; gap: 0.75rem; color: #9a8471; font-size: 0.8rem; }
.divider::before, .divider::after { content: ''; flex: 1; height: 1px; background: #dfd2c1; }
.social-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: .55rem; }
.social { display: inline-flex; min-width: 0; align-items: center; justify-content: center; gap: .45rem; padding-inline: .55rem; font-size: .84rem; font-weight: 700; background: #fff; }
.social.google { color: #7f5130; }
.social.discord { color: #5865f2; }
.social.github { color: #24292f; }
.google-icon, .social-icon { width: 1.25rem; height: 1.25rem; flex: 0 0 auto; }
.social:hover { transform: translateY(-1px); box-shadow: 0 5px 12px #6f45281c; }
.guest-link { padding: 0.35rem; color: #806d5d; background: transparent; border: 0; text-decoration: underline; text-underline-offset: 3px; }
.guest-link:hover { color: var(--brown); background: #efe2ce; }
.hint { margin: -0.4rem 0 0; color: #8b7664; font-size: 0.82rem; }
.error { margin: 0; color: #b33e2e; text-align: center; }
.session-message { margin: 0; padding: 0.8rem; color: #7f5130; text-align: center; background: #efe2ce; border-radius: 10px; }
.success-message { margin: 0; padding: 0.8rem; color: #345b36; text-align: center; background: #e4f0df; border: 1px solid #c6ddbf; border-radius: 10px; }
.tagline { max-width: 520px; margin: 0; color: #806d5d; text-align: center; }
@media (max-width: 390px) { .social { gap: .3rem; padding-inline: .35rem; font-size: .76rem; }.google-icon, .social-icon { width: 1.05rem; height: 1.05rem; } }
@media (max-width: 520px) { .auth-shell{justify-items:stretch;padding:1.25rem 1rem}.auth-card{padding:1.35rem}.password-row { grid-template-columns:1fr; } }
.auth-shell { min-height: 100dvh; height: auto; color: var(--text); background: radial-gradient(circle at 50% 5%, color-mix(in srgb,var(--accent) 10%,transparent), transparent 34%), var(--bg); background-size: auto; }.brand-title { color: var(--text); font-family: Georgia, serif; font-size: clamp(3rem, 8vw, 5rem); letter-spacing: -.02em; }.brand-title span { color: var(--accent); }.brand p { color: var(--text-muted); font-family: Georgia, serif; font-size: 1.25rem; font-style: italic; text-transform: none; letter-spacing: .08em; }.auth-card { background: color-mix(in srgb,var(--surface) 96%,transparent); border-color: var(--border); border-radius: 18px; box-shadow: var(--shadow); backdrop-filter: blur(16px); }.tabs { background: var(--surface-strong); border-color: var(--border); }.tabs button { color: var(--text-muted); }.tabs button.active { color: var(--accent-ink); background: var(--accent); box-shadow: none; }label { color: var(--text-muted); }input, button { color: var(--text); background: var(--surface-strong); border-color: var(--border); }input::placeholder { color: color-mix(in srgb,var(--text-muted) 72%,transparent); }input:focus { border-color: var(--accent); outline: 0; box-shadow: 0 0 0 3px color-mix(in srgb,var(--accent) 16%,transparent); }.primary { color: var(--accent-ink); background: var(--accent); border-color: var(--accent); box-shadow: none; }.primary:hover:not(:disabled) { color: var(--accent-ink); background: var(--accent-hover); border-color: var(--accent-hover); }.divider { color: var(--text-muted); }.divider::before, .divider::after { background: var(--border); }.social { color: var(--text) !important; background: var(--surface-strong); }.social:hover { background: var(--surface-hover); box-shadow: none; }.social.discord { color: #8690ff !important; }.social.github { color: var(--text) !important; }.guest-link { color: var(--text-muted); }.guest-link:hover { color: var(--accent); background: var(--surface-hover); }.hint { color: var(--text-muted); }.error { color: var(--danger); }.session-message { color: var(--accent); background: color-mix(in srgb,var(--accent) 12%,transparent); }.success-message { color: var(--success); background: var(--success-soft); border-color: var(--success); }
.tabs { gap: 0; padding: 0; overflow: hidden; background: var(--surface-strong); border: 0; border-radius: 11px; }.tabs button { min-height: 46px; color: var(--text-muted); background: transparent; border: 0; border-radius: 10px; font-weight: 500; }.tabs button.active { color: var(--text); background: var(--surface); box-shadow: 0 1px 4px rgb(0 0 0 / 5%); }
.brand-title { display: flex; align-items: center; justify-content: center; gap: .65rem; }.brand-title > span { color: var(--text); }.brand-title > .brand-pawn { display:inline-flex; align-items:center; color:var(--accent); font-family:Georgia,"Times New Roman",serif; font-size:.82em; line-height:.8; filter:drop-shadow(0 4px 8px color-mix(in srgb,var(--accent) 20%,transparent)); }
</style>
