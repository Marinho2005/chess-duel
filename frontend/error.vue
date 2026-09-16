<script setup lang="ts">
const props = defineProps<{
  error: {
    statusCode?: number
    statusMessage?: string
    message?: string
  }
}>()

const isNotFound = computed(() => props.error.statusCode === 404)

function goHome() {
  clearError({ redirect: '/' })
}

function goLobby() {
  clearError({ redirect: '/lobby' })
}
</script>

<template>
  <main class="error-shell">
    <section class="error-card">
      <div class="brand"><BrandLogo /></div>
      <div class="board-mark" aria-hidden="true">
        <span>{{ isNotFound ? '404' : error.statusCode || '!' }}</span>
      </div>

      <span class="eyebrow">{{ isNotFound ? 'LANCE FORA DO TABULEIRO' : 'PARTIDA INTERROMPIDA' }}</span>
      <h1>{{ isNotFound ? 'Página não encontrada' : 'Algo não saiu como esperado' }}</h1>
      <p>
        {{ isNotFound
          ? 'A casa que você procurou não existe ou essa rota já deixou o tabuleiro.'
          : 'Não conseguimos carregar esta página. Você pode voltar ao início e tentar novamente.'
        }}
      </p>

      <div class="actions">
        <button type="button" class="primary" @click="goHome">Voltar ao início</button>
        <button type="button" class="secondary" @click="goLobby">Ir para os desafios</button>
      </div>
    </section>
  </main>
</template>

<style scoped>
.error-shell { display: grid; min-height: 100vh; place-items: center; padding: 1.25rem; color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e40 .7px, transparent .7px); background-size: 5px 5px; font-family: var(--font-sans); }
.error-card { width: min(590px, 100%); padding: clamp(1.6rem, 6vw, 3.5rem); text-align: center; background: #fffaf0e8; border: 1px solid #e8dac4; border-radius: 24px; box-shadow: 0 24px 55px #60401f1f; }
.brand { --brand-mark-color: #925b35; margin-bottom: 2rem; color: #925b35; font-size: clamp(1.8rem, 5vw, 2.5rem); }
.board-mark { display: grid; width: 132px; height: 132px; margin: 0 auto 1.8rem; place-items: center; color: #fffaf0; background-color: #925b35; background-image: conic-gradient(from 90deg, #754326 25%, #a86f46 0 50%, #754326 0 75%, #a86f46 0); background-size: 66px 66px; border: 8px solid #e4d2b7; border-radius: 18px; box-shadow: 0 12px 24px #60401f28; }.board-mark span { display: grid; min-width: 78px; min-height: 52px; place-items: center; padding: .25rem .5rem; background: #3c2b20e8; border-radius: 9px; font: 700 1.7rem var(--font-serif); }
.eyebrow { color: #925b35; font-size: .72rem; font-weight: 800; letter-spacing: .14em; }.error-card h1 { margin: .55rem 0 .8rem; font: 500 clamp(2rem, 7vw, 3.2rem) var(--font-serif); }.error-card p { max-width: 450px; margin: 0 auto; color: #806d5d; line-height: 1.65; }
.actions { display: flex; justify-content: center; gap: .75rem; margin-top: 2rem; }.actions button { padding: .9rem 1.15rem; border: 1px solid #925b35; border-radius: 11px; font: 700 .92rem var(--font-sans); cursor: pointer; }.primary { color: white; background: #925b35; box-shadow: 0 8px 16px #7b472a30; }.secondary { color: #74492f; background: #f5e9d7; }
@media (max-width: 480px) { .actions { display: grid; }.board-mark { width: 112px; height: 112px; background-size: 56px 56px; } }
</style>
