<script setup lang="ts">
import { Socket, type Channel } from 'phoenix'

type Move = {
  from: string
  to: string
  player: string
}

type GameState = {
  moves: Move[]
  current_turn: string
  fen: string
  white_time_remaining_ms: number
  black_time_remaining_ms: number
}

type MoveMade = Move & {
  new_fen: string
  current_turn: string
  is_check: boolean
  is_checkmate: boolean
  is_stalemate: boolean
  is_draw: boolean
  white_time_remaining_ms: number
  black_time_remaining_ms: number
}

type GameOver = {
  reason: 'checkmate' | 'stalemate' | 'draw' | 'timeout'
  winner: string | null
}

const gameId = 'test-game-1'
const from = ref('')
const to = ref('')
const moves = ref<Move[]>([])
const currentTurn = ref('white')
const fen = ref('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1')
const whiteTimeRemainingMs = ref(180_000)
const blackTimeRemainingMs = ref(180_000)
const connectionStatus = ref('Conectando...')
const errorMessage = ref('')
const gameOverMessage = ref('')

let socket: Socket | null = null
let channel: Channel | null = null

onMounted(() => {
  const backendUrl = useRuntimeConfig().public.api.baseURL
  const websocketUrl = `${backendUrl.replace(/^http/, 'ws').replace(/\/$/, '')}/socket`
  const playerId = `player-${crypto.randomUUID().slice(0, 8)}`

  socket = new Socket(websocketUrl, { params: { player_id: playerId } })
  socket.connect()

  channel = socket.channel(`game:${gameId}`, {})
  channel
    .join()
    .receive('ok', (state: GameState) => {
      moves.value = state.moves
      currentTurn.value = state.current_turn
      fen.value = state.fen
      whiteTimeRemainingMs.value = state.white_time_remaining_ms
      blackTimeRemainingMs.value = state.black_time_remaining_ms
      connectionStatus.value = `Conectado como ${playerId}`
    })
    .receive('error', (reason: unknown) => {
      connectionStatus.value = 'Falha ao entrar na partida'
      errorMessage.value = JSON.stringify(reason)
    })

  channel.on('move_made', (move: MoveMade) => {
    moves.value.push({ from: move.from, to: move.to, player: move.player })
    currentTurn.value = move.current_turn
    fen.value = move.new_fen
    whiteTimeRemainingMs.value = move.white_time_remaining_ms
    blackTimeRemainingMs.value = move.black_time_remaining_ms
    errorMessage.value = ''
  })

  channel.on('game_over', (result: GameOver) => {
    if (result.reason === 'timeout') {
      const winner = result.winner === 'white' ? 'brancas' : 'pretas'
      gameOverMessage.value = `Fim de jogo por tempo esgotado. Vencedor: ${winner}`
    } else if (result.reason === 'checkmate') {
      gameOverMessage.value = `Xeque-mate! Vencedor: ${result.winner}`
    } else if (result.reason === 'stalemate') {
      gameOverMessage.value = 'Partida encerrada por afogamento.'
    } else {
      gameOverMessage.value = 'Partida encerrada em empate.'
    }
  })
})

onBeforeUnmount(() => {
  channel?.leave()
  socket?.disconnect()
})

function sendMove() {
  errorMessage.value = ''

  if (!channel || !from.value.trim() || !to.value.trim()) {
    errorMessage.value = 'Preencha as casas de origem e destino.'
    return
  }

  channel
    .push('move', { from: from.value.trim(), to: to.value.trim() })
    .receive('ok', () => {
      from.value = ''
      to.value = ''
    })
    .receive('error', (reason: { reason?: string }) => {
      errorMessage.value = reason.reason === 'illegal_move' ? 'Lance ilegal' : JSON.stringify(reason)
    })
}
</script>

<template>
  <main class="container">
    <h1>Partida em tempo real</h1>
    <p class="muted">Canal: <code>game:{{ gameId }}</code></p>
    <p>{{ connectionStatus }} · turno atual: <strong>{{ currentTurn }}</strong></p>
    <div class="clocks">
      <p>Brancas: <strong>{{ Math.ceil(whiteTimeRemainingMs / 1000) }}s</strong></p>
      <p>Pretas: <strong>{{ Math.ceil(blackTimeRemainingMs / 1000) }}s</strong></p>
    </div>
    <p class="fen"><strong>FEN:</strong> <code>{{ fen }}</code></p>
    <p v-if="gameOverMessage" class="game-over">{{ gameOverMessage }}</p>

    <form class="move-form" @submit.prevent="sendMove">
      <label>
        Origem
        <input v-model="from" placeholder="e2" autocomplete="off">
      </label>
      <label>
        Destino
        <input v-model="to" placeholder="e4" autocomplete="off">
      </label>
      <button type="submit">Enviar lance</button>
    </form>

    <p v-if="errorMessage" class="error">{{ errorMessage }}</p>

    <section>
      <h2>Lances recebidos</h2>
      <p v-if="moves.length === 0" class="muted">Nenhum lance ainda.</p>
      <ol v-else>
        <li v-for="(move, index) in moves" :key="index">
          <strong>{{ move.from }} → {{ move.to }}</strong>
          <span class="muted"> por {{ move.player }}</span>
        </li>
      </ol>
    </section>
  </main>
</template>

<style scoped>
.container {
  max-width: 720px;
  min-height: 100vh;
  margin: 0 auto;
  padding: 2rem 1.5rem;
  color: #e8e8ee;
  background: #0f1115;
  font-family: system-ui, sans-serif;
}
.muted { color: #9aa0aa; }
.clocks { display: flex; gap: 2rem; }
.move-form {
  display: flex;
  align-items: end;
  gap: 1rem;
  padding: 1.25rem;
  margin: 1.5rem 0;
  background: #171a21;
  border: 1px solid #232835;
  border-radius: 12px;
}
label { display: grid; gap: 0.4rem; }
input, button {
  padding: 0.65rem 0.8rem;
  color: inherit;
  background: #0f1115;
  border: 1px solid #3a4150;
  border-radius: 6px;
}
button { cursor: pointer; background: #2855b6; border-color: #3769d4; }
li { margin: 0.6rem 0; }
.error { color: #ff7b72; }
.fen { overflow-wrap: anywhere; }
.game-over {
  padding: 1rem;
  color: #fff;
  background: #2855b6;
  border-radius: 8px;
}
@media (max-width: 560px) {
  .move-form { align-items: stretch; flex-direction: column; }
}
</style>
