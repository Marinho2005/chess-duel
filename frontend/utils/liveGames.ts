import type { BroadcastGame, ChessDuelLiveGame, LiveFeedItem, LiveMove } from '~/types/live-games'

export function formatClock(milliseconds: number) {
  const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000))
  return `${String(Math.floor(totalSeconds / 60)).padStart(2, '0')}:${String(totalSeconds % 60).padStart(2, '0')}`
}

export function groupBroadcastMoves(moves: LiveMove[]) {
  return Array.from({ length: Math.ceil(moves.length / 2) }, (_, index) => ({
    number: index + 1,
    white: moves[index * 2]?.san || '',
    black: moves[index * 2 + 1]?.san || '',
  }))
}

export function turnFromFen(fen: string): 'white' | 'black' {
  return fen.split(' ')[1] === 'b' ? 'black' : 'white'
}

export function combineLiveFeed(
  broadcasts: BroadcastGame[],
  chessDuelGames: ChessDuelLiveGame[],
): LiveFeedItem[] {
  return [
    ...broadcasts.map(game => ({
      id: `broadcast-${game.game_id}`,
      source: 'broadcast' as const,
      game,
    })),
    ...chessDuelGames.map(game => ({
      id: `chessduel-${game.game_id}`,
      source: 'chessduel' as const,
      game,
    })),
  ]
}
