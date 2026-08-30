<script setup lang="ts">
import { Sparkles } from 'lucide-vue-next'

defineProps<{ title: string; description: string }>()
</script>

<template>
  <section class="coming-soon">
    <span class="icon"><Sparkles :size="30" aria-hidden="true" /></span>
    <p>EM BREVE</p>
    <h1>{{ title }}</h1>
    <div class="rule"><span>♟</span></div>
    <p class="description">{{ description }}</p>
    <NuxtLink to="/lobby">Voltar aos desafios</NuxtLink>
  </section>
</template>

<style scoped>
.coming-soon { display: grid; width: min(620px, 100%); justify-items: center; padding: clamp(2.5rem, 8vw, 5rem) 2rem; text-align: center; background: #fffaf0e8; border: 1px solid #eadcc7; border-radius: 20px; box-shadow: 0 18px 40px #6f452814; }
.icon { display: grid; width: 62px; height: 62px; place-items: center; color: #6f4528; background: #efe2ce; border: 1px solid #dfcfb8; border-radius: 50%; }
p { margin: 1.2rem 0 .4rem; color: #6f4528; font-size: .72rem; font-weight: 800; letter-spacing: .18em; }
h1 { margin: 0; color: #3c2b20; font: 500 clamp(2.4rem, 7vw, 4.5rem)/1 Georgia, serif; }
.rule { display: flex; width: min(280px, 70%); align-items: center; gap: .8rem; margin: 1.4rem 0; color: #b27b55; }
.rule::before, .rule::after { content: ''; flex: 1; height: 1px; background: #dfcfb8; }
.description { max-width: 440px; margin: 0; color: #806d5d; font-size: 1rem; font-weight: 400; line-height: 1.65; letter-spacing: 0; }
a { margin-top: 2rem; padding: .8rem 1.1rem; color: white; font-weight: 700; text-decoration: none; background: #6f4528; border-radius: 10px; }
</style>
