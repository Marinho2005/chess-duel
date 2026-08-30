<script setup lang="ts">
import { Bot, LogOut, Puzzle, Swords, Trophy, UserRoundCog } from 'lucide-vue-next'

type NavigationKey = 'challenges' | 'ranking' | 'puzzles' | 'bots' | 'profile'

defineProps<{ active: NavigationKey }>()
defineEmits<{ logout: [] }>()

const items = [
  { key: 'challenges', label: 'Desafios', to: '/lobby', icon: Swords },
  { key: 'ranking', label: 'Ranking', to: '/ranking', icon: Trophy },
  { key: 'puzzles', label: 'Puzzles', to: '/puzzles', icon: Puzzle },
  { key: 'bots', label: 'Bots', to: '/bots', icon: Bot },
  { key: 'profile', label: 'Editar perfil', to: '/settings/profile', icon: UserRoundCog }
] as const
</script>

<template>
  <aside class="sidebar">
    <NuxtLink class="logo" to="/lobby"><span aria-hidden="true">♟</span> <strong>ChessDuel</strong></NuxtLink>
    <nav aria-label="Navegação principal">
      <NuxtLink
        v-for="item in items"
        :key="item.key"
        :to="item.to"
        :class="{ active: active === item.key }"
        :aria-current="active === item.key ? 'page' : undefined"
      >
        <component :is="item.icon" :size="19" :stroke-width="1.8" aria-hidden="true" />
        <span>{{ item.label }}</span>
      </NuxtLink>
    </nav>
    <button class="logout" type="button" @click="$emit('logout')">
      <LogOut :size="18" aria-hidden="true" />
      <span>Sair</span>
    </button>
  </aside>
</template>

<style scoped>
.sidebar { position: sticky; top: 0; display: flex; height: 100vh; flex-direction: column; gap: 2rem; padding: 2rem 1.4rem; background: #fffaf0dd; border-right: 1px solid #dfcfb8; }
.logo { color: #925b35; font-size: 1.5rem; text-decoration: none; white-space: nowrap; }
.logo strong { font: 700 1.7rem Georgia, serif; }
nav { display: grid; gap: 0.5rem; }
nav a { display: flex; align-items: center; gap: .75rem; padding: 0.85rem 1rem; color: #806d5d; text-decoration: none; border: 1px solid transparent; border-radius: 10px; }
nav a:hover { color: #3c2b20; background: #f5ead9; }
nav a.active { color: #3c2b20; background: #efe2ce; border-color: #dfcfb8; }
.logout { display: flex; align-items: center; justify-content: center; gap: .55rem; margin-top: auto; padding: 0.7rem 1rem; color: #3c2b20; background: #f7eedf; border: 1px solid #dfcfb8; border-radius: 9px; cursor: pointer; }
@media (max-width: 760px) {
  .sidebar { position: static; width: auto; height: auto; gap: .85rem; padding: 1rem; border-right: 0; border-bottom: 1px solid #dfcfb8; }
  .logo { text-align: center; }
  nav { display: flex; overflow-x: auto; padding-bottom: .2rem; }
  nav a { flex: 0 0 auto; padding: .65rem .8rem; }
  .logout { display: none; }
}
</style>
