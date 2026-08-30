<script setup lang="ts">
import { Bot, LogOut, Puzzle, Settings, Swords, Trophy } from 'lucide-vue-next'

const route = useRoute()
const auth = useAuthStore()

const items = [
  { label: 'Desafios', to: '/lobby', icon: Swords },
  { label: 'Ranking', to: '/ranking', icon: Trophy },
  { label: 'Puzzles', to: '/puzzles', icon: Puzzle },
  { label: 'Bots', to: '/bots', icon: Bot },
  { label: 'Editar perfil', to: '/settings/profile', icon: Settings }
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
      <span aria-hidden="true">♟</span><strong>ChessDuel</strong>
    </NuxtLink>

    <nav aria-label="Navegação principal">
      <NuxtLink
        v-for="item in items"
        :key="item.to"
        :to="item.to"
        :class="{ active: isActive(item.to) }"
      >
        <component :is="item.icon" :size="20" :stroke-width="1.8" aria-hidden="true" />
        <span>{{ item.label }}</span>
      </NuxtLink>
    </nav>

    <button class="logout" type="button" @click="logOut">
      <LogOut :size="19" :stroke-width="1.8" aria-hidden="true" />
      <span>Sair</span>
    </button>
  </aside>
</template>

<style scoped>
.sidebar {
  position: sticky;
  top: 0;
  z-index: 20;
  display: flex;
  height: 100vh;
  flex-direction: column;
  gap: 2rem;
  padding: 2rem 1.4rem;
  color: #3c2b20;
  background: #fffaf0ee;
  border-right: 1px solid #dfcfb8;
  font-family: Inter, system-ui, sans-serif;
}

.logo { display: flex; align-items: center; gap: .45rem; color: #925b35; text-decoration: none; }
.logo > span { font-size: 1.45rem; }
.logo strong { font: 700 1.7rem Georgia, serif; }
nav { display: grid; gap: .45rem; }
nav a, .logout { display: flex; align-items: center; gap: .75rem; padding: .85rem 1rem; border-radius: 10px; font: 600 .92rem Inter, system-ui, sans-serif; }
nav a { color: #806d5d; text-decoration: none; border: 1px solid transparent; }
nav a:hover { color: #5a3c29; background: #f5ead8; }
nav a.active { color: #3c2b20; background: #efe2ce; border-color: #dfcfb8; }
.logout { margin-top: auto; color: #815638; background: transparent; border: 1px solid #dfcfb8; cursor: pointer; }
.logout:hover { color: #fffaf0; background: #925b35; }

@media (max-width: 760px) {
  .sidebar { position: sticky; width: 100%; height: auto; padding: .75rem 1rem; flex-direction: row; align-items: center; gap: .6rem; border-right: 0; border-bottom: 1px solid #dfcfb8; }
  .logo strong { font-size: 1.25rem; }
  nav { display: flex; flex: 1; justify-content: center; gap: .15rem; }
  nav a { padding: .65rem; }
  nav a span, .logout span { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; }
  .logout { margin: 0; padding: .65rem; }
}
</style>
