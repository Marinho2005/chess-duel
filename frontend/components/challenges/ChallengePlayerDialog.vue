<script setup lang="ts">
import { Link2, LoaderCircle, Search, Swords, X } from 'lucide-vue-next'

type Player = { id: string; nickname: string; avatar_url: string | null; status: 'online' | 'offline' | 'away' | 'dnd' | 'invisible'; rating: number; ratings: { bullet: number; blitz: number; rapid: number } }

const props = defineProps<{
  open: boolean
  timeControlLabel: string
  challengeReady: boolean
  challengeBusy: boolean
  challengeError: string
  creatingLink: boolean
  inviteLink: string
  copyMessage?: string
}>()
const emit = defineEmits<{
  close: []
  challenge: [player: Player]
  createLink: []
  copyLink: []
}>()

const auth = useAuthStore()
const config = useRuntimeConfig()
const query = ref('')
const results = ref<Player[]>([])
const searching = ref(false)
const searched = ref(false)
let searchTimer: ReturnType<typeof setTimeout> | undefined
let searchVersion = 0

watch(() => props.open, (open) => {
  if (!open) {
    clearTimeout(searchTimer)
    ++searchVersion
    query.value = ''
    results.value = []
    searched.value = false
    searching.value = false
  }
})

watch(query, (value) => {
  clearTimeout(searchTimer)
  const version = ++searchVersion
  results.value = []
  searched.value = false
  searching.value = false
  const term = value.trim()
  if (term.length < 2) return
  searchTimer = setTimeout(() => { void searchPlayers(term, version) }, 350)
})

async function searchPlayers(term: string, version: number) {
  searching.value = true
  try {
    const data = await $fetch<{ users: Player[] }>('/api/users/search', {
      baseURL: config.public.api.baseURL,
      headers: { Authorization: `Bearer ${auth.token}` },
      query: { q: term },
    })
    if (version === searchVersion) {
      results.value = data.users
      searched.value = true
    }
  } catch {
    if (version === searchVersion) {
      results.value = []
      searched.value = true
    }
  } finally {
    if (version === searchVersion) searching.value = false
  }
}

onBeforeUnmount(() => { clearTimeout(searchTimer); ++searchVersion })
</script>

<template>
  <div v-if="open" class="overlay" @click.self="emit('close')">
    <section class="dialog" role="dialog" aria-modal="true" aria-labelledby="challenge-dialog-title" @keydown.esc="emit('close')">
      <header><div><span>DESAFIO DIRETO</span><h2 id="challenge-dialog-title">Desafie alguém</h2><p>Formato escolhido: <strong>{{ timeControlLabel }}</strong></p></div><button type="button" aria-label="Fechar" :disabled="challengeBusy || creatingLink" @click="emit('close')"><X :size="20" /></button></header>
      <section class="nickname-section" aria-labelledby="nickname-title">
        <h3 id="nickname-title"><Swords :size="17" /> Buscar pelo apelido</h3>
        <div class="search-field" :aria-busy="searching"><Search :size="18" aria-hidden="true" /><input v-model="query" type="search" minlength="2" maxlength="32" placeholder="Digite o apelido" aria-label="Apelido do jogador" autocomplete="off" autofocus><LoaderCircle v-if="searching" class="spinner" :size="18" aria-label="Buscando jogadores" /></div>
        <p v-if="query.trim().length < 2" class="hint">Digite pelo menos 2 caracteres.</p>
        <p v-else-if="searched && !results.length" class="hint">Nenhum jogador encontrado.</p>
        <ul v-if="results.length" class="results">
          <li v-for="player in results" :key="player.id"><NuxtLink :to="`/user/${encodeURIComponent(player.nickname)}`"><ProfilePresenceAvatar :name="player.nickname" :avatar-url="player.avatar_url" :status="player.status" :size="38" /><strong>{{ player.nickname }}</strong></NuxtLink><button type="button" :disabled="!challengeReady || challengeBusy" @click="emit('challenge', player)">{{ challengeBusy ? 'Enviando…' : 'Desafiar' }}</button></li>
        </ul>
        <p v-if="challengeError" class="error" role="alert">{{ challengeError }}</p>
      </section>
      <div class="divider"><span>ou</span></div>
      <section class="link-section" aria-labelledby="link-title"><div><Link2 :size="19" /><span><h3 id="link-title">Convite por link</h3><p>Crie uma sala privada para compartilhar.</p></span></div><button v-if="!inviteLink" type="button" :disabled="creatingLink" @click="emit('createLink')">{{ creatingLink ? 'Criando…' : 'Gerar link' }}</button><div v-else class="link-row"><input :value="inviteLink" readonly aria-label="Link da sala privada" @focus="($event.target as HTMLInputElement).select()"><button type="button" @click="emit('copyLink')">{{ copyMessage || 'Copiar' }}</button></div></section>
    </section>
  </div>
