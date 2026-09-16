<script setup lang="ts">
import { Brain, Clock3, Flame, Swords } from 'lucide-vue-next'

definePageMeta({ middleware: 'auth', layout: 'default' })

type Summary = {
  puzzle_rating: number
  battle_rating: number
  rush_records: Record<'180' | '300', number>
}

const auth = useAuthStore()
const { request } = useApi()
const summary = ref<Summary | null>(null)
const loading = ref(true)
const errorMessage = ref('')

onMounted(async () => {
  const result = await request<Summary>('/api/puzzles/summary', {
    headers: { Authorization: `Bearer ${auth.token}` }
  })
  loading.value = false
  if (result.data) summary.value = result.data
  else errorMessage.value = 'Não foi possível carregar seus dados de problemas.'
})
</script>

<template>
  <main class="hub-page">
    <header>
      <span>TRÊS FORMAS DE TREINAR</span>
      <h1>Problemas</h1>
      <p>Estude no seu ritmo, corra contra o relógio ou enfrente outro jogador.</p>
    </header>

    <p v-if="loading" class="state">Carregando seus modos…</p>
    <p v-else-if="errorMessage" class="state error">{{ errorMessage }}</p>

    <section v-else class="mode-grid">
      <article class="mode-card classic">
        <span class="icon"><Brain :size="28" aria-hidden="true" /></span>
        <small>ESTUDO</small>
        <h2>Modo Clássico</h2>
        <p>Resolva um problema por vez, sem pressão de tempo.</p>
        <dl><dt>Rating de problemas</dt><dd>{{ summary?.puzzle_rating || 1200 }}</dd></dl>
        <NuxtLink to="/puzzles/session?mode=classic">Jogar Modo Clássico <span>→</span></NuxtLink>
      </article>

      <article class="mode-card rush">
        <span class="icon"><Flame :size="28" aria-hidden="true" /></span>
        <small>VELOCIDADE</small>
        <h2>Corrida de problemas</h2>
        <p>Quantos problemas você consegue resolver antes do tempo ou das vidas acabarem?</p>
        <div class="records">
          <dl><dt><Clock3 :size="13" /> 3 min</dt><dd>{{ summary?.rush_records['180'] || 0 }}</dd></dl>
          <dl><dt><Clock3 :size="13" /> 5 min</dt><dd>{{ summary?.rush_records['300'] || 0 }}</dd></dl>
        </div>
        <div class="actions">
          <NuxtLink to="/puzzles/session?mode=rush&duration=180">Corrida 3 min</NuxtLink>
          <NuxtLink to="/puzzles/session?mode=rush&duration=300">Corrida 5 min</NuxtLink>
        </div>
      </article>

      <article class="mode-card battle">
        <span class="icon"><Swords :size="28" aria-hidden="true" /></span>
        <small>COMPETIÇÃO</small>
        <h2>Batalha de problemas</h2>
        <p>Enfrente outro jogador na mesma sequência de problemas.</p>
        <dl><dt>Rating de batalha</dt><dd>{{ summary?.battle_rating || 1200 }}</dd></dl>
        <div class="actions">
          <NuxtLink to="/puzzles/battle/180">Batalha 3 min</NuxtLink>
          <NuxtLink to="/puzzles/battle/300">Batalha 5 min</NuxtLink>
        </div>
      </article>
    </section>
  </main>
</template>

