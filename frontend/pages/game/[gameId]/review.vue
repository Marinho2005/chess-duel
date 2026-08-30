<script setup lang="ts">
import EvaluationBar from '~/components/review/EvaluationBar.vue'
import ReviewBoard from '~/components/review/ReviewBoard.vue'
import ReviewPanel from '~/components/review/ReviewPanel.vue'

definePageMeta({ middleware: 'auth', layout: false })

const route = useRoute()
// Nesta rota, gameId é Game.id: a chave primária UUID persistida, usada pelos endpoints de análise.
const gameId = computed(() => String(route.params.gameId))
const { review, loading, error, currentPly, replay, position, evaluation, start, stop, select } = useGameReview(gameId)

const statusLabel = computed(() => review.value?.status === 'processing'
  ? 'Stockfish está calculando as posições…'
  : 'Análise aguardando na fila…')

onMounted(start)
onBeforeUnmount(stop)
</script>

<template>
  <main class="review-shell">
    <header class="page-header">
      <div>
        <NuxtLink to="/profile/history">← Histórico</NuxtLink>
        <span>ANÁLISE PÓS-PARTIDA</span>
        <h1>Revisão da partida</h1>
      </div>
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
        @select="select"
      />
    </section>
  </main>
</template>

<style scoped>
.review-shell { min-height: 100vh; padding: clamp(1rem, 3vw, 2.5rem); color: #3c2b20; background-color: #f4eddf; background-image: radial-gradient(#bba98e35 .7px, transparent .7px); background-size: 5px 5px; font-family: Inter, system-ui, sans-serif; }
.page-header { width: min(1180px, 100%); margin: 0 auto 1.4rem; }.page-header a { display: block; margin-bottom: 1rem; color: #815638; text-decoration: none; }.page-header a:hover { text-decoration: underline; }.page-header span { color: #925b35; font-size: .7rem; font-weight: 800; letter-spacing: .13em; }.page-header h1 { margin: .25rem 0 0; font: 500 clamp(2rem, 5vw, 3.3rem) Georgia, serif; }
.workspace { display: grid; width: min(1180px, 100%); margin: auto; grid-template-columns: minmax(0, 720px) minmax(330px, 420px); align-items: start; justify-content: center; gap: 1.25rem; }
.board-area { display: flex; flex-direction: row; align-items: stretch; gap: .55rem; width: 100%; min-width: 0; }
.evaluation-rail { display: flex; flex-direction: column; width: 32px; min-width: 32px; flex-shrink: 0; align-self: stretch; }
.board-area > :deep(.review-board) { flex: 1; min-width: 0; }
.state { width: min(700px, 100%); margin: 4rem auto; padding: 3rem; text-align: center; background: #fffaf0e8; border: 1px solid #eadcc7; border-radius: 16px; box-shadow: 0 8px 24px #60401f12; }.state h2 { font-family: Georgia, serif; }.state p, .state small { color: #806d5d; }.state i { display: block; width: 30px; height: 30px; margin: auto; border: 3px solid #dfcbb3; border-top-color: #925b35; border-radius: 50%; animation: spin 1s linear infinite; }.state button { padding: .7rem 1rem; color: white; background: #925b35; border: 0; border-radius: 8px; cursor: pointer; }.error { color: #a53e2e; }
@keyframes spin { to { transform: rotate(360deg); } }
@media (max-width: 920px) { .workspace { grid-template-columns: minmax(0, 720px); }.board-area { max-width: 720px; } }
@media (max-width: 480px) { .review-shell { padding: .75rem; }.board-area { gap: .35rem; }.evaluation-rail { width: 24px; min-width: 24px; }.state { padding: 2rem 1rem; } }
</style>