</template>

<style scoped>
.overlay{position:fixed;z-index:110;inset:0;display:grid;place-items:center;padding:1rem;background:rgb(0 0 0/62%)}.dialog{width:min(590px,100%);max-height:calc(100vh - 2rem);overflow:auto;padding:1.35rem;color:var(--text);background:var(--surface);border:1px solid var(--border);border-radius:16px;box-shadow:var(--shadow)}.dialog>header{display:flex;align-items:flex-start;justify-content:space-between;gap:1rem}.dialog>header>div>span{color:var(--accent);font-size:.72rem;font-weight:850;letter-spacing:.11em}.dialog h2{margin:.25rem 0}.dialog header p,.hint,.link-section p{margin:.2rem 0;color:var(--text-muted);font-size:.82rem}.dialog button{display:inline-flex;min-height:40px;align-items:center;justify-content:center;padding:.58rem .8rem;color:var(--text);background:var(--surface-strong);border:1px solid var(--border);border-radius:8px;font-weight:700;cursor:pointer}.dialog button:hover:not(:disabled){border-color:var(--accent);background:var(--surface-hover)}.dialog button:disabled{opacity:.55;cursor:default}.dialog>header>button{padding:.4rem}.nickname-section{margin-top:1.25rem}.nickname-section h3,.link-section h3{display:flex;align-items:center;gap:.45rem;margin:0 0 .65rem;font-size:.95rem}.nickname-section h3 svg,.link-section svg{color:var(--accent)}.search-field{display:flex;align-items:center;gap:.65rem;padding:0 .8rem;color:var(--text-muted);background:var(--bg);border:1px solid var(--border);border-radius:9px}.search-field:focus-within{border-color:var(--accent);box-shadow:0 0 0 2px color-mix(in srgb,var(--accent) 20%,transparent)}.search-field input{min-width:0;flex:1;padding:.78rem 0;color:var(--text);background:transparent;border:0;outline:0}.spinner{color:var(--accent);animation:spin .8s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}.results{max-height:210px;padding:0;margin:.7rem 0 0;overflow:auto;list-style:none}.results li{display:flex;align-items:center;justify-content:space-between;gap:.7rem;padding:.65rem 0;border-top:1px solid var(--border-subtle)}.results a{display:flex;align-items:center;gap:.7rem;min-width:0;color:var(--text);text-decoration:none}.results a:hover strong{color:var(--accent)}.results li>button{color:var(--accent-ink);background:var(--accent);border-color:var(--accent)}.error{padding:.7rem;margin:.7rem 0 0;color:var(--danger);background:var(--danger-soft);border-radius:8px;font-size:.8rem}.divider{display:flex;align-items:center;gap:.7rem;margin:1rem 0;color:var(--text-muted);font-size:.72rem}.divider::before,.divider::after{height:1px;flex:1;content:'';background:var(--border-subtle)}.link-section{display:grid;grid-template-columns:1fr auto;align-items:center;gap:1rem;padding:.9rem;background:var(--surface-strong);border:1px solid var(--border);border-radius:11px}.link-section>div:first-child{display:flex;align-items:center;gap:.65rem}.link-section h3{margin:0}.link-row{display:grid!important;min-width:0;grid-column:1/-1;grid-template-columns:minmax(0,1fr) auto;gap:.5rem}.link-row input{min-width:0;padding:.68rem;color:var(--text);background:var(--surface);border:1px solid var(--border);border-radius:8px}@media(max-width:520px){.link-section{grid-template-columns:1fr}.link-section>button{width:100%}.results li{align-items:flex-start}.results li>button{min-height:36px;padding:.45rem .6rem}}
</style>
