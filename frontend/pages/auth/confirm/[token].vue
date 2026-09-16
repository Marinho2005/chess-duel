<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const config = useRuntimeConfig()
const status = ref<'confirming' | 'confirmed' | 'error'>('confirming')

onMounted(async () => {
  const token = Array.isArray(route.params.token) ? route.params.token[0] : route.params.token

  try {
    await $fetch(`/api/users/confirm/${encodeURIComponent(token || '')}`, {
      baseURL: config.public.api.baseURL,
      method: 'POST'
    })
    status.value = 'confirmed'
  } catch {
    status.value = 'error'
  }
})
</script>

<template>
  <main class="confirmation-shell">
    <section class="confirmation-card">
      <div class="brand"><BrandLogo /></div>
      <p v-if="status === 'confirming'">Confirmando seu e-mail...</p>
      <template v-else-if="status === 'confirmed'">
        <h1>E-mail confirmado!</h1>
        <p>Sua conta está pronta. Agora você já pode entrar e jogar.</p>
        <NuxtLink to="/">Ir para o login</NuxtLink>
      </template>
      <template v-else>
        <h1>Link inválido ou expirado</h1>
        <p>Não foi possível confirmar este e-mail.</p>
        <NuxtLink to="/">Voltar ao início</NuxtLink>
      </template>
    </section>
  </main>
</template>

<style scoped>
.confirmation-shell { display: grid; min-height: 100vh; place-items: center; padding: 1rem; color: #3c2b20; background: #f4eddf radial-gradient(#bba98e40 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: var(--font-sans); }
.confirmation-card { width: min(440px, 100%); padding: 2.5rem; text-align: center; background: #fffaf0e8; border: 1px solid #e8dac4; border-radius: 18px; box-shadow: 0 20px 45px rgb(0 0 0 / 14%); }
.brand { --brand-mark-color: #6f4528; margin-bottom: 1.5rem; color: #6f4528; font-size: 2.2rem; }
h1 { font: 700 1.8rem var(--font-serif); }
p { color: #6e5847; line-height: 1.6; }
a { display: inline-block; margin-top: 1rem; padding: 0.85rem 1.2rem; color: white; text-decoration: none; background: #6f4528; border-radius: 10px; }
</style>
