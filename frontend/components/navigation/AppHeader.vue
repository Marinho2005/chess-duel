<script setup lang="ts">
import { ChevronDown, LogOut, Menu, Settings, UserRound, X } from 'lucide-vue-next'

const route = useRoute()
const auth = useAuthStore()
const config = useRuntimeConfig()
const mobileOpen = ref(false)
const profileOpen = ref(false)
const presenceLabels = {
  online: 'Online',
  away: 'Ausente',
  dnd: 'Não perturbar',
  invisible: 'Invisível'
} as const

const items = [
  { label: 'Jogar', to: '/lobby', match: ['/lobby', '/play', '/room'] },
  { label: 'Observar', to: '/observar', match: ['/observar'] },
  { label: 'Ranking', to: '/ranking', match: ['/ranking'] },
  { label: 'Problemas', to: '/puzzles', match: ['/puzzles'] },
  { label: 'Bots', to: '/bots', match: ['/bots'] }
]

const avatarUrl = computed(() => resolveAvatarUrl(auth.user?.avatar_url, config.public.api.baseURL))
const presenceLabel = computed(() => presenceLabels[auth.presence])

function isActive(item: typeof items[number]) {
  return item.match.some(path => route.path.startsWith(path))
}

function closeMenus() {
  mobileOpen.value = false
  profileOpen.value = false
}

async function logOut() {
  closeMenus()
  await auth.logOut()
  await navigateTo('/')
}

watch(() => route.fullPath, closeMenus)
</script>

<template>
  <header class="app-header">
    <div class="header-inner">
      <NuxtLink class="brand" to="/lobby" aria-label="ChessDuel — Jogar">
        <span aria-hidden="true">♟</span><strong>ChessDuel</strong>
      </NuxtLink>

      <nav class="desktop-nav" aria-label="Navegação principal">
        <NuxtLink v-for="item in items" :key="item.label" :to="item.to" :class="{ active: isActive(item) }">
          {{ item.label }}
        </NuxtLink>
      </nav>

      <slot name="context-actions" />

      <div class="account">
        <span v-if="auth.user" class="rating">{{ auth.user.rating }} rating</span>
        <button class="profile-trigger" type="button" :aria-expanded="profileOpen" aria-haspopup="menu" aria-label="Abrir menu do perfil" @click="profileOpen = !profileOpen">
          <span class="profile-avatar">
            <img v-if="avatarUrl" :src="avatarUrl" alt="">
            <span v-else class="avatar-fallback">{{ auth.user?.nickname?.charAt(0).toUpperCase() || '♟' }}</span>
            <span class="profile-status-dot" :class="auth.presence" role="img" :aria-label="presenceLabel" :title="presenceLabel" />
          </span>
          <ChevronDown :size="17" aria-hidden="true" />
        </button>
        <div v-if="profileOpen" class="profile-menu" role="menu">
          <NuxtLink v-if="auth.user" :to="`/user/${encodeURIComponent(auth.user.nickname)}`" role="menuitem"><UserRound :size="17" />Perfil</NuxtLink>
          <NuxtLink to="/settings/profile" role="menuitem"><Settings :size="17" />Configurações</NuxtLink>
          <button type="button" role="menuitem" @click="logOut"><LogOut :size="17" />Sair</button>
        </div>
      </div>

      <button class="menu-trigger" type="button" :aria-expanded="mobileOpen" aria-controls="mobile-navigation" :aria-label="mobileOpen ? 'Fechar menu' : 'Abrir menu'" @click="mobileOpen = !mobileOpen">
        <X v-if="mobileOpen" :size="23" aria-hidden="true" /><Menu v-else :size="23" aria-hidden="true" />
      </button>
    </div>

    <nav v-if="mobileOpen" id="mobile-navigation" class="mobile-nav" aria-label="Navegação principal mobile">
      <NuxtLink v-for="item in items" :key="item.label" :to="item.to" :class="{ active: isActive(item) }">{{ item.label }}</NuxtLink>
      <NuxtLink to="/settings/profile">Configurações</NuxtLink>
      <button type="button" @click="logOut">Sair</button>
    </nav>
  </header>
</template>

