<script setup lang="ts">
import { Bell, ChevronDown, LogOut, Megaphone, Menu, Settings, Shield, UserPlus, X } from 'lucide-vue-next'

const route = useRoute()
const auth = useAuthStore()
const config = useRuntimeConfig()
const mobileOpen = ref(false)
const notificationsOpen = ref(false)
const socialOpen = ref(false)
const socialTrigger = ref<HTMLButtonElement | null>(null)
const accountMenu = ref<HTMLElement | null>(null)
type NotificationPlayer = { id: string; nickname: string; avatar_url: string | null }
type FriendshipNotification = { id: string; status: 'pending' | 'accepted' | 'declined'; direction: 'incoming' | 'outgoing'; user: NotificationPlayer }
const friendshipNotifications = ref<FriendshipNotification[]>([])
const notificationsLoading = ref(false)
let notificationsTimer: ReturnType<typeof setInterval> | undefined
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
const avatarFailed = ref(false)
watch([avatarUrl, () => auth.user?.id], () => { avatarFailed.value = false })
const presenceLabel = computed(() => presenceLabels[auth.presence])
const incomingRequests = computed(() => friendshipNotifications.value.filter(item => item.status === 'pending' && item.direction === 'incoming'))
const notificationCount = computed(() => incomingRequests.value.length)

function isActive(item: typeof items[number]) {
  return item.match.some(path => route.path.startsWith(path))
}

function closeMenus() {
  mobileOpen.value = false
  notificationsOpen.value = false
  socialOpen.value = false
}

async function loadNotifications() {
  if (!auth.token || !auth.user) {
    friendshipNotifications.value = []
    return
  }

  notificationsLoading.value = true
  try {
    const data = await $fetch<{ friendships: FriendshipNotification[] }>('/api/friendships', {
      baseURL: config.public.api.baseURL,
      headers: { Authorization: `Bearer ${auth.token}` }
    })
    friendshipNotifications.value = data.friendships
  } catch {
    friendshipNotifications.value = []
  } finally {
    notificationsLoading.value = false
  }
}

function toggleNotifications() {
  notificationsOpen.value = !notificationsOpen.value
  if (notificationsOpen.value) void loadNotifications()
}

function closeAccountMenus(event: PointerEvent) {
  if (!accountMenu.value?.contains(event.target as Node)) {
    notificationsOpen.value = false
  }
}

function closeSocial(event: FocusEvent) {
  if (!(event.currentTarget as HTMLElement).contains(event.relatedTarget as Node | null)) socialOpen.value = false
}

function escapeSocial() {
  socialOpen.value = false
  socialTrigger.value?.focus()
}

async function logOut() {
  closeMenus()
  await auth.logOut()
  await navigateTo('/')
}

watch(() => route.fullPath, closeMenus)
watch(() => auth.user?.id, () => { void loadNotifications() })

onMounted(() => {
  document.addEventListener('pointerdown', closeAccountMenus)
  void loadNotifications()
  notificationsTimer = setInterval(() => {
    if (!document.hidden) void loadNotifications()
  }, 15000)
})

onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', closeAccountMenus)
  clearInterval(notificationsTimer)
})
</script>