<style scoped>
.hub-page { min-height:100vh; padding:clamp(1.2rem,4vw,3.5rem); color:#3c2b20; background-color:#f4eddf; background-image:radial-gradient(#bba98e35 .7px,transparent .7px); background-size:5px 5px; font-family:var(--font-sans); }
header { max-width:1040px; margin:0 auto 2rem; }header>span { color:#6f4528; font-size:.66rem; font-weight:900; letter-spacing:.15em; }h1 { margin:.2rem 0; font:500 clamp(2.5rem,5vw,4rem)/1 var(--font-serif); }header p { margin:.55rem 0 0; color:#806d5d; font-size:1.02rem; }
.mode-grid { display:grid; max-width:1040px; grid-template-columns:repeat(3,minmax(0,1fr)); gap:1rem; margin:auto; }.mode-card { --accent:#6f4528; display:flex; min-height:430px; flex-direction:column; gap:.7rem; padding:1.5rem; background:#fffaf0ed; border:1px solid #ddcbb0; border-radius:18px; box-shadow: 0 16px 34px rgb(0 0 0 / 14%); }.mode-card.rush { --accent:#9a4b28; }.mode-card.battle { --accent:#62416f; }.icon { display:grid; width:52px; height:52px; place-items:center; color:#fff8e8; background:var(--accent); border-radius:14px; box-shadow: 0 9px 20px rgb(0 0 0 / 14%); }.mode-card>small { margin-top:.3rem; color:var(--accent); font-size:.62rem; font-weight:900; letter-spacing:.13em; }.mode-card h2 { margin:0; font:600 1.8rem var(--font-serif); }.mode-card>p { min-height:3.2rem; margin:0; color:#806d5d; line-height:1.5; }.mode-card dl { display:flex; align-items:center; justify-content:space-between; margin:auto 0 0; padding:1rem; background:#f2e6d4; border:1px solid #dfccb0; border-radius:11px; }.mode-card dt { display:flex; align-items:center; gap:.3rem; color:#7b6655; font-size:.72rem; font-weight:800; }.mode-card dd { margin:0; color:var(--accent); font:700 1.6rem var(--font-serif); }.records { display:grid; grid-template-columns:1fr 1fr; gap:.5rem; margin-top:auto; }.records dl { margin:0; }.actions { display:flex; gap:.5rem; }.mode-card>a,.actions a { display:flex; min-height:44px; flex:1; align-items:center; justify-content:center; gap:.4rem; padding:.72rem; color:white; background:var(--accent); border:1px solid color-mix(in srgb,var(--accent) 80%,black); border-radius:9px; text-align:center; text-decoration:none; font-size:.82rem; font-weight:800; }.mode-card>a:hover,.actions a:hover { filter:brightness(1.1); }.mode-card a:focus-visible { outline:3px solid #d0a45d; outline-offset:2px; }.state { max-width:1040px; margin:3rem auto; text-align:center; color:#806d5d; }.state.error { color:#a04134; }
@media (max-width:900px) { .mode-grid { grid-template-columns:1fr; }.mode-card { min-height:360px; }.mode-card>p { min-height:0; } }.actions { flex-wrap:wrap; }
.hub-page { color: var(--text); background: var(--bg); }header>span { color: var(--brand-accent); }h1 { font-family: inherit; font-weight: 700; letter-spacing: -.04em; }header p, .state { color: var(--text-muted); }.state.error { color: var(--danger); }.mode-card, .mode-card.rush, .mode-card.battle { --accent: var(--brand-accent); background: var(--surface); border-color: var(--border-subtle); border-radius: 12px; box-shadow: var(--shadow); }.icon { color: var(--accent-ink); }.mode-card h2 { font-family: inherit; }.mode-card>p, .mode-card dt { color: var(--text-muted); }.mode-card dl { background: var(--surface-strong); border-color: var(--border); }.mode-card>a, .actions a { color: var(--accent-ink); border-color: var(--accent); }.mode-card a:focus-visible { outline-color: var(--accent); }
.hub-page > header, .hub-page > .state, .hub-page > .mode-grid { width: min(1300px, 100%); max-width: 1300px; margin-right: auto; margin-left: auto; }.mode-grid { gap: 1.25rem; }.mode-card { min-height: 430px; padding: 1.5rem; }
.hub-page { padding: clamp(1.25rem, 2.5vw, 2.25rem); }.hub-page > header, .hub-page > .state, .hub-page > .mode-grid { width: min(1180px, 100%); max-width: 1180px; }.hub-page > header { margin-bottom: 1.25rem; }.hub-page h1 { margin-top: .12rem; font-size: clamp(2.35rem, 4vw, 3.6rem); }.hub-page header p { margin-top: .4rem; }.mode-grid { gap: 1rem; }.mode-card { min-height: 410px; }
@media (max-width: 900px) { .mode-card { min-height: 360px; } }
</style>
