export type BoardLayoutSize = 'compact' | 'standard' | 'large'
export type LayoutStorage = Pick<Storage, 'getItem' | 'setItem'>

const storageKey = 'chess-duel:board-layout-size'

export function readBoardLayoutSize(storage: LayoutStorage | null): BoardLayoutSize {
  const value = storage?.getItem(storageKey)
  return value === 'compact' || value === 'large' ? value : 'standard'
}

export function writeBoardLayoutSize(storage: LayoutStorage | null, value: BoardLayoutSize) {
  storage?.setItem(storageKey, value)
}
