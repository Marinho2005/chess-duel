<script setup lang="ts">
definePageMeta({ layout: false })

const auth = useAuthStore()
const message = ref('Finalizando sua autenticacao...')

onMounted(async () => {
  const params = new URLSearchParams(window.location.hash.slice(1))
  const token = params.get('token') || ''

  // Remove o token da barra de endereco assim que ele for lido.
  window.history.replaceState({}, document.title, window.location.pathname)

  if (await auth.completeOAuth(token)) {
    await navigateTo('/lobby', { replace: true })
    return
  }

  message.value = 'Nao foi possivel concluir o login social.'
  await navigateTo('/?oauth_error=invalid_token', { replace: true })
})
</script>

<template>
  <main class="callback-page">
    <section class="callback-card" aria-live="polite">
      <span class="pawn">♟</span>
      <h1>ChessDuel</h1>
      <p>{{ message }}</p>
    </section>
  </main>
</template>

<style scoped>
.callback-page { display: grid; min-height: 100vh; place-items: center; padding: 1rem; color: #463224; background: #f3ecdf; font-family: Georgia, serif; }
.callback-card { width: min(420px, 100%); padding: 2.5rem; text-align: center; background: #fffaf0; border: 1px solid #decdb5; border-radius: 18px; box-shadow: 0 18px 48px rgb(73 49 30 / 12%); }
.pawn { display: block; color: #935f38; font-size: 3rem; }
h1 { margin: 0.5rem 0; font-size: 2rem; }
p { margin: 0; color: #806e60; font-family: system-ui, sans-serif; }
</style>
