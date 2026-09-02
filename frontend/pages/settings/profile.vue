<script setup lang="ts">
import { countries, countryFlag, countryName } from '~/utils/countries'

definePageMeta({ middleware: 'auth', layout: 'default' })

const auth = useAuthStore()
const nickname = ref('')
const countryCode = ref('')
const saving = ref(false)
const saved = ref(false)
const selectedAvatar = ref<File | null>(null)
const previewUrl = ref<string | null>(null)
const config = useRuntimeConfig()

const currentAvatarUrl = computed(() => {
  if (previewUrl.value) return previewUrl.value
  return resolveAvatarUrl(auth.user?.avatar_url, config.public.api.baseURL)
})

onMounted(() => {
  nickname.value = auth.user?.nickname || ''
  countryCode.value = auth.user?.country_code || ''
})

async function save() {
  saving.value = true
  saved.value = false
  const avatar = selectedAvatar.value
  const profileUpdated = await auth.updateProfile(nickname.value.trim(), countryCode.value, countryName(countryCode.value))
  const avatarUpdated = !avatar || (profileUpdated && await auth.updateAvatar(avatar))
  saving.value = false

  if (!auth.token) {
    await navigateTo('/?session=expired')
    return
  }

  if (profileUpdated && avatarUpdated) {
    saved.value = true
    selectedAvatar.value = null
    clearPreview()
    nickname.value = auth.user?.nickname || ''
    countryCode.value = auth.user?.country_code || ''
  }
}

function selectAvatar(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0] || null
  selectedAvatar.value = file
  clearPreview()

  if (file) previewUrl.value = URL.createObjectURL(file)
}

function clearPreview() {
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value)
  previewUrl.value = null
}

onBeforeUnmount(clearPreview)
</script>

<template>
  <main class="settings-shell">
    <NuxtLink class="back" to="/lobby">← Voltar para Jogar</NuxtLink>

    <section class="settings-card appearance-card">
      <span class="eyebrow">APARÊNCIA</span><h1>Aparência</h1>
      <p>Escolha como o ChessDuel aparece neste navegador.</p>
      <SettingsThemeSwitcher />
    </section>

    <section class="settings-card">
      <span class="eyebrow">MINHA CONTA</span>
      <h1>Editar perfil</h1>
      <p>Essas informações aparecem para seus oponentes.</p>

      <form @submit.prevent="save">
        <div class="avatar-editor">
          <img v-if="currentAvatarUrl" :src="currentAvatarUrl" alt="Prévia da foto de perfil">
          <span v-else class="avatar-fallback">{{ nickname.charAt(0).toUpperCase() || '♟' }}</span>
          <label class="file-label">Foto de perfil<input type="file" accept="image/jpeg,image/png,image/webp" @change="selectAvatar"><small>JPEG, PNG ou WebP · máximo de 2 MB</small></label>
        </div>
        <label>Apelido<input v-model="nickname" required minlength="3" maxlength="32" autocomplete="nickname"></label>
        <label>País<select v-model="countryCode" autocomplete="country-name"><option value="">Prefiro não informar</option><option v-for="item in countries" :key="item.code" :value="item.code">{{ countryFlag(item.code) }} {{ item.name }}</option></select></label>
        <div class="rating"><span>Rating</span><strong>{{ auth.user?.rating }}</strong><small>Será atualizado automaticamente pelo sistema competitivo na Fase 2.4.</small></div>
        <button type="submit" :disabled="saving">{{ saving ? 'Salvando...' : 'Salvar alterações' }}</button>
        <p v-if="saved" class="success">Perfil atualizado com sucesso.</p>
        <p v-if="auth.error" class="error">{{ auth.error }}</p>
      </form>
    </section>
  </main>
</template>

<style scoped>
.settings-shell{min-height:100vh;padding:clamp(1.2rem,5vw,4rem);color:var(--text);background:var(--bg)}.back{color:var(--accent);text-decoration:none}.back:hover{text-decoration:underline}.settings-card{width:min(720px,100%);margin:1.5rem auto 0;padding:clamp(1.5rem,5vw,3rem);background:var(--surface);border:1px solid var(--border);border-radius:18px;box-shadow:var(--shadow)}.appearance-card{margin-top:5vh}.eyebrow{color:var(--accent);font-size:.72rem;font-weight:800;letter-spacing:.12em}.settings-card h1{margin:.4rem 0;font-size:2rem;letter-spacing:-.03em}.settings-card>p{margin:0 0 2rem;color:var(--text-muted)}form,label{display:grid;gap:.6rem}form{gap:1.2rem}label{color:var(--text-muted);font-size:.9rem}input,select,button{padding:.9rem 1rem;color:var(--text);background:var(--surface-strong);border:1px solid var(--border);border-radius:10px;font:inherit}button{color:var(--accent-ink);font-weight:700;background:var(--accent);border-color:var(--accent);cursor:pointer}button:disabled{opacity:.65;cursor:wait}.rating{display:grid;grid-template-columns:1fr auto;gap:.35rem 1rem;padding:1rem;background:var(--surface-strong);border-radius:12px}.rating strong{color:var(--accent)}.rating small{grid-column:1/-1;color:var(--text-muted)}.success,.error{margin:0;text-align:center}.success{color:var(--success)}.error{color:var(--danger)}.avatar-editor{display:flex;align-items:center;gap:1rem;padding:1rem;background:var(--surface-strong);border-radius:14px}.avatar-editor img,.avatar-fallback{width:76px;height:76px;flex:0 0 auto;border-radius:50%;object-fit:cover}.avatar-fallback{display:grid;place-items:center;color:var(--accent-ink);background:var(--accent);font:700 1.7rem Georgia,serif}.file-label{flex:1}.file-label input{width:100%;padding:.6rem}.file-label small{color:var(--text-muted)}
</style>
