import { describe, expect, it } from 'vitest'
import { createBroadcastClockEstimate } from '../utils/broadcastClocks'

describe('broadcast clock estimate', () => {
  it('matches Valev–Kanov after joining during a long think, including cached time', () => {
    const clock = createBroadcastClockEstimate()
    const sample = { white_ms: 3988000, black_ms: 3812000, think_time_ms: 1312000, sampled_at_ms: 10000000 }
    clock.sync('Valev-Kanov-ply-23', sample.white_ms, sample.black_ms, 500, sample, 10020000)
    // 1:03:32 - 21:52 already spent on Lichess - 20 seconds in cache = 41:20.
    expect(clock.remaining(sample.black_ms, true, 500)).toBe(2480000)
    expect(clock.remaining(sample.white_ms, false, 500)).toBe(3988000)
    clock.sync('Valev-Kanov-ply-23', sample.white_ms, sample.black_ms, 1500, sample, 10021000)
    expect(clock.remaining(sample.black_ms, true, 1500)).toBe(2479000)
    const refreshed = { ...sample, think_time_ms: 1342000, sampled_at_ms: 10030000 }
    clock.sync('Valev-Kanov-ply-23', sample.white_ms, sample.black_ms, 30500, refreshed, 10050000)
    expect(clock.remaining(sample.black_ms, true, 30500)).toBe(2450000)
  })

  it('counts elapsed time only for the running clock, even after a delayed timer tick', () => {
    const clock = createBroadcastClockEstimate()
    clock.sync('position-1', 60000, 90000, 1000)
    expect(clock.remaining(60000, true, 2000)).toBe(59000)
    expect(clock.remaining(90000, false, 2000)).toBe(90000)
    expect(clock.remaining(60000, true, 16500)).toBe(44500)
    expect(clock.remaining(null, true, 16500)).toBeNull()
    expect(clock.remaining(60000, true, 100000)).toBe(0)
  })

  it('does not rewind on repeated HTTP or channel snapshots', () => {
    const clock = createBroadcastClockEstimate()
    clock.sync('position-1', 60000, 90000, 1000)
    clock.sync('position-1', 60000, 90000, 21000)
    expect(clock.remaining(60000, true, 22000)).toBe(39000)
  })

  it('realigns on a new move or a correction to the recorded clocks', () => {
    const clock = createBroadcastClockEstimate()
    clock.sync('position-1', 60000, 90000, 1000)
    clock.sync('position-2', 45000, 90000, 20000)
    expect(clock.remaining(45000, false, 23000)).toBe(45000)
    expect(clock.remaining(90000, true, 23000)).toBe(87000)
    clock.sync('position-2', 45000, 85000, 24000)
    expect(clock.remaining(85000, true, 25000)).toBe(84000)
  })

  it('shows recorded times in history or when stopped and keeps the live anchor on return', () => {
    const clock = createBroadcastClockEstimate()
    clock.sync('position-1', 60000, 90000, 1000)
    expect(clock.remaining(70000, false, 10000)).toBe(70000)
    expect(clock.remaining(60000, true, 20000)).toBe(41000)
    expect(clock.remaining(60000, false, 30000)).toBe(60000)
  })
})
