<script setup lang="ts">
import { countries, countryName } from '~/utils/countries'
import { AVATAR_OUTPUT_SIZE, normalizeAvatarImage } from '~/utils/avatarImage'

definePageMeta({ middleware: 'auth', layout: 'default' })

const auth = useAuthStore()
const nickname = ref('')
const countryCode = ref('')
const birthDate = ref('')
const saving = ref(false)
const saved = ref(false)
const selectedAvatar = ref<File | null>(null)
const previewUrl = ref<string | null>(null)
const processingAvatar = ref(false)
const avatarError = ref('')
const config = useRuntimeConfig()
const countryPicker = ref<HTMLElement | null>(null)
const countryOpen = ref(false)
const countrySearch = ref('')

const selectedCountry = computed(() => countries.find(item => item.code === countryCode.value) || null)
const filteredCountries = computed(() => {
  const search = countrySearch.value.trim().toLocaleLowerCase('pt-BR')
  if (!search) return countries
  return countries.filter(item => item.name.toLocaleLowerCase('pt-BR').includes(search) || item.code.toLowerCase().includes(search))
})

const currentAvatarUrl = computed(() => {
  if (previewUrl.value) return previewUrl.value
  return resolveAvatarUrl(auth.user?.avatar_url, config.public.api.baseURL)
})

onMounted(() => {
  nickname.value = auth.user?.nickname || ''
  countryCode.value = auth.user?.country_code || ''
  birthDate.value = auth.user?.birth_date || ''
  document.addEventListener('pointerdown', closeCountryPicker)
})

async function save() {
  saving.value = true
  saved.value = false
  const avatar = selectedAvatar.value
  const profileUpdated = await auth.updateProfile(nickname.value.trim(), countryCode.value, countryName(countryCode.value), birthDate.value)
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
    birthDate.value = auth.user?.birth_date || ''
  }
}

async function selectAvatar(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0] || null
  selectedAvatar.value = null
  clearPreview()
  avatarError.value = ''

  if (!file) return

  processingAvatar.value = true

  try {
    const normalizedAvatar = await normalizeAvatarImage(file)
    selectedAvatar.value = normalizedAvatar
    previewUrl.value = URL.createObjectURL(normalizedAvatar)
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'avatar_processing_failed'
    const messages: Record<string, string> = {
      avatar_too_large: 'A imagem original deve ter no máximo 2 MB.',
      invalid_avatar_format: 'Escolha uma imagem JPEG, PNG ou WebP válida.',
      avatar_processing_failed: 'Não foi possível preparar essa imagem.',
    }
    avatarError.value = messages[reason] || messages.avatar_processing_failed!
    input.value = ''
  } finally {
    processingAvatar.value = false
  }
}

function clearPreview() {
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value)
  previewUrl.value = null
}

function selectCountry(code: string) {
  countryCode.value = code
  countryOpen.value = false
  countrySearch.value = ''
}

function closeCountryPicker(event: PointerEvent) {
  if (!countryPicker.value?.contains(event.target as Node)) countryOpen.value = false
}

onBeforeUnmount(() => {
  clearPreview()
  document.removeEventListener('pointerdown', closeCountryPicker)
})
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
          <label class="file-label">Foto de perfil<input type="file" accept="image/jpeg,image/png,image/webp" :disabled="processingAvatar" @change="selectAvatar"><small>JPEG, PNG ou WebP · máximo de 2 MB · salva em {{ AVATAR_OUTPUT_SIZE }}×{{ AVATAR_OUTPUT_SIZE }}</small></label>
        </div>
        <p v-if="processingAvatar" class="avatar-message">Preparando e recortando a imagem…</p>
        <p v-if="avatarError" class="error">{{ avatarError }}</p>
        <label>Apelido<input v-model="nickname" required minlength="3" maxlength="32" autocomplete="nickname"></label>
        <label>Data de nascimento <small>Dado privado, visível apenas para você.</small><input v-model="birthDate" type="date" :max="new Date().toISOString().slice(0,10)" autocomplete="bday"></label>
        <div class="form-field">
          <span class="field-label">País</span>
          <div ref="countryPicker" class="country-picker" @keydown.esc="countryOpen = false">
            <button
              type="button"
              class="country-trigger"
              :aria-expanded="countryOpen"
              aria-haspopup="listbox"
              @click="countryOpen = !countryOpen"
            >
              <span v-if="selectedCountry" class="country-value"><ProfileCountryFlag :code="selectedCountry.code" />{{ selectedCountry.name }}</span>
              <span v-else>Prefiro não informar</span>
              <span aria-hidden="true">⌄</span>
            </button>
            <div v-if="countryOpen" class="country-menu">
              <input v-model="countrySearch" type="search" placeholder="Buscar país" autocomplete="off" aria-label="Buscar país">
              <div class="country-options" role="listbox" aria-label="País">
                <button type="button" role="option" :aria-selected="countryCode === ''" @click="selectCountry('')">Prefiro não informar</button>
                <button
                  v-for="item in filteredCountries"
                  :key="item.code"
                  type="button"
                  role="option"
                  :aria-selected="countryCode === item.code"
                  @click="selectCountry(item.code)"
                >
                  <ProfileCountryFlag :code="item.code" />
                  <span>{{ item.name }}</span>
                </button>
              </div>
            </div>
          </div>
        </div>
        <div class="rating"><span>Rating</span><strong>{{ auth.user?.rating }}</strong><small>Será atualizado automaticamente pelo sistema competitivo na Fase 2.4.</small></div>
        <button type="submit" :disabled="saving || processingAvatar">{{ saving ? 'Salvando...' : 'Salvar alterações' }}</button>
        <p v-if="saved" class="success">Perfil atualizado com sucesso.</p>
        <p v-if="auth.error" class="error">{{ auth.error }}</p>
      </form>
    </section>
  </main>
