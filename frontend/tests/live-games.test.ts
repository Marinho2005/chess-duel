import { describe, expect, it } from 'vitest'
import { existsSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import type { LiveGame } from '../types/live-games'
import { formatClock, groupBroadcastMoves, turnFromFen } from '../utils/liveGames'

const root = fileURLToPath(new URL('..', import.meta.url))
const source = (path: string) => readFileSync(`${root}/${path}`, 'utf8')

describe('contratos de partidas ao vivo', () => {
  it('mantém os dois formatos em uma união discriminada', () => {
    const games: LiveGame[] = [
      { source: 'broadcast', game: { game_id: 'a', tournament_id: 'open', tournament: 'Open', round: 'R1', white: { name: 'W', title: 'GM', rating: 2500 }, black: { name: 'B', title: null, rating: null }, fen: 'fen', last_move: null, moves: [], lichess_url: 'https://lichess.org/a' } },
      { source: 'chessduel', game: { game_id: 'b', category: 'blitz', white: { id: 'w', nickname: 'W', rating: 1200, status: 'online' }, black: { id: 'b', nickname: 'B', rating: 1200, status: 'offline' }, fen: 'fen', current_turn: 'white', white_time_remaining_ms: 176420, black_time_remaining_ms: 178913, initial_time_ms: 180000, increment_ms: 0 } },
    ]
    expect(games.map(game => game.source)).toEqual(['broadcast', 'chessduel'])
  })

  it('converte milissegundos e agrupa SAN por full move', () => {
    expect(formatClock(176420)).toBe('02:56')
    expect(groupBroadcastMoves([
      { san: 'e4', from: 'e2', to: 'e4', promotion: null },
      { san: 'e5', from: 'e7', to: 'e5', promotion: null },
      { san: 'Nf3', from: 'g1', to: 'f3', promotion: null },
    ])).toEqual([
      { number: 1, white: 'e4', black: 'e5' },
      { number: 2, white: 'Nf3', black: '' },
    ])
    expect(turnFromFen('8/8/8/8/8/8/8/8 b - - 0 1')).toBe('black')
  })
})

describe('integração da UI ao vivo', () => {
  it('mantém o mini board readonly e destaca lastMove nativamente', () => {
    const board = source('components/game/ReadonlyBoard.vue')
    expect(board).toContain('movable: { color: undefined }')
    expect(board).toContain('draggable: { enabled: false }')
    expect(board).toContain('lastMove: props.lastMove || undefined')
  })

  it('abre a partida específica no Lichess em uma nova aba', () => {
    const card = source('components/live/BroadcastLiveCard.vue')
    expect(card).toContain(':href="game.lichess_url"')
    expect(card).toContain('Ver no Lichess')
    expect(card).toContain('target="_blank"')
    expect(card).toContain('rel="noopener noreferrer"')
    expect(card).toContain(':animation-duration="0"')
    expect(card).not.toContain('/watch/broadcast/')
    expect(existsSync(root + '/pages/watch/broadcast/[gameId].vue')).toBe(false)
  })

  it('mantém previews sem áudio no lobby', () => {
    expect(source('pages/lobby.vue')).not.toContain('useGameSounds()')
    expect(source('components/live/BroadcastLiveCard.vue')).not.toContain('useGameSounds()')
  })

  it('inicia um único polling, preserva resultados parciais e limpa o interval', () => {
    const composable = source('composables/useLiveGames.ts')
    expect(composable.match(/timer = setInterval/g)).toHaveLength(1)
    expect(composable).toContain('if (broadcastResult.data) broadcasts.value')
    expect(composable).toContain('if (chessDuelResult.data) chessDuelGames.value')
    expect(composable).toContain('clearInterval(timer)')
  })

  it('continua baseado nos tokens comuns aos temas claro, preto e navy', () => {
    const themes = source('assets/css/theme.css')
    const lobby = source('pages/lobby.vue')
    expect(themes).toContain(":root[data-theme='white']")
    expect(themes).toContain(":root[data-theme='black']")
    expect(themes).toContain(":root[data-theme='navy']")
    expect(lobby).toContain('background: var(--surface)')
  })

  it('oferece página dedicada, agrupamento por torneio e filtro ChessDuel', () => {
    const watch = source('pages/observar/index.vue')
    const tournament = source('pages/observar/torneio/[tournamentId].vue')
    expect(watch).toContain('/api/broadcasts/tournaments')
    expect(watch).toContain('category: category.value')
    expect(watch).toContain('blitz_increment')
    expect(tournament).toContain('/api/broadcasts/rounds/${encodeURIComponent(selectedRound.value)}/games')
    expect(watch).toContain('tournament.image_url')
    expect(tournament).toContain('tournament.value?.image_url')
    expect(tournament).toContain('<LiveBroadcastLiveCard')
    const presenceAvatar = source('components/profile/PresenceAvatar.vue')
    expect(presenceAvatar).toContain('bottom: 0')
    expect(presenceAvatar).toContain('box-sizing: border-box')
  })
})
