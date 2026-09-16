<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'default' })

type Bot = { id: string; name: string; nickname: string; rating: number; difficulty: string; persona: string }
type TimeControl = 'bullet_1_0' | 'blitz_3_0' | 'blitz_5_0' | 'rapid_10_0'
type ColorChoice = 'white' | 'black' | 'random'

const auth = useAuthStore()
const { request } = useApi()
const bots = ref<Bot[]>([])
const selectedBot = ref('clark')
const timeControl = ref<TimeControl>('blitz_3_0')
const color = ref<ColorChoice>('random')
const loading = ref(true)
const creating = ref(false)
const errorMessage = ref('')
const selectedBotDetails = computed(() => bots.value.find(bot => bot.id === selectedBot.value) || null)
const descriptions: Record<string, string> = {
  clark: 'Ótimo para dar seus primeiros passos.',
  jonathan: 'Equilibrado e previsível na medida certa.',
  renan: 'Mais sólido e estratégico, com bons fundamentos.',
  boris: 'Experiente, paciente e muito perigoso.',
  terminator: 'Frio, implacável e quase imbatível.'
}

const botPortrait = (id: string) => `/bots/${id}.webp`

const controls = [
  { id: 'bullet_1_0', label: 'Bullet 1+0' }, { id: 'blitz_3_0', label: 'Blitz 3+0' },
  { id: 'blitz_5_0', label: 'Blitz 5+0' }, { id: 'rapid_10_0', label: 'Rapid 10+0' }
] as const

onMounted(async () => {
  const result = await request<{ bots: Bot[] }>('/api/bots', { headers: { Authorization: `Bearer ${auth.token}` } })
  loading.value = false
  if (result.data) bots.value = result.data.bots
  else errorMessage.value = 'Não foi possível carregar os bots.'
})

async function play() {
  creating.value = true
  errorMessage.value = ''
  const result = await request<{ game_id: string }>('/api/bot-games', {
    method: 'POST', headers: { Authorization: `Bearer ${auth.token}` },
    body: { bot_id: selectedBot.value, time_control: timeControl.value, color: color.value }
  })
  creating.value = false
  if (result.data) await navigateTo(`/game/${result.data.game_id}/live`)
  else errorMessage.value = 'Não foi possível criar a partida contra o bot.'
}
</script>

<template>
  <main class="bots-page">
    <header><span>JOGAR CONTRA COMPUTADOR</span><h1>Escolha seu adversário</h1><p>Cinco personalidades, uma mesma engine. Partidas contra bots não alteram seu rating.</p></header>
    <p v-if="loading" class="state">Preparando os adversários…</p>
    <p v-else-if="errorMessage && !bots.length" class="state error">{{ errorMessage }}</p>
    <section v-else class="bot-grid">
      <button v-for="bot in bots" :key="bot.id" type="button" class="bot-card" :class="[{ selected: selectedBot === bot.id }, `bot-${bot.id}`]" @click="selectedBot = bot.id">
        <span class="portrait-wrap"><img :src="botPortrait(bot.id)" :alt="`Retrato de ${bot.name}`"><i v-if="selectedBot === bot.id">✓</i></span>
        <span class="difficulty">{{ bot.difficulty }}</span>
        <strong>{{ bot.name }}</strong>
        <small>{{ descriptions[bot.id] }}</small>
        <b>{{ bot.rating }} <span class="strength" aria-hidden="true"><i /><i /><i /></span></b>
      </button>
    </section>
    <section v-if="bots.length && selectedBotDetails" class="setup-card">
      <div class="selected-rival">
        <img class="selected-portrait" :src="botPortrait(selectedBotDetails.id)" :alt="`Retrato de ${selectedBotDetails.name}`">
        <div><span>SEU ADVERSÁRIO</span><strong>{{ selectedBotDetails.name }}</strong><small>{{ selectedBotDetails.difficulty }} · {{ selectedBotDetails.rating }}</small></div>
      </div>
      <div class="match-options">
        <label class="time-option"><span>Controle de tempo</span><select v-model="timeControl"><option v-for="item in controls" :key="item.id" :value="item.id">{{ item.label }}</option></select></label>
        <fieldset><legend>Jogar com</legend><label v-for="item in [{id:'white',label:'Brancas'},{id:'black',label:'Pretas'},{id:'random',label:'Surpresa'}]" :key="item.id"><input v-model="color" type="radio" :value="item.id"><span class="color-option" :class="`${item.id}-option`"><svg v-if="item.id !== 'random'" class="pawn-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="6" r="3.6"/><path d="M8.2 10h7.6l1.35 7.5H6.85z"/><path d="M6.5 17.5h11a2 2 0 0 1 2 2V21h-15v-1.5a2 2 0 0 1 2-2Z"/></svg><i v-else aria-hidden="true">⇄</i>{{ item.label }}</span></label></fieldset>
      </div>
      <button class="play" type="button" :disabled="creating" @click="play">
        <span>⚔ {{ creating ? 'Preparando o tabuleiro…' : `Desafiar ${selectedBotDetails.name}` }}</span>
        <small v-if="!creating">Partida casual · não altera rating <b>→</b></small>
      </button>
      <p v-if="errorMessage" class="error">{{ errorMessage }}</p>
    </section>
  </main>