</template>

<style scoped>
.settings-shell{min-height:100vh;padding:clamp(1.2rem,5vw,4rem);color:var(--text);background:var(--bg)}.back{color:var(--accent);text-decoration:none}.back:hover{text-decoration:underline}.settings-card{width:min(720px,100%);margin:1.5rem auto 0;padding:clamp(1.5rem,5vw,3rem);background:var(--surface);border:1px solid var(--border);border-radius:18px;box-shadow:var(--shadow)}.appearance-card{margin-top:5vh}.eyebrow{color:var(--accent);font-size:.72rem;font-weight:800;letter-spacing:.12em}.settings-card h1{margin:.4rem 0;font-size:2rem;letter-spacing:-.03em}.settings-card>p{margin:0 0 2rem;color:var(--text-muted)}form,label,.form-field{display:grid;gap:.6rem}form{gap:1.2rem}label,.field-label{color:var(--text-muted);font-size:.9rem}input,select,button{padding:.9rem 1rem;color:var(--text);background:var(--surface-strong);border:1px solid var(--border);border-radius:10px;font:inherit}button{color:var(--accent-ink);font-weight:700;background:var(--accent);border-color:var(--accent);cursor:pointer}button:disabled{opacity:.65;cursor:wait}.rating{display:grid;grid-template-columns:1fr auto;gap:.35rem 1rem;padding:1rem;background:var(--surface-strong);border-radius:12px}.rating strong{color:var(--accent)}.rating small{grid-column:1/-1;color:var(--text-muted)}.success,.error{margin:0;text-align:center}.success{color:var(--success)}.error{color:var(--danger)}.avatar-message{margin:0;color:var(--text-muted);font-size:.8rem;text-align:center}.avatar-editor{display:flex;align-items:center;gap:1rem;padding:1rem;background:var(--surface-strong);border-radius:14px}.avatar-editor img,.avatar-fallback{width:76px;height:76px;flex:0 0 auto;border-radius:50%;object-fit:cover}.avatar-fallback{display:grid;place-items:center;color:var(--accent-ink);background:var(--accent);font:700 1.7rem var(--font-serif)}.file-label{flex:1}.file-label input{width:100%;padding:.6rem}.file-label small{color:var(--text-muted)}
.country-picker{position:relative}.country-trigger{display:flex;width:100%;align-items:center;justify-content:space-between;color:var(--text);background:var(--surface-strong);border-color:var(--border);font-weight:500;text-align:left}.country-value{display:flex;align-items:center;gap:.7rem}.country-menu{position:absolute;z-index:20;top:calc(100% + .4rem);right:0;left:0;padding:.55rem;background:var(--surface);border:1px solid var(--border);border-radius:12px;box-shadow:var(--shadow)}.country-menu>input{width:100%;margin-bottom:.45rem}.country-options{display:grid;max-height:310px;overflow:auto;overscroll-behavior:contain}.country-options button{display:flex;align-items:center;gap:.65rem;padding:.65rem .75rem;color:var(--text);background:transparent;border:0;border-radius:8px;font-weight:500;text-align:left}.country-options button:hover,.country-options button[aria-selected="true"]{color:var(--text);background:var(--surface-hover)}
.country-picker :deep(.flag){width:1.2em;height:1.2em}
</style>
