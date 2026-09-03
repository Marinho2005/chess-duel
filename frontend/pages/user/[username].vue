<script setup lang="ts">
import type { PlayerRatings } from '~/stores/auth'

definePageMeta({ layout: 'default' })

type RecentGame = { id:string; opponent:{nickname:string}; result:'win'|'loss'|'draw'; rating_change:number|null; rating_category:string|null; time_control:{label:string}; finished_at:string }
type PublicProfile = { id:string; nickname:string; country:string|null; country_code:string|null; avatar_url:string|null; inserted_at:string; ratings:PlayerRatings; stats:{total_games:number;win_rate:number;current_streak:number}; recent_games:RecentGame[] }

const route = useRoute(); const auth = useAuthStore(); const config = useRuntimeConfig()
const profile = ref<PublicProfile|null>(null); const loading = ref(true); const notFound = ref(false)
const isOwnProfile = computed(() => auth.user?.id === profile.value?.id)
const avatarUrl = computed(() => resolveAvatarUrl(profile.value?.avatar_url, config.public.api.baseURL))
const ratingCards = computed(() => profile.value ? [
  ['Bullet', profile.value.ratings.bullet], ['Blitz', profile.value.ratings.blitz],
  ['Rapid', profile.value.ratings.rapid]
] : [])

watch(() => route.params.username, loadProfile, { immediate:true })
async function loadProfile() {
  loading.value=true; notFound.value=false; auth.restoreSession(); if(auth.token) await auth.fetchCurrentUser()
  try { const username=encodeURIComponent(String(route.params.username)); const data=await $fetch<{profile:PublicProfile}>(`/api/users/${username}`,{baseURL:config.public.api.baseURL}); profile.value=data.profile }
  catch { profile.value=null; notFound.value=true } finally { loading.value=false }
}
function memberSince(value:string){return new Intl.DateTimeFormat('pt-BR',{month:'long',year:'numeric'}).format(new Date(value))}
function streak(value:number){if(!value)return 'Nenhuma'; return `${Math.abs(value)} ${value>0?'vitória(s)':'sem vitória'}`}
function resultLabel(value:RecentGame['result']){return value==='win'?'Vitória':value==='loss'?'Derrota':'Empate'}
</script>

<template>
  <main class="profile-page"><div class="content">
    <p v-if="loading" class="state">Carregando perfil…</p>
    <section v-else-if="notFound" class="state"><strong>Jogador não encontrado</strong><span>Confira o nome informado e tente novamente.</span></section>
    <template v-else-if="profile">
      <section class="hero">
        <img v-if="avatarUrl" :src="avatarUrl" :alt="`Avatar de ${profile.nickname}`"><span v-else class="avatar">{{ profile.nickname[0]?.toUpperCase() }}</span>
        <div><small>PERFIL DO JOGADOR</small><h1>{{ profile.nickname }}</h1><p><ProfileCountryFlag v-if="profile.country_code" :code="profile.country_code" show-name /><span v-else>País não informado</span> · Membro desde {{ memberSince(profile.inserted_at) }}</p></div>
        <NuxtLink v-if="isOwnProfile" class="edit" to="/settings/profile">Editar perfil</NuxtLink>
      </section>
      <section class="ratings"><article v-for="card in ratingCards" :key="card[0]"><span>{{ card[0] }}</span><strong>{{ card[1] }}</strong></article></section>
      <section class="stats"><article><strong>{{ profile.stats.total_games }}</strong><span>Partidas</span></article><article><strong>{{ profile.stats.win_rate }}%</strong><span>Vitórias</span></article><article><strong>{{ streak(profile.stats.current_streak) }}</strong><span>Sequência atual</span></article></section>
      <section class="recent"><h2>Partidas recentes</h2><p v-if="!profile.recent_games.length" class="empty">Nenhuma partida finalizada.</p><article v-for="game in profile.recent_games" :key="game.id"><b :class="game.result">{{ resultLabel(game.result) }}</b><div><strong>vs {{ game.opponent.nickname }}</strong><span>{{ game.time_control.label }}</span></div><em v-if="game.rating_change !== null" :class="{positive:game.rating_change>=0}">{{ game.rating_change>=0?'+':'' }}{{ game.rating_change }}</em></article></section>
    </template>
  </div></main>
</template>

<style scoped>
.profile-page{min-height:calc(100vh - 60px);padding:clamp(1rem,4vw,3rem);color:var(--text);background:var(--bg)}.content{display:grid;width:min(1080px,100%);gap:1.2rem;margin:auto}.hero,.ratings article,.stats,.recent,.state{background:var(--surface);border:1px solid var(--border);border-radius:14px;box-shadow:var(--shadow)}.hero{display:grid;grid-template-columns:auto 1fr auto;align-items:center;gap:1.3rem;padding:1.5rem}.hero img,.avatar{display:grid;width:88px;height:88px;place-items:center;object-fit:cover;color:var(--accent-ink);background:var(--accent);border-radius:50%;font-size:2rem;font-weight:800}.hero small{color:var(--accent);font-weight:850;letter-spacing:.12em}.hero h1{margin:.2rem 0;font-size:clamp(2rem,5vw,3.2rem);letter-spacing:-.04em}.hero p{margin:0;color:var(--text-muted)}.edit{padding:.7rem 1rem;color:var(--accent-ink);background:var(--accent);border-radius:9px;text-decoration:none;font-weight:800}.ratings{display:grid;grid-template-columns:repeat(4,1fr);gap:.8rem}.ratings article{display:grid;gap:.45rem;padding:1.2rem}.ratings span,.stats span,.recent article span{color:var(--text-muted)}.ratings strong{color:var(--accent);font-size:1.65rem}.stats{display:grid;grid-template-columns:repeat(3,1fr);padding:1.2rem}.stats article{display:grid;gap:.25rem;text-align:center}.stats article+article{border-left:1px solid var(--border-subtle)}.recent{padding:1.3rem}.recent h2{margin:0 0 1rem}.recent article{display:grid;grid-template-columns:80px 1fr auto;align-items:center;gap:1rem;padding:.8rem 0;border-top:1px solid var(--border-subtle)}.recent article div{display:grid}.recent b{color:var(--text-muted)}.recent b.win,.recent em.positive{color:var(--success)}.recent b.loss,.recent em{color:var(--danger)}.recent em{font-style:normal;font-weight:800}.state{display:grid;gap:.5rem;padding:3rem;text-align:center}.empty{color:var(--text-muted)}@media(max-width:700px){.hero{grid-template-columns:auto 1fr}.edit{grid-column:1/-1;text-align:center}.ratings{grid-template-columns:repeat(2,1fr)}.stats{grid-template-columns:1fr;gap:1rem}.stats article+article{padding-top:1rem;border-top:1px solid var(--border-subtle);border-left:0}}
</style>
<style scoped>.ratings{grid-template-columns:repeat(3,1fr)}</style>
