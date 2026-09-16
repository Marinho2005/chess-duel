<script setup lang="ts">
const route = useRoute()
const auth = useAuthStore()
const links = [{ to: '/admin', label: 'Visão geral' }, { to: '/admin/users', label: 'Usuários' }, { to: '/admin/games', label: 'Partidas' }, { to: '/admin/system', label: 'Sistema' }]
function selected(path: string) { return path === '/admin' ? route.path === path : route.path.startsWith(path) }
</script>

<template>
  <div class="admin-shell">
    <NavigationAppHeader />
    <div v-if="auth.user?.role === 'admin' && auth.user.account_status === 'active'" class="admin-container">
      <header class="admin-heading"><div><p class="admin-eyebrow">CHESSDUEL</p><h1>Administração</h1></div><SettingsThemeSwitcher /></header>
      <nav class="admin-nav" aria-label="Administração"><NuxtLink v-for="link in links" :key="link.to" :to="link.to" :aria-current="selected(link.to) ? 'page' : undefined">{{ link.label }}</NuxtLink></nav>
      <main id="admin-content"><slot /></main>
    </div>
  </div>
</template>

<style>
.admin-shell { min-height: 100vh; color: var(--text); background: var(--bg); }
.admin-container { width: min(1240px, 100%); margin: auto; padding: clamp(1rem, 3vw, 2rem); }
.admin-heading, .admin-toolbar, .admin-title, .admin-pagination, .admin-actions { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 1rem; }
.admin-heading h1 { margin: .2rem 0 0; font-size: clamp(1.6rem, 3vw, 2.2rem); }
.admin-eyebrow { margin: 0; color: var(--text-muted); font-size: .72rem; letter-spacing: .12em; font-weight: 800; }
.admin-nav { display: flex; gap: .3rem; margin: 1.5rem 0; padding: .35rem; border: 1px solid var(--border); border-radius: 12px; background: var(--surface); overflow-x: auto; }
.admin-nav a { padding: .7rem 1rem; color: var(--text-muted); font-weight: 700; text-decoration: none; white-space: nowrap; border-radius: 8px; }
.admin-nav a[aria-current] { color: var(--accent-ink); background: var(--accent); }
.admin-shell main { display: grid; gap: 1rem; }
.admin-shell h2 { margin: 0; font-size: 1.25rem; }
.admin-shell h3 { margin-top: 0; font-size: 1rem; }
.admin-panel { padding: 1.2rem; border: 1px solid var(--border); border-radius: 12px; background: var(--surface); }
.admin-shell button, .admin-button { display: inline-flex; align-items: center; justify-content: center; min-height: 42px; padding: .6rem .9rem; border: 1px solid var(--border); border-radius: 8px; background: var(--surface-strong); color: var(--text); cursor: pointer; font: inherit; font-weight: 650; text-decoration: none; }
.admin-shell button:hover:not(:disabled), .admin-button:hover { background: var(--surface-hover); }
.admin-shell button:disabled { cursor: default; opacity: .55; }
.admin-shell button.primary { background: var(--accent); color: var(--accent-ink); border-color: var(--accent); }
.admin-shell button.danger { background: var(--danger-soft); color: var(--danger); border-color: var(--danger); }
.admin-shell :is(a, button, input, select, textarea):focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; }
.admin-shell label { display: grid; gap: .4rem; font-size: .88rem; }
.admin-shell :is(input, select, textarea) { box-sizing: border-box; width: 100%; min-height: 42px; padding: .65rem .75rem; color: var(--text); background: var(--bg); border: 1px solid var(--border); border-radius: 7px; font: inherit; }
.admin-shell textarea { resize: vertical; }
.admin-filters { display: flex; flex-wrap: wrap; align-items: end; gap: .8rem; }
.admin-filters label:first-child { flex: 1; min-width: 180px; }
.admin-table-scroll { width: 100%; overflow-x: auto; }
.admin-table { width: 100%; border-collapse: collapse; text-align: left; font-size: .88rem; }
.admin-table :is(th, td) { padding: .85rem .7rem; border-bottom: 1px solid var(--border-subtle); vertical-align: middle; }
.admin-table th { color: var(--text-muted); font-size: .78rem; font-weight: 700; white-space: nowrap; }
.admin-table td { overflow-wrap: anywhere; }
.admin-table a, .admin-link { color: var(--accent); text-underline-offset: 3px; }
.admin-table tbody tr:hover { background: var(--surface-hover); }
.admin-table small { display: block; margin-top: .2rem; color: var(--text-muted); }
.admin-table time { white-space: nowrap; }
.admin-muted { color: var(--text-muted); font-size: .88rem; line-height: 1.5; }
.admin-state { padding: 1.2rem; text-align: center; color: var(--text-muted); }
.admin-error { padding: .9rem; border: 1px solid var(--danger); border-radius: 8px; color: var(--danger); background: var(--danger-soft); }
.admin-success { padding: .9rem; border-radius: 8px; color: var(--success); background: var(--success-soft); }
.admin-pagination { justify-content: center; margin-top: 1rem; font-size: .88rem; }
.admin-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 260px), 1fr)); gap: 1rem; }
.admin-metric strong { display: block; margin: .5rem 0; font-size: 2rem; font-variant-numeric: tabular-nums; }
.admin-metric h3 { font-size: .9rem; color: var(--text-muted); font-weight: 600; margin-bottom: 0; }
.admin-details { display: grid; gap: .6rem; margin-bottom: 0; }
.admin-details div { display: flex; justify-content: space-between; flex-wrap: wrap; gap: .4rem 1rem; padding: .5rem 0; border-top: 1px solid var(--border-subtle); }
.admin-details dt { color: var(--text-muted); }
.admin-details dd { margin: 0; overflow-wrap: anywhere; }
.admin-badge { display: inline-flex; padding: .25rem .55rem; border-radius: 6px; background: var(--surface-strong); white-space: nowrap; font-size: .8rem; }
.admin-badge.active { background: var(--success-soft); color: var(--success); }
.admin-badge.banned, .admin-badge.suspended { background: var(--danger-soft); color: var(--danger); }
@media (max-width: 600px) { .admin-filters > label { flex: 1 1 100%; } .admin-nav a { padding: .65rem; font-size: .85rem; } .admin-panel { padding: .9rem; } }
</style>
