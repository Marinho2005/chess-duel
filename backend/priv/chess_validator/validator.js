import { createInterface } from 'node:readline'
import { Chess } from 'chess.js'

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity })

function validateMove(request) {
  try {
    const chess = new Chess(request.fen)
    const move = chess.move({
      from: request.from,
      to: request.to,
      ...(request.promotion ? { promotion: request.promotion } : {}),
    })

    if (!move) return { valid: false, reason: 'illegal_move' }

    return {
      valid: true,
      new_fen: chess.fen(),
      is_check: chess.isCheck(),
      is_checkmate: chess.isCheckmate(),
      is_stalemate: chess.isStalemate(),
      is_draw: chess.isDraw(),
      captured: move.captured ?? null,
      san: move.san,
    }
  } catch (_error) {
    return { valid: false, reason: 'illegal_move' }
  }
}

function parsePgn(pgn) {
  const chunks = pgn.trim().split(/\n\s*\n(?=\[Event\s)/)

  return chunks.filter(Boolean).map((source) => {
    const chess = new Chess()
    chess.loadPgn(source, { strict: false })
    const headers = chess.getHeaders()
    const moves = chess.history({ verbose: true }).map((move) => ({
      san: move.san,
      from: move.from,
      to: move.to,
      promotion: move.promotion ?? null,
    }))

    return { headers, moves, fen: chess.fen() }
  })
}

lines.on('line', (line) => {
  try {
    const request = JSON.parse(line)
    const response = request.action === 'parse_pgn'
      ? { ok: true, games: parsePgn(request.pgn) }
      : validateMove(request)
    process.stdout.write(`${JSON.stringify(response)}\n`)
  } catch (_error) {
    process.stdout.write(`${JSON.stringify({ valid: false, reason: 'illegal_move' })}\n`)
  }
})
