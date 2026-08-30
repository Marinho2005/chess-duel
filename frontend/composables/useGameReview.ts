import { Chess } from 'chess.js'
import type { Color, Key } from '@lichess-org/chessground/types'
import type { AnalyzedMove, Evaluation, ReviewResponse } from '~/types/game-review'

export function useGameReview(gameId: Ref<string>) {
  const auth = useAuthStore()
  const config = useRuntimeConfig()
  const review = ref<ReviewResponse | null>(null)
  const loading = ref(true)
  const error = ref('')
  const currentPly = ref(0)
  let pollTimer: ReturnType<typeof setTimeout> | null = null

  const replay = computed(() => {
    const chess = new Chess()
    const positions: Array<{ fen: string; turn: Color; lastMove: [Key, Key] | null }> = [
      { fen: chess.fen(), turn: 'white', lastMove: null }
    ]
    const moves: Array<AnalyzedMove & { san: string }> = []

    for (const [index, raw] of (review.value?.game.moves || []).entries()) {
      const made = chess.move({ from: raw.from, to: raw.to, promotion: raw.promotion || undefined })
      if (!made) continue
      const analysis = review.value?.results?.moves.find(item => item.ply === index + 1)
      moves.push({
        ply: index + 1, move_number: Math.floor(index / 2) + 1,
        color: index % 2 === 0 ? 'white' : 'black', played_move: `${raw.from}${raw.to}${raw.promotion || ''}`,
        best_move: '', evaluation_before: { type: 'cp', value: 0 }, evaluation: { type: 'cp', value: 0 },
        principal_variation: [], centipawn_loss: 0, classification: 'good', ...analysis, san: made.san
      })
      positions.push({ fen: chess.fen(), turn: chess.turn() === 'w' ? 'white' : 'black', lastMove: [raw.from as Key, raw.to as Key] })
    }
    return { positions, moves }
  })

  const position = computed(() => replay.value.positions[currentPly.value] || replay.value.positions[0])
  const evaluation = computed<Evaluation>(() => {
    if (currentPly.value === 0) return review.value?.results?.initial_evaluation || { type: 'cp', value: 0 }
    return replay.value.moves[currentPly.value - 1]?.evaluation || { type: 'cp', value: 0 }
  })

  async function start() {
    auth.restoreSession()
    if (!auth.token) return
    loading.value = true
    try {
      review.value = await request('POST')
      schedulePoll()
    } catch (requestError: any) {
      error.value = requestError?.data?.error || 'Não foi possível abrir a análise desta partida.'
    } finally { loading.value = false }
  }

  async function poll() {
    try { review.value = await request('GET'); schedulePoll() }
    catch { error.value = 'A atualização da análise foi interrompida.' }
  }

  function request(method: 'GET' | 'POST') {
    return $fetch<ReviewResponse>(`/api/games/${gameId.value}/${method === 'POST' ? 'analyze' : 'analysis'}`, {
      baseURL: config.public.api.baseURL, method, headers: { Authorization: `Bearer ${auth.token}` }
    })
  }

  function schedulePoll() {
    if (review.value && ['pending', 'processing'].includes(review.value.status)) pollTimer = setTimeout(poll, 2000)
  }
  function select(ply: number) { currentPly.value = Math.min(Math.max(ply, 0), replay.value.moves.length) }
  function stop() { if (pollTimer) clearTimeout(pollTimer) }

  return { review, loading, error, currentPly, replay, position, evaluation, start, stop, select }
}
