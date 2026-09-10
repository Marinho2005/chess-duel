import { describe, expect, it } from 'vitest'
import { spawnSync } from 'node:child_process'
import { broadcastClocks, formatBroadcastClock } from '../utils/broadcastClocks'
import type { LiveMove } from '../types/live-games'

function parse(movetext: string, headers = '') {
  const pgn = `[Event "Clock test"]\n${headers}\n${movetext}`
  const result = spawnSync('node', ['../backend/priv/chess_validator/validator.js'], {
    input: JSON.stringify({ action: 'parse_pgn', pgn }) + '\n', encoding: 'utf8',
  })
  expect(result.status).toBe(0)
  const response = JSON.parse(result.stdout)
  expect(response.ok).toBe(true)
  return response.games[0].moves as LiveMove[]
}

describe('broadcast clocks from PGN to displayed position', () => {
  it('preserves hours, fractions, increments and zero, synchronized with replay', () => {
    const moves = parse('1. e4 {[%clk 1:02:03.5]} e5 {[%clk 0:05:00]} 2. Nf3 {[%clk 1:02:05]} Nc6 {[%clk 0:00:00]} *')
    expect(broadcastClocks(moves, 0)).toEqual({ white: null, black: null })
    expect(broadcastClocks(moves, 1)).toEqual({ white: 3723500, black: null })
    expect(broadcastClocks(moves, 2)).toEqual({ white: 3723500, black: 300000 })
    expect(broadcastClocks(moves, 4)).toEqual({ white: 3725000, black: 0 })
    expect(formatBroadcastClock(3723500)).toBe('1:02:03')
    expect(formatBroadcastClock(300000)).toBe('05:00')
    expect(formatBroadcastClock(0)).toBe('00:00')
    expect(formatBroadcastClock(null)).toBe('—')
  })

  it('does not invent times for missing or malformed annotations', () => {
    const moves = parse('1. e4 {[%clk 0:05:00]} e5 {[%clk invalid]} 2. Nf3 *')
    expect(broadcastClocks(moves, 3)).toEqual({ white: null, black: null })
    expect(parse('1. e4 {[%clk 0:99:00]} *')[0]?.clock_ms).toBeNull()
  })

  it('assigns clocks correctly when a custom position starts with black', () => {
    const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1'
    const moves = parse('1... e5 {[%clk 0:04:59]} 2. Nf3 {[%clk 0:04:58]} *', `[SetUp "1"]\n[FEN "${fen}"]`)
    expect(broadcastClocks(moves, 1, fen)).toEqual({ white: null, black: 299000 })
    expect(broadcastClocks(moves, 2, fen)).toEqual({ white: 298000, black: 299000 })
  })
})