</template>

<style scoped>
.bots-page { min-height: 100vh; padding: clamp(1rem, 2.5vw, 2rem); color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e35 .7px, transparent .7px); background-size: 5px 5px; font-family: var(--font-sans); }
header { max-width: 760px; margin-bottom: 1.15rem; } header > span { color: #6f4528; font-size: .65rem; font-weight: 800; letter-spacing: .14em; } h1 { margin: .18rem 0; font: 500 clamp(2rem, 4vw, 3.15rem)/1 var(--font-serif); } header p { margin: .35rem 0 0; color: #806d5d; line-height: 1.45; }
.bot-grid { display: grid; grid-template-columns: repeat(5, minmax(140px,1fr)); gap: .8rem; max-width: 1120px; }.bot-card { --level: #6f4528; display: grid; min-height: 390px; justify-items: center; align-content: start; gap: .45rem; padding: 1rem .8rem 1.15rem; color: inherit; background: linear-gradient(180deg,#fffaf0f2,#fbf3e6e8); border: 1px solid #e1d1ba; border-radius: 18px; box-shadow: 0 10px 24px rgb(0 0 0 / 14%); cursor: pointer; transition: transform 160ms, border-color 160ms, box-shadow 160ms; }.bot-card:hover { transform: translateY(-3px); border-color: #c0a37b; box-shadow: 0 15px 30px rgb(0 0 0 / 14%); }.bot-card.selected { border: 2px solid var(--level); box-shadow: 0 12px 28px rgb(0 0 0 / 14%); }.bot-card:focus-visible { outline: 3px solid #d0a45d; outline-offset: 3px; }.portrait-wrap { position: relative; display: block; width: min(100%,176px); aspect-ratio: 1; margin-bottom: .35rem; }.portrait-wrap img { width: 100%; height: 100%; object-fit: cover; border: 3px solid #ead4b3; border-radius: 50%; box-shadow: 0 6px 18px rgb(0 0 0 / 14%); }.portrait-wrap > i { position: absolute; top: 0; right: 0; display: grid; width: 30px; height: 30px; place-items: center; color: white; background: var(--level); border: 3px solid #fff8ec; border-radius: 50%; font-style: normal; font-weight: 900; }.difficulty { padding: .25rem .65rem; color: var(--level); background: color-mix(in srgb,var(--level) 15%,#fffaf0); border-radius: 999px; font-size: .66rem; font-weight: 900; text-transform: uppercase; letter-spacing: .07em; }.bot-card strong { margin-top: .1rem; font: 600 1.55rem var(--font-serif); }.bot-card small { min-height: 2.8rem; color: #766252; line-height: 1.45; }.bot-card b { margin-top: auto; color: var(--level); font-size: 1.35rem; }.strength { display: inline-flex; height: 18px; align-items: end; gap: 2px; }.strength i { display: block; width: 4px; height: 7px; background: currentColor; }.strength i:nth-child(2) { height: 12px; }.strength i:nth-child(3) { height: 17px; }.bot-clark { --level: #3f6a42; }.bot-jonathan { --level: #365f85; }.bot-renan { --level: #8b5616; }.bot-boris { --level: #5a3e78; }.bot-terminator { --level: #8b2d25; }
.setup-card { display: grid; max-width: 1120px; grid-template-columns: minmax(230px,.75fr) minmax(420px,1.5fr) minmax(250px,.85fr); align-items: stretch; margin-top: 1.2rem; overflow: hidden; background: #fffaf0e8; border: 1px solid #dfcfb8; border-radius: 18px; box-shadow: 0 14px 34px rgb(0 0 0 / 14%); }.selected-rival { display: flex; align-items: center; gap: .8rem; padding: 1rem 1.15rem; background: #f5e9d7; border-right: 1px solid #dbc6a8; }.selected-portrait { width: 62px; height: 62px; flex: 0 0 auto; object-fit: cover; border: 2px solid #d7ba92; border-radius: 50%; }.selected-rival > div { display: grid; gap: .08rem; }.selected-rival span { color: #6f4528; font-size: .62rem; font-weight: 900; letter-spacing: .11em; }.selected-rival strong { font: 600 1.3rem var(--font-serif); }.selected-rival small { color: #806d5d; }
.match-options { display: grid; grid-template-columns: minmax(150px,.75fr) minmax(245px,1.25fr); align-items: end; gap: 1rem; padding: .9rem 1.1rem; }.time-option { display: grid; gap: .4rem; }.setup-card label > span, legend { color: #806d5d; font-size: .72rem; font-weight: 800; }select { width: 100%; padding: .7rem .8rem; color: inherit; background: #fffaf0; border: 1px solid #d8c4aa; border-radius: 10px; font: inherit; }fieldset { display: flex; gap: .4rem; margin: 0; padding: 0; border: 0; }legend { margin-bottom: .4rem; }fieldset label { position: relative; flex: 1; }fieldset input { position: absolute; opacity: 0; }fieldset span { display: block; padding: .68rem .55rem; text-align: center; white-space: nowrap; background: #f3e7d5; border: 1px solid #dfcfb8; border-radius: 9px; cursor: pointer; transition: color 140ms, background 140ms, border-color 140ms; }fieldset input:checked + span { color:#4b3829; background:#eadcc7; border-color:#c9a976; box-shadow: inset 0 0 0 1px rgb(0 0 0 / 14%),0 5px 12px rgb(0 0 0 / 14%); }fieldset input:focus-visible + span { outline: 3px solid #d0a45d; outline-offset: 2px; }.color-option { display:flex; align-items:center; justify-content:center; gap:.42rem; }.pawn-icon { width:20px; height:20px; flex:0 0 auto; overflow:visible; stroke-width:1.35; stroke-linejoin:round; }.white-option .pawn-icon { fill:#fffdf8; stroke:#352a23; filter:drop-shadow(0 1px 1px #352a2340); }.black-option .pawn-icon { fill:#25201c; stroke:#fff8ec; }.random-option i { color:#9a6a2b; font:800 1.15rem/1 var(--font-sans); }
.play { display: grid; align-content: center; gap: .2rem; padding: .8rem 1.15rem; color: white; text-align: left; background: #6f4528; border: 0; border-left: 1px solid #5a351f; cursor: pointer; transition: background 150ms ease, transform 150ms ease, box-shadow 150ms ease; box-shadow: inset 0 1px rgb(0 0 0 / 14%), 0 12px 22px rgb(0 0 0 / 14%); }.play:hover { background: #7f5130; transform: translateY(-1px); }.play > span { font: 700 1.08rem var(--font-serif); }.play small { color: #f1dfcf; }.play b { float: right; margin-left: .5rem; font-size: 1rem; }.play:disabled { opacity: .6; cursor: wait; }.setup-card > .error { grid-column: 1/-1; margin: 0; padding: .65rem 1rem; background: #f6ded5; }.error { color: #a44232; }.state { padding: 2rem; text-align: center; }
@media (max-width: 1000px) { .bot-grid { grid-template-columns: repeat(3,1fr); }.setup-card { grid-template-columns: minmax(190px,.7fr) 1.3fr; }.play { grid-column: 1/-1; border-top: 1px solid #5a351f; border-left: 0; text-align: center; } }
@media (max-width: 680px) { .bots-page { padding: 1rem; }.bot-grid { grid-template-columns: repeat(2,1fr); }.setup-card { grid-template-columns: 1fr; }.selected-rival { border-right: 0; border-bottom: 1px solid #dbc6a8; }.match-options { grid-template-columns: 1fr; }.play { grid-column: auto; }fieldset { flex-wrap: wrap; } }
@media (max-width: 390px) { .bot-grid { grid-template-columns: 1fr; }fieldset label { min-width: 46%; } }
.bots-page { color: var(--text); background: var(--bg); }header { max-width: 920px; }header > span { color: var(--accent); }h1 { font-family: inherit; font-weight: 700; letter-spacing: -.04em; }header p, .bot-card small, .selected-rival small, .setup-card label > span, legend { color: var(--text-muted); }.bot-card { background: var(--surface); border-color: var(--border-subtle); border-radius: 12px; box-shadow: var(--shadow); }.bot-card:hover { border-color: var(--accent); box-shadow: var(--shadow); }.portrait-wrap img { border-color: var(--border); }.portrait-wrap > i { border-color: var(--surface); }.difficulty { background: color-mix(in srgb,var(--level) 18%,var(--surface)); }.setup-card { background: var(--surface); border-color: var(--border); border-radius: 12px; box-shadow: var(--shadow); }.selected-rival { background: var(--surface-strong); border-color: var(--border); }.selected-rival span { color: var(--accent); }select, fieldset span { color: var(--text); background: var(--surface-strong); border-color: var(--border); }fieldset input:checked + span { color:var(--text); background:var(--surface-hover); border-color:var(--accent); }.play { color: var(--accent-ink); background: var(--accent); border-color: var(--accent); }.play small { color: color-mix(in srgb,var(--accent-ink) 72%,transparent); }.play:hover { background: var(--accent-hover); }.setup-card > .error { color: var(--danger); background: var(--danger-soft); }.state.error { color: var(--danger); }
.bots-page { width: 100%; }.bots-page > header, .bots-page > .state, .bot-grid, .setup-card { width: min(1400px, 100%); margin-right: auto; margin-left: auto; }.bots-page > header { max-width: 1400px; }.bot-grid, .setup-card { max-width: 1400px; }.bot-grid { grid-template-columns: repeat(5, minmax(0, 1fr)); }.setup-card { margin-top: 1.2rem; }
@media (max-width: 1000px) { .bot-grid { grid-template-columns: repeat(3, 1fr); } }
@media (max-width: 680px) { .bot-grid { grid-template-columns: repeat(2, 1fr); } }
@media (max-width: 390px) { .bot-grid { grid-template-columns: 1fr; } }
.bots-page { padding: clamp(1rem, 2vw, 1.6rem); }.bots-page > header, .bots-page > .state, .bot-grid, .setup-card { width: min(1240px, 100%); max-width: 1240px; }.bots-page > header { margin-bottom: .9rem; }.bots-page h1 { font-size: clamp(1.9rem, 3.2vw, 2.75rem); }.bot-grid { gap: .7rem; }.bot-card { min-height: 350px; padding: .85rem .7rem 1rem; }.portrait-wrap { width: min(100%, 148px); }.bot-card strong { font-size: 1.35rem; }.bot-card small { min-height: 2.5rem; font-size: .82rem; }.bot-card b { font-size: 1.2rem; }.setup-card { margin-top: .9rem; }.selected-portrait { width: 54px; height: 54px; }.selected-rival { padding: .8rem 1rem; }.match-options { padding: .75rem 1rem; }.play { padding: .7rem 1rem; }
</style>
