<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'default' })

const auth = useAuthStore()
const nickname = ref('')
const country = ref('')
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
  country.value = auth.user?.country || ''
})

async function save() {
  saving.value = true
  saved.value = false
  const avatar = selectedAvatar.value
  const profileUpdated = await auth.updateProfile(nickname.value.trim(), country.value.trim())
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
    country.value = auth.user?.country || ''
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
    <NuxtLink class="back" to="/lobby">← Voltar para os desafios</NuxtLink>

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
        <label>País<input v-model="country" maxlength="56" autocomplete="country-name" placeholder="Ex.: Brasil"></label>
        <div class="rating"><span>Rating</span><strong>{{ auth.user?.rating }}</strong><small>Será atualizado automaticamente pelo sistema competitivo na Fase 2.4.</small></div>
        <button type="submit" :disabled="saving">{{ saving ? 'Salvando...' : 'Salvar alterações' }}</button>
        <p v-if="saved" class="success">Perfil atualizado com sucesso.</p>
        <p v-if="auth.error" class="error">{{ auth.error }}</p>
      </form>
    </section>
  </main>
</template>

<style scoped>
.settings-shell { min-height: 100vh; padding: clamp(1.2rem, 5vw, 4rem); color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e35 0.7px, transparent 0.7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }.back { color: #815638; text-decoration: none; }.back:hover { text-decoration: underline; }
.settings-card { width: min(620px, 100%); margin: 5vh auto 0; padding: clamp(1.5rem, 5vw, 3rem); background: #fffaf0e8; border: 1px solid #eadcc7; border-radius: 22px; box-shadow: 0 20px 45px #60401f1c; }.eyebrow { color: #925b35; font-size: 0.72rem; font-weight: 800; letter-spacing: 0.12em; }.settings-card h1 { margin: 0.4rem 0; font: 500 2.5rem Georgia, serif; }.settings-card > p { margin: 0 0 2rem; color: #857060; }
form, label { display: grid; gap: 0.6rem; }form { gap: 1.2rem; }label { color: #6e5847; font-size: 0.9rem; }input, button { padding: 0.9rem 1rem; color: inherit; background: white; border: 1px solid #dfd2c1; border-radius: 10px; font: inherit; }button { color: white; font-weight: 700; background: #925b35; border-color: #925b35; cursor: pointer; }button:disabled { opacity: 0.65; cursor: wait; }
.rating { display: grid; grid-template-columns: 1fr auto; gap: 0.35rem 1rem; padding: 1rem; background: #efe3cf; border-radius: 12px; }.rating strong { color: #925b35; }.rating small { grid-column: 1 / -1; color: #806d5d; }.success, .error { margin: 0; text-align: center; }.success { color: #56784a; }.error { color: #b33e2e; }
.avatar-editor { display: flex; align-items: center; gap: 1rem; padding: 1rem; background: #efe3cf; border-radius: 14px; }.avatar-editor img, .avatar-fallback { width: 76px; height: 76px; flex: 0 0 auto; border-radius: 50%; object-fit: cover; }.avatar-fallback { display: grid; place-items: center; color: white; background: #925b35; font: 700 1.7rem Georgia, serif; }.file-label { flex: 1; }.file-label input { width: 100%; padding: 0.6rem; }.file-label small { color: #806d5d; }
</style>
