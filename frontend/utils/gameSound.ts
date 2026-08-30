export type StorageLike = Pick<Storage, 'getItem' | 'setItem'>
export type ConfirmedMoveSoundData = { captured?: string | null; is_check?: boolean }

export function soundForMove(move: ConfirmedMoveSoundData): 'move' | 'capture' | 'check' {
  return move.is_check ? 'check' : move.captured ? 'capture' : 'move'
}

export function soundForSan(san?: string | null): 'move' | 'capture' | 'check' | 'gameOver' {
  if (san?.endsWith('#')) return 'gameOver'
  if (san?.endsWith('+')) return 'check'
  if (san?.includes('x')) return 'capture'
  return 'move'
}

export function readSoundPreference(storage: StorageLike | null) {
  return storage?.getItem('chess-duel:sounds-enabled') !== 'false'
}

export function writeSoundPreference(storage: StorageLike | null, enabled: boolean) {
  storage?.setItem('chess-duel:sounds-enabled', String(enabled))
}

export function createGameSoundGate(initialPly = 0) {
  let lastPly = initialPly
  let gameOverHandled = false

  return {
    sync(ply: number) { lastPly = Math.max(lastPly, ply) },
    acceptMove(ply: number, enabled: boolean) {
      if (ply <= lastPly) return false
      lastPly = ply
      return enabled
    },
    acceptGameOver(enabled: boolean) {
      if (gameOverHandled) return false
      gameOverHandled = true
      return enabled
    }
  }
}
