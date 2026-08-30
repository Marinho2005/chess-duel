import { Chess } from 'chess.js'

export type StoredMove = { from: string; to: string; promotion?: string | null; san?: string | null }
export type MoveRow = { number: number; white: string; black: string }
export type ReplayPosition = { fen: string; turn: 'white' | 'black'; lastMove: [string, string] | null }

export function movesWithSan(moves: StoredMove[]) {
  const chess = new Chess()
  return moves.map((move) => {
    const made = chess.move({ from: move.from, to: move.to, promotion: move.promotion || undefined })
    return move.san || made?.san || `${move.from}–${move.to}`
  })
}

export function groupMoveRows(moves: StoredMove[]): MoveRow[] {
  const san = movesWithSan(moves)
  return Array.from({ length: Math.ceil(san.length / 2) }, (_, index) => ({
    number: index + 1,
    white: san[index * 2] || '',
    black: san[index * 2 + 1] || ''
  }))
}

export function buildReplayPositions(moves: StoredMove[]): ReplayPosition[] {
  const chess = new Chess()
  const positions: ReplayPosition[] = [{ fen: chess.fen(), turn: 'white', lastMove: null }]

  for (const move of moves) {
    const made = chess.move({ from: move.from, to: move.to, promotion: move.promotion || undefined })
    if (!made) break
    positions.push({
      fen: chess.fen(),
      turn: chess.turn() === 'w' ? 'white' : 'black',
      lastMove: [move.from, move.to]
    })
  }

  return positions
}
