import type { BroadcastClockSnapshot, LiveMove } from '../types/live-games'

export function broadcastClocks(moves: LiveMove[], ply: number, initialFen?: string | null) {
  const clocks: { white: number | null; black: number | null } = { white: null, black: null }
  const blackStarts = initialFen?.split(' ')[1] === 'b'
  for (let index = 0; index < Math.min(ply, moves.length); index++) {
    const color = (index % 2 === 0) !== blackStarts ? 'white' : 'black'
    const value = moves[index]?.clock_ms
    // A missing annotation invalidates this player's previous reading.
    clocks[color] = typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null
  }
  return clocks
}

export function formatBroadcastClock(milliseconds: number | null) {
  if (milliseconds === null) return '—'
  const seconds = Math.floor(milliseconds / 1000)
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor(seconds / 60) % 60
  const remainder = String(seconds % 60).padStart(2, '0')
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, '0')}:${remainder}`
    : `${String(minutes).padStart(2, '0')}:${remainder}`
}

// Repeated HTTP/channel snapshots must not restart the current turn's estimate.
export function createBroadcastClockEstimate() {
  let signature = ''
  let startedAt = 0
  return {
    sync(position: string, white: number | null, black: number | null, now: number,
      source?: BroadcastClockSnapshot | null, wallNow = Date.now()) {
      const timedSource = source?.think_time_ms == null ? null : source
      const next = JSON.stringify([position, white, black, timedSource])
      if (next === signature) return
      signature = next
      // Include thinking before the viewer joined, plus time spent in backend caches/transit.
      const elapsed = source?.think_time_ms == null ? 0
        : source.think_time_ms + Math.max(0, wallNow - source.sampled_at_ms)
      startedAt = now - elapsed
    },
    remaining(recorded: number | null, running: boolean, now: number) {
      if (recorded === null || !running) return recorded
      return Math.max(0, recorded - Math.max(0, now - startedAt))
    },
  }
}
