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
    }
  } catch (_error) {
    return { valid: false, reason: 'illegal_move' }
  }
}

lines.on('line', (line) => {
  try {
    const request = JSON.parse(line)
    process.stdout.write(`${JSON.stringify(validateMove(request))}\n`)
  } catch (_error) {
    process.stdout.write(`${JSON.stringify({ valid: false, reason: 'illegal_move' })}\n`)
  }
})