<template>
  <header class="app-header">
    <div class="header-inner">
      <NuxtLink class="brand" to="/lobby" aria-label="ChessDuel — Jogar">
        <BrandLogo />
      </NuxtLink>

      <nav class="desktop-nav" aria-label="Navegação principal">
        <NuxtLink v-for="item in items" :key="item.label" :to="item.to" :class="{ active: isActive(item) }">
          {{ item.label }}
        </NuxtLink>
        <div class="social-nav" @mouseenter="socialOpen = true" @mouseleave="socialOpen = false" @focusout="closeSocial" @keydown.esc.stop.prevent="escapeSocial">
          <button ref="socialTrigger" type="button" class="social-trigger" :class="{ active: route.path.startsWith('/social') }" :aria-expanded="socialOpen" aria-controls="social-navigation" @click="socialOpen = !socialOpen" @keydown.down.prevent="socialOpen = true">
            Social <ChevronDown :size="15" aria-hidden="true" />
          </button>
          <div v-if="socialOpen" id="social-navigation" class="social-dropdown">
            <NuxtLink to="/social/friends">Amigos</NuxtLink>
            <NuxtLink to="/social/clubs">Clubes</NuxtLink>
          </div>
        </div>
      </nav>

      <slot name="context-actions" />

      <div ref="accountMenu" class="account" @keydown.esc.stop="notificationsOpen = false">
        <button v-if="auth.user" class="notification-trigger" type="button" :aria-expanded="notificationsOpen" aria-haspopup="dialog" aria-controls="notifications-panel" :aria-label="notificationCount ? `Notificações: ${notificationCount} nova${notificationCount === 1 ? '' : 's'}` : 'Notificações'" @click="toggleNotifications">
          <Bell :size="21" aria-hidden="true" />
          <span v-if="notificationCount" class="notification-badge" aria-hidden="true">{{ notificationCount > 9 ? '9+' : notificationCount }}</span>
        </button>
        <div v-if="notificationsOpen" id="notifications-panel" class="notifications-panel" role="dialog" aria-label="Notificações">
          <header class="notifications-heading">
            <strong>Notificações</strong>
            <span>{{ notificationCount ? `${notificationCount} nova${notificationCount === 1 ? '' : 's'}` : 'Tudo em dia' }}</span>
          </header>
          <section class="notification-section" aria-labelledby="friend-request-title">
            <h2 id="friend-request-title"><UserPlus :size="17" aria-hidden="true" /> Convites de amizade</h2>
            <p v-if="notificationsLoading && !incomingRequests.length" class="notification-empty" role="status">Atualizando…</p>
            <p v-else-if="!incomingRequests.length" class="notification-empty">Nenhum convite novo.</p>
            <NuxtLink v-for="request in incomingRequests" :key="request.id" class="notification-item" to="/social/friends">
              <span class="notification-avatar">
                <img v-if="request.user.avatar_url" :src="resolveAvatarUrl(request.user.avatar_url, config.public.api.baseURL) || undefined" alt="">
                <span v-else>{{ request.user.nickname.charAt(0).toUpperCase() }}</span>
              </span>
              <span><strong>{{ request.user.nickname }}</strong><small>enviou um convite de amizade</small></span>
            </NuxtLink>
          </section>
          <section class="notification-section" aria-labelledby="site-message-title">
            <h2 id="site-message-title"><Megaphone :size="17" aria-hidden="true" /> Mensagens do ChessDuel</h2>
            <p class="notification-empty">Nenhuma mensagem nova.</p>
          </section>
        </div>
        <NuxtLink v-if="auth.user?.role === 'admin'" class="settings-trigger" to="/admin" aria-label="Administração" title="Administração"><Shield :size="19" /></NuxtLink>
        <NuxtLink v-if="auth.user" class="settings-trigger" to="/settings/profile" aria-label="Configurações" title="Configurações">
          <Settings :size="21" aria-hidden="true" />
        </NuxtLink>
        <button v-if="auth.user" class="logout-trigger" type="button" aria-label="Sair" title="Sair" @click="logOut">
          <LogOut :size="21" aria-hidden="true" />
        </button>
        <NuxtLink v-if="auth.user" class="profile-avatar-link" :to="`/user/${encodeURIComponent(auth.user.nickname)}`" aria-label="Abrir seu perfil" title="Abrir seu perfil">
          <span class="profile-avatar">
            <img v-if="avatarUrl && !avatarFailed" :key="avatarUrl" :src="avatarUrl" alt="" referrerpolicy="no-referrer" @error="avatarFailed = true">
            <span v-else class="avatar-fallback">{{ auth.user?.nickname?.charAt(0).toUpperCase() || '♟' }}</span>
            <span class="profile-status-dot" :class="auth.presence" role="img" :aria-label="presenceLabel" :title="presenceLabel" />
          </span>
        </NuxtLink>
      </div>

      <button class="menu-trigger" type="button" :aria-expanded="mobileOpen" aria-controls="mobile-navigation" :aria-label="mobileOpen ? 'Fechar menu' : 'Abrir menu'" @click="mobileOpen = !mobileOpen">
        <X v-if="mobileOpen" :size="23" aria-hidden="true" /><Menu v-else :size="23" aria-hidden="true" />
      </button>
    </div>

    <nav v-if="mobileOpen" id="mobile-navigation" class="mobile-nav" aria-label="Navegação principal mobile">
      <NuxtLink v-for="item in items" :key="item.label" :to="item.to" :class="{ active: isActive(item) }">{{ item.label }}</NuxtLink>
      <NuxtLink v-if="auth.user" class="mobile-notifications" to="/social/friends"><Bell :size="18" aria-hidden="true" />Notificações <span v-if="notificationCount">{{ notificationCount > 9 ? '9+' : notificationCount }}</span></NuxtLink>
      <NuxtLink v-if="auth.user?.role === 'admin'" to="/admin">Administração</NuxtLink>
      <NuxtLink to="/settings/profile">Configurações</NuxtLink>
      <span class="mobile-social-label">Social</span>
      <NuxtLink to="/social/friends">Amigos</NuxtLink>
      <NuxtLink to="/social/clubs">Clubes</NuxtLink>
      <button type="button" @click="logOut">Sair</button>
    </nav>
  </header>
