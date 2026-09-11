<script setup lang="ts">
definePageMeta({ layout: 'default' })

type PublicProfile = {
  id: string
  nickname: string
  country: string | null
  country_code: string | null
  avatar_url: string | null
  rating: number
  inserted_at: string
}

const route = useRoute()
const auth = useAuthStore()
const config = useRuntimeConfig()
const profile = ref<PublicProfile | null>(null)
const loading = ref(true)
const notFound = ref(false)
const isOwnProfile = computed(() => auth.user?.id === profile.value?.id)

const avatarUrl = computed(() => resolveAvatarUrl(
  profile.value?.avatar_url,
  config.public.api.baseURL
))

onMounted(async () => {
  auth.restoreSession()
  if (auth.token) await auth.fetchCurrentUser()
  await loadProfile()
})
watch(() => route.params.nickname, loadProfile)

async function loadProfile() {
  loading.value = true
  notFound.value = false

  try {
    const nickname = encodeURIComponent(String(route.params.nickname))
    const response = await $fetch<{ profile: PublicProfile }>(`/api/profiles/${nickname}`, {
      baseURL: config.public.api.baseURL
    })
    profile.value = response.profile
  } catch {
    profile.value = null
    notFound.value = true
  } finally {
    loading.value = false
  }
}

function memberSince(date: string) {
  return new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric' }).format(new Date(date))
}
</script>

<template>
  <main class="profile-shell">
    <NuxtLink class="back" to="/lobby">← Voltar para os desafios</NuxtLink>

    <section v-if="loading" class="card status">Carregando perfil...</section>
    <section v-else-if="notFound" class="card status">
      <span class="piece">♟</span>
      <h1>Jogador não encontrado</h1>
      <p>Esse perfil não existe ou o apelido foi alterado.</p>
    </section>
    <section v-else-if="profile" class="card">
      <div class="identity">
        <img v-if="avatarUrl" class="avatar" :src="avatarUrl" :alt="`Foto de ${profile.nickname}`">
        <span v-else class="avatar">{{ profile.nickname.charAt(0).toUpperCase() }}</span>
        <div>
          <span class="eyebrow">PERFIL DO JOGADOR</span>
          <h1>{{ profile.nickname }}</h1>
          <p v-if="profile.country_code"><ProfileCountryFlag :code="profile.country_code" show-name /></p>
          <p v-else>País não informado</p>
        </div>
      </div>

      <div class="stats">
        <article><strong>{{ profile.rating }}</strong><span>Rating atual</span></article>
        <article><strong>ELO</strong><span>Sistema competitivo</span></article>
      </div>

      <p class="member">Membro desde {{ memberSince(profile.inserted_at) }}</p>
      <NuxtLink v-if="isOwnProfile" class="history-link" to="/profile/history">Ver histórico de partidas →</NuxtLink>
    </section>
  </main>
</template>

<style scoped>
.profile-shell { min-height: 100vh; padding: clamp(1.2rem, 5vw, 4rem); color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e35 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: var(--font-sans); }
.back { display: inline-block; margin-bottom: 2rem; color: #7f5130; text-decoration: none; }.back:hover { text-decoration: underline; }
.card { width: min(720px, 100%); margin: 5vh auto 0; padding: clamp(1.5rem, 5vw, 3rem); background: #fffaf0e8; border: 1px solid #eadcc7; border-radius: 22px; box-shadow: 0 20px 45px #6f45281c; }
.identity { display: flex; align-items: center; gap: 1.5rem; }.avatar { display: grid; flex: 0 0 auto; width: 92px; height: 92px; place-items: center; color: white; object-fit: cover; background: #6f4528; border-radius: 50%; font: 700 2.2rem var(--font-serif); }
.eyebrow { color: #6f4528; font-size: 0.72rem; font-weight: 800; letter-spacing: 0.12em; }.identity h1 { margin: 0.3rem 0; font: 500 clamp(2rem, 6vw, 3.4rem) var(--font-serif); }.identity p, .member { margin: 0; color: #857060; }
.stats { display: grid; grid-template-columns: repeat(2, 1fr); gap: 1rem; margin: 2.5rem 0; }.stats article { display: grid; gap: 0.35rem; padding: 1.4rem; background: #efe3cf; border: 1px solid #dfcfb8; border-radius: 14px; }.stats strong { color: #6f4528; font: 500 1.8rem var(--font-serif); }.stats span { color: #806d5d; }
.status { text-align: center; }.piece { color: #6f4528; font-size: 3rem; }.status h1 { font-family: var(--font-serif); }
.history-link { display: inline-block; margin-top: 1.5rem; padding: .85rem 1.1rem; color: white; font-weight: 700; text-decoration: none; background: #6f4528; border-radius: 10px; }
@media (max-width: 560px) { .identity { align-items: flex-start; }.avatar { width: 64px; height: 64px; }.stats { grid-template-columns: 1fr; } }

.profile-shell { color:var(--text); background:var(--bg); }
.back,.eyebrow,.piece { color:var(--accent); }
.card { color:var(--text); background:color-mix(in srgb,var(--surface) 96%,transparent); border-color:var(--border); box-shadow:var(--shadow); }
.avatar { color:var(--accent-ink); background:var(--accent); }
.identity p,.member,.stats span { color:var(--text-muted); }
.stats article { background:var(--surface-strong); border-color:var(--border); }
.stats strong { color:var(--accent); }
.history-link { color:var(--accent-ink); background:var(--accent); }
.history-link:hover { background:var(--accent-hover); }
</style>
