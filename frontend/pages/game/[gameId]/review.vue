<script setup lang="ts">
import EvaluationBar from '~/components/review/EvaluationBar.vue'
import ReviewBoard from '~/components/review/ReviewBoard.vue'
import ReviewPanel from '~/components/review/ReviewPanel.vue'
import { soundForSan } from '~/utils/gameSound'

definePageMeta({ middleware: 'auth', layout: false })

const route = useRoute()
// Nesta rota, gameId é Game.id: a chave primária UUID persistida, usada pelos endpoints de análise.
const gameId = computed(() => String(route.params.gameId))
const { review, loading, error, currentPly, replay, position, evaluation, start, stop, select } = useGameReview(gameId)
const sounds = useGameSounds()

const statusLabel = computed(() => review.value?.status === 'processing'
  ? 'Stockfish está calculando as posições…'
  : 'Análise aguardando na fila…')

onMounted(() => {
  start()
  window.addEventListener('keydown', handleReviewKeydown)
})
onBeforeUnmount(() => {
  stop()
  window.removeEventListener('keydown', handleReviewKeydown)
})

function selectWithSound(ply: number) {
  if (ply === currentPly.value) return
  const target = Math.min(Math.max(ply, 0), replay.value.moves.length)
  select(target)
  if (target > 0) sounds.play(soundForSan(replay.value.moves[target - 1]?.san))
}

function handleReviewKeydown(event: KeyboardEvent) {
  const target = event.target as HTMLElement | null
  if (target?.matches('input, textarea, select, [contenteditable="true"]')) return
  if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return
  event.preventDefault()
  selectWithSound(currentPly.value + (event.key === 'ArrowRight' ? 1 : -1))
}
</script>

<template>
  <main class="review-shell" @pointerdown.once="sounds.unlock">
    <header class="page-header">
      <div>
        <NuxtLink to="/profile/history">← Histórico</NuxtLink>
        <span>ANÁLISE PÓS-PARTIDA</span>
        <h1>Revisão da partida</h1>
      </div>
      <button type="button" class="sound-toggle" :aria-pressed="sounds.enabled.value" :title="sounds.enabled.value ? 'Desativar sons' : 'Ativar sons'" @click="sounds.toggle">
        {{ sounds.enabled.value ? '🔊' : '🔇' }} <span>{{ sounds.enabled.value ? 'Sons ligados' : 'Sons desligados' }}</span>
      </button>
    </header>

    <section v-if="loading" class="state">Preparando o tabuleiro…</section>
    <section v-else-if="error" class="state error">{{ error }}</section>

    <section v-else-if="review && ['pending', 'processing'].includes(review.status)" class="state">
      <i />
      <h2>Análise em andamento</h2>
      <p>{{ statusLabel }}</p>
      <small>Você pode deixar esta página aberta; ela será atualizada automaticamente.</small>
    </section>

    <section v-else-if="review?.status === 'failed'" class="state error">
      <h2>Não foi possível concluir</h2>
      <p>{{ review.error }}</p>
      <button type="button" @click="start">Tentar novamente</button>
    </section>

    <section v-else-if="review?.results" class="workspace">
      <div class="board-area">
        <div class="evaluation-rail">
          <EvaluationBar
            :evaluation="evaluation"
            :orientation="review.game.viewer_color"
          />
        </div>
        <ReviewBoard
          :fen="position.fen"
          :orientation="review.game.viewer_color"
          :turn-color="position.turn"
          :last-move="position.lastMove"
        />
      </div>

      <ReviewPanel
        :evaluation="evaluation"
        :depth="review.results.depth"
        :moves="replay.moves"
        :current-ply="currentPly"
        :white-player="review.game.white_player"
        :black-player="review.game.black_player"
        @select="selectWithSound"
      />
    </section>
  </main>
</template>

<style scoped>
.review-shell { min-height: 100vh; padding: .65rem clamp(1rem, 3vw, 2.5rem) 1.5rem; color: var(--text); background-color: var(--bg); background-image: radial-gradient(var(--pattern-dot) .7px, transparent .7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
.page-header { display: flex; width: min(990px, 100%); min-height: 76px; margin: 0 auto .7rem; align-items: center; justify-content: space-between; gap: 1rem; }.page-header a { display: block; margin-bottom: .3rem; color: var(--accent); font-size: .82rem; text-decoration: none; }.page-header a:hover { text-decoration: underline; }.page-header div > span { color: var(--accent); font-size: .62rem; font-weight: 800; letter-spacing: .13em; }.page-header h1 { margin: .12rem 0 0; color: var(--text); font: 500 clamp(1.75rem, 3.2vw, 2.35rem) Georgia, serif; }.sound-toggle { display: inline-flex; align-items: center; gap: .3rem; padding: .38rem .55rem; color: var(--text); background: var(--surface); border: 1px solid var(--border); border-radius: 8px; font: 700 .7rem Inter,sans-serif; cursor: pointer; }.sound-toggle:hover { background: var(--surface-hover); }
.workspace { display: grid; width: min(990px, 100%); margin: auto; grid-template-columns: minmax(0, 550px) minmax(330px, 420px); align-items: start; justify-content: center; gap: 1rem; }
.board-area { display: flex; flex-direction: row; align-items: stretch; gap: .55rem; width: 100%; min-width: 0; }
.evaluation-rail { display: flex; flex-direction: column; width: 32px; min-width: 32px; flex-shrink: 0; align-self: stretch; }
.board-area > :deep(.review-board) { flex: 1; min-width: 0; }
.workspace > :deep(.analysis-panel) { height: min(510px, calc(100dvh - 120px)); }
.state { width: min(700px, 100%); margin: 4rem auto; padding: 3rem; color: var(--text); text-align: center; background: color-mix(in srgb, var(--surface) 96%, transparent); border: 1px solid var(--border); border-radius: 16px; box-shadow: var(--shadow); }.state h2 { color: var(--text); font-family: Georgia, serif; }.state p, .state small { color: var(--text-muted); }.state i { display: block; width: 30px; height: 30px; margin: auto; border: 3px solid var(--border); border-top-color: var(--accent); border-radius: 50%; animation: spin 1s linear infinite; }.state button { padding: .7rem 1rem; color: var(--accent-ink); background: var(--accent); border: 0; border-radius: 8px; cursor: pointer; }.state button:hover { background: var(--accent-hover); }.error { color: var(--danger); }
@keyframes spin { to { transform: rotate(360deg); } }
@media (max-width: 920px) { .workspace { grid-template-columns: minmax(0, 550px); }.board-area { max-width: 550px; }.workspace > :deep(.analysis-panel) { height: auto; } }
@media (max-width: 480px) { .review-shell { padding: .75rem; }.page-header { align-items: center; }.sound-toggle span { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0,0,0,0); }.board-area { gap: .35rem; }.evaluation-rail { width: 24px; min-width: 24px; }.state { padding: 2rem 1rem; } }
</style>