<style scoped>
.app-header { position: sticky; top: 0; z-index: 50; background: color-mix(in srgb, var(--bg-elevated) 94%, transparent); border-bottom: 1px solid var(--border-subtle); backdrop-filter: blur(16px); }
.header-inner { display: flex; width: min(1440px, calc(100% - 3rem)); min-height: 60px; align-items: stretch; gap: 2.4rem; margin: auto; }
.brand { display: flex; align-items: center; gap: .65rem; color: var(--text); text-decoration: none; }
.brand > span { color: var(--accent); font-size: 1.8rem; line-height: 1; }
.brand strong { font-family: Georgia, "Times New Roman", serif; font-size: 1.35rem; font-weight: 700; letter-spacing: -.035em; }
.desktop-nav { display: flex; align-items: stretch; gap: 1.9rem; }
.desktop-nav a { position: relative; display: flex; align-items: center; color: var(--text-muted); font-weight: 600; text-decoration: none; transition: color 180ms ease; }
.desktop-nav a::after { position: absolute; right: 0; bottom: 0; left: 0; height: 2px; content: ''; background: var(--accent); transform: scaleX(0); transition: transform 180ms ease; }
.desktop-nav a:hover, .desktop-nav a.active { color: var(--text); }
.desktop-nav a.active::after { transform: scaleX(1); }
.account { position: relative; display: flex; align-items: center; gap: 1rem; margin-left: auto; }
.rating { color: var(--text-muted); font-size: .9rem; }
.profile-trigger, .menu-trigger { display: flex; align-items: center; gap: .45rem; padding: .25rem; color: var(--text); background: transparent; border: 0; border-radius: 10px; cursor: pointer; }
.profile-avatar { position: relative; display: inline-grid; width: 38px; height: 38px; flex: 0 0 auto; }
.profile-trigger img, .avatar-fallback { display: grid; width: 38px; height: 38px; place-items: center; object-fit: cover; color: var(--accent-ink); background: var(--accent); border-radius: 10px; font-weight: 800; }
.profile-status-dot { position: absolute; right: -3px; bottom: -3px; width: 10px; height: 10px; background: var(--success); border: 3px solid var(--bg-elevated); border-radius: 50%; box-sizing: content-box; }
.profile-status-dot.online { background: var(--success); box-shadow: 0 0 6px var(--success); }
.profile-status-dot.away { background: #e7a83e; }
.profile-status-dot.dnd { background: var(--danger); }
.profile-status-dot.dnd::after { position: absolute; top: 4px; right: 2px; left: 2px; height: 2px; content: ''; background: var(--bg-elevated); border-radius: 2px; }
.profile-status-dot.invisible { width: 8px; height: 8px; background: var(--bg-elevated); border: 3px solid var(--text-muted); box-shadow: 0 0 0 2px var(--bg-elevated); }
.profile-trigger svg { transition: transform 180ms ease; }.profile-trigger[aria-expanded='true'] svg { transform: rotate(180deg); }
.profile-menu { position: absolute; top: calc(100% - 8px); right: 0; display: grid; width: 190px; padding: .45rem; background: var(--surface); border: 1px solid var(--border); border-radius: 12px; box-shadow: var(--shadow); }
.profile-menu a, .profile-menu button { display: flex; align-items: center; gap: .65rem; padding: .7rem .75rem; color: var(--text); background: transparent; border: 0; border-radius: 8px; text-align: left; text-decoration: none; cursor: pointer; }
.profile-menu a:hover, .profile-menu button:hover { background: var(--surface-hover); }
.menu-trigger, .mobile-nav { display: none; }
@media (max-width: 820px) {
  .header-inner { width: calc(100% - 2rem); min-height: 58px; }.desktop-nav, .account { display: none; }.menu-trigger { display: flex; margin-left: auto; }
  .mobile-nav { display: grid; gap: .25rem; padding: .5rem 1rem 1rem; border-top: 1px solid var(--border-subtle); }
  .mobile-nav a, .mobile-nav button { padding: .8rem; color: var(--text-muted); background: transparent; border: 0; border-radius: 9px; font-weight: 650; text-align: left; text-decoration: none; }
  .mobile-nav a:hover, .mobile-nav a.active, .mobile-nav button:hover { color: var(--text); background: var(--surface); }
  .mobile-nav a.active { box-shadow: inset 3px 0 var(--accent); }
}
</style>