</template>

<style scoped>
.app-header { position: sticky; top: 0; z-index: 50; background: color-mix(in srgb, var(--bg-elevated) 94%, transparent); border-bottom: 1px solid var(--border-subtle); backdrop-filter: blur(16px); }
.header-inner { display: flex; width: min(1440px, calc(100% - 3rem)); min-height: 60px; align-items: stretch; gap: 2.4rem; margin: auto; }
.brand { display: flex; align-items: center; color: var(--text); font-size: 1.8rem; text-decoration: none; }
.desktop-nav { display: flex; align-items: stretch; gap: 1.9rem; }
.social-nav { position: relative; display: flex; }
.social-trigger { display: flex; align-items: center; gap: .35rem; padding: 0; color: var(--text-muted); background: transparent; border: 0; font-weight: 600; cursor: pointer; }
.social-trigger:hover, .social-trigger.active { color: var(--text); }
.social-dropdown { position: absolute; top: 100%; left: -.75rem; display: grid; min-width: 160px; padding: .45rem; background: var(--surface); border: 1px solid var(--border); border-radius: 0 0 12px 12px; box-shadow: var(--shadow); }
.desktop-nav .social-dropdown a { padding: .75rem; border-radius: 8px; }
.desktop-nav .social-dropdown a:hover { background: var(--surface-hover); }
.mobile-social-label { padding: .8rem .8rem .25rem; color: var(--text-muted); font-size: .8rem; }
.desktop-nav a { position: relative; display: flex; align-items: center; color: var(--text-muted); font-weight: 600; text-decoration: none; transition: color 180ms ease; }
.desktop-nav a::after { position: absolute; right: 0; bottom: 0; left: 0; height: 2px; content: ''; background: var(--accent); transform: scaleX(0); transition: transform 180ms ease; }
.desktop-nav a:hover, .desktop-nav a.active { color: var(--text); }
.desktop-nav a.active::after { transform: scaleX(1); }
.account { position: relative; display: flex; align-items: center; gap: .65rem; margin-left: auto; }
.notification-trigger, .settings-trigger, .logout-trigger, .profile-avatar-link, .menu-trigger { display: flex; align-items: center; justify-content: center; gap: .45rem; padding: .45rem; color: var(--text); background: transparent; border: 0; border-radius: 10px; cursor: pointer; text-decoration: none; }
.notification-trigger { position: relative; justify-content: center; width: 38px; height: 38px; color: var(--text-muted); }
.notification-trigger:hover, .notification-trigger[aria-expanded='true'] { color: var(--text); background: var(--surface-hover); }
.settings-trigger { width: 38px; height: 38px; color: var(--text-muted); }.settings-trigger:hover { color: var(--text); background: var(--surface-hover); }
.logout-trigger { width: 38px; height: 38px; color: var(--text-muted); }.logout-trigger:hover { color: var(--danger); background: var(--danger-soft); }
.notification-badge { position: absolute; top: 0; right: -2px; display: grid; min-width: 17px; height: 17px; padding: 0 4px; place-items: center; color: white; background: var(--danger); border: 2px solid var(--bg-elevated); border-radius: 999px; font-size: .62rem; font-weight: 800; line-height: 1; }
.notifications-panel { position: absolute; top: calc(100% - 8px); right: 144px; width: min(360px, calc(100vw - 2rem)); overflow: hidden; color: var(--text); background: var(--surface); border: 1px solid var(--border); border-radius: 14px; box-shadow: var(--shadow); }
.notifications-heading { display: flex; align-items: center; justify-content: space-between; gap: 1rem; padding: 1rem; border-bottom: 1px solid var(--border-subtle); }
.notifications-heading > span { color: var(--text-muted); font-size: .78rem; }
.notification-section { padding: .85rem 1rem; }
.notification-section + .notification-section { border-top: 1px solid var(--border-subtle); }
.notification-section h2 { display: flex; align-items: center; gap: .5rem; margin: 0 0 .65rem; color: var(--text-muted); font-size: .78rem; letter-spacing: .025em; text-transform: uppercase; }
.notification-section h2 svg { color: var(--accent); }
.notification-empty { margin: 0; padding: .45rem 0; color: var(--text-muted); font-size: .85rem; }
.notification-item { display: flex; align-items: center; gap: .7rem; padding: .65rem; margin: 0 -.35rem; color: var(--text); border-radius: 9px; text-decoration: none; }
.notification-item:hover { background: var(--surface-hover); }
.notification-item > span:last-child { display: grid; min-width: 0; }
.notification-item small { margin-top: .15rem; color: var(--text-muted); }
.notification-avatar, .notification-avatar img, .notification-avatar > span { display: grid; width: 34px; height: 34px; flex: 0 0 auto; place-items: center; object-fit: cover; color: var(--accent-ink); background: var(--accent); border-radius: 9px; font-weight: 800; }
.profile-avatar { position: relative; display: inline-grid; width: 38px; height: 38px; flex: 0 0 auto; }
.profile-avatar-link { padding: 0; }.profile-avatar-link:hover { background: transparent; }.profile-avatar-link img, .avatar-fallback { display: grid; width: 38px; height: 38px; place-items: center; object-fit: cover; color: var(--accent-ink); background: var(--accent); border-radius: 10px; font-weight: 800; }
.profile-status-dot { position: absolute; right: -3px; bottom: -3px; width: 10px; height: 10px; background: var(--success); border: 3px solid var(--bg-elevated); border-radius: 50%; box-sizing: content-box; }
.profile-status-dot.online { background: var(--success); }
.profile-status-dot.away { background: #e7a83e; }
.profile-status-dot.dnd { background: var(--danger); }
.profile-status-dot.dnd::after { position: absolute; top: 4px; right: 2px; left: 2px; height: 2px; content: ''; background: var(--bg-elevated); border-radius: 2px; }
.profile-status-dot.invisible { width: 8px; height: 8px; background: var(--bg-elevated); border: 3px solid var(--text-muted); box-shadow: 0 0 0 2px var(--bg-elevated); }
.menu-trigger, .mobile-nav { display: none; }
@media (max-width: 1020px) {
  .header-inner { width: calc(100% - 2rem); min-height: 58px; }.desktop-nav, .account { display: none; }.menu-trigger { display: flex; margin-left: auto; }
  .mobile-nav { display: grid; gap: .25rem; padding: .5rem 1rem 1rem; border-top: 1px solid var(--border-subtle); }
  .mobile-nav a, .mobile-nav button { padding: .8rem; color: var(--text-muted); background: transparent; border: 0; border-radius: 9px; font-weight: 650; text-align: left; text-decoration: none; }
  .mobile-nav .mobile-notifications { display: flex; align-items: center; gap: .65rem; }.mobile-notifications span { display: grid; min-width: 20px; height: 20px; margin-left: auto; padding: 0 5px; place-items: center; color: white; background: var(--danger); border-radius: 999px; font-size: .7rem; }
  .mobile-nav a:hover, .mobile-nav a.active, .mobile-nav button:hover { color: var(--text); background: var(--surface); }
  .mobile-nav a.active { box-shadow: inset 3px 0 var(--accent); }
}
</style>
