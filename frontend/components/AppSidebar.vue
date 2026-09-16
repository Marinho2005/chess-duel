<script setup lang="ts">
import { Bot, Crown, Eye, LogOut, Puzzle, Settings, Swords, Trophy } from 'lucide-vue-next'

const route = useRoute()
const auth = useAuthStore()

const items = [
  { key: 'play', label: 'Desafios', to: '/lobby', icon: Swords },
  { key: 'ranking', label: 'Ranking', to: '/ranking', icon: Trophy },
  { key: 'puzzles', label: 'Problemas', to: '/puzzles', icon: Puzzle },
  { key: 'bots', label: 'Bots', to: '/bots', icon: Bot },
  { key: 'watch', label: 'Observar', to: '/observar', icon: Eye },
  { key: 'profile', label: 'Editar perfil', to: '/settings/profile', icon: Settings }
]

function isActive(path: string) {
  return path === '/lobby' ? route.path === path : route.path.startsWith(path)
}

async function logOut() {
  await auth.logOut()
  await navigateTo('/')
}
</script>

<template>
  <aside class="sidebar">
    <NuxtLink class="logo" to="/lobby" aria-label="ChessDuel — Desafios">
      <BrandLogo />
    </NuxtLink>

    <nav aria-label="Navegação principal">
      <NuxtLink
        v-for="item in items"
        :key="item.to"
        :to="item.to"
        :class="[`nav-${item.key}`, { active: isActive(item.to) }]"
      >
        <component :is="item.icon" :size="20" :stroke-width="1.8" aria-hidden="true" />
        <span>{{ item.label }}</span>
      </NuxtLink>
    </nav>

    <div class="sidebar-bottom">
      <aside class="premium-card" aria-label="Plano Premium em breve">
        <Crown :size="23" :stroke-width="1.7" aria-hidden="true" />
        <div><strong>Plano Premium</strong><small>Em breve</small></div>
      </aside>

      <div class="sidebar-controls" aria-label="Controles da navegação">
        <button class="logout" type="button" title="Sair" @click="logOut">
          <LogOut :size="19" :stroke-width="1.8" aria-hidden="true" />
          <span>Sair</span>
        </button>
      </div>
    </div>
  </aside>
</template>

<style scoped>
.sidebar {
  --side-ink: #f8e7c4;
  --side-muted: #d8c095;
  --side-line: #d2a35a3d;
  --side-hover: #8d634533;
  --side-active: #8b63454f;
  position: sticky;
  top: 0;
  z-index: 20;
  display: flex;
  height: 100dvh;
  flex-direction: column;
  gap: 1.65rem;
  padding: 1.7rem 1.15rem 1.25rem;
  color: var(--side-ink);
  background:
    radial-gradient(circle at 20% 0%, #4a2f1a 0%, transparent 34%),
    linear-gradient(155deg, #21160e 0%, #342214 48%, #21170f 100%);
  border-right: 1px solid #8c673f;
  box-shadow: 12px 0 32px rgb(0 0 0 / 14%);
  font-family: var(--font-sans);
  transition: background 220ms ease, color 220ms ease;
}

.logo { --brand-mark-color: #efcb83; display: flex; align-items: center; color: var(--side-ink); font-size: 1.75rem; text-decoration: none; }
nav { display: grid; gap: .32rem; }
nav a { position: relative; display: grid; grid-template-columns: 24px 1fr auto; align-items: center; gap: .72rem; padding: .78rem .85rem; color: var(--side-muted); border: 1px solid transparent; border-radius: 11px; font: 650 .9rem var(--font-sans); text-decoration: none; transition: color 190ms ease, background 190ms ease, border-color 190ms ease, transform 190ms ease; }
nav a::before { position: absolute; left: -1px; width: 3px; height: 0; content: ''; background: #e2ad55; border-radius: 0 4px 4px 0; transition: height 190ms ease; }
nav a:hover, nav a:focus-visible { color: var(--side-ink); background: var(--side-hover); transform: translateX(2px); }
nav a:focus-visible { outline: 2px solid #e4b866; outline-offset: 2px; }
nav a.active { color: var(--side-ink); background: var(--side-active); border-color: var(--side-line); box-shadow: inset 0 1px rgb(0 0 0 / 14%), 0 7px 18px rgb(0 0 0 / 14%); }
nav a.active::before { height: 54%; }
nav a svg { transition: transform 210ms ease, color 210ms ease; transform-origin: center; }
nav a:hover svg, nav a:focus-visible svg, nav a.active svg { color: #efc477; }
.nav-play:hover svg, .nav-play:focus-visible svg { transform: rotate(-9deg) translateX(2px); }
.nav-ranking:hover svg, .nav-ranking:focus-visible svg { transform: translateY(-2px) scale(1.06); }
.nav-puzzles:hover svg, .nav-puzzles:focus-visible svg { transform: rotate(8deg); }
.nav-bots:hover svg, .nav-bots:focus-visible svg { transform: rotate(-5deg) scale(1.08); }
.nav-profile:hover svg, .nav-profile:focus-visible svg { transform: rotate(18deg); }
nav a.active svg { transform: scale(1.04); }
.sidebar-bottom { display: grid; gap: .8rem; margin-top: auto; }.premium-card { display: flex; align-items: center; gap: .7rem; padding: .85rem; color: #efc979; background: linear-gradient(135deg,#bd83351c,#efbf6524); border: 1px solid #d7a35342; border-radius: 12px; }.premium-card div { display: grid; gap: .12rem; }.premium-card strong { font: 700 .86rem var(--font-serif); }.premium-card small { color: var(--side-muted); font-size: .66rem; text-transform: uppercase; letter-spacing: .07em; }
.sidebar-controls { display: flex; justify-content: flex-end; gap: .55rem; }.sidebar-controls button { display: grid; width: 40px; height: 40px; place-items: center; padding: 0; color: var(--side-muted); background: #ffffff0a; border: 1px solid var(--side-line); border-radius: 10px; cursor: pointer; transition: color 180ms ease, background 180ms ease, transform 180ms ease; }.sidebar-controls button:hover,.sidebar-controls button:focus-visible { color: #f2cb82; background: #e3b55b20; transform: translateY(-1px); }.sidebar-controls button:focus-visible { outline: 2px solid #e4b866; outline-offset: 2px; }.logout span { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); }

@media (prefers-reduced-motion: reduce) {
  .sidebar, nav a, nav a::before, nav a svg, .sidebar-controls button { transition: none; }
  nav a:hover, nav a:focus-visible, .sidebar-controls button:hover, .sidebar-controls button:focus-visible { transform: none; }
  nav a:hover svg, nav a:focus-visible svg, nav a.active svg { transform: none; }
}

@media (max-width: 760px) {
  .sidebar { position: sticky; width: 100%; height: auto; padding: .65rem .8rem; flex-direction: row; align-items: center; gap: .5rem; border-right: 0; border-bottom: 1px solid #8c673f; box-shadow: 0 8px 22px rgb(0 0 0 / 14%); }
  .logo { font-size: 1.3rem; }
  nav { display: flex; flex: 1; justify-content: center; gap: .15rem; }
  nav a { display: flex; padding: .58rem; }
  nav a::before,nav a > span,.premium-card { display: none; }
  .sidebar-bottom { margin: 0; }
  .sidebar-controls { display: block; }
  .sidebar-controls .logout { width: 38px; height: 38px; }
}

@media (max-width: 520px) { .logo :deep(.brand-logo__word) { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); }.sidebar { gap: .2rem; }.logo { padding: .35rem; }nav { justify-content: space-around; }nav a { padding: .52rem; } }
</style>
