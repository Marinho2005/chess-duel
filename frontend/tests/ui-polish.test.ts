import { describe, expect, it } from 'vitest'
import { buildReplayPositions, groupMoveRows, movesWithSan } from '../utils/chessMoves'
import { countryFlag, normalizeCountryCode } from '../utils/countries'
import { createGameSoundGate, readSoundPreference, soundForMove, soundForSan, writeSoundPreference } from '../utils/gameSound'
import { analysisAction } from '../utils/postGameAnalysis'
import { readBoardLayoutSize, writeBoardLayoutSize } from '../utils/boardLayout'

function memoryStorage() {
  const values = new Map<string, string>()
  return { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => values.set(key, value) }
}

describe('sons da partida', () => {
  it('aceita cada movimento uma vez e não repete plies reconstruídos no reconnect', () => {
    const gate = createGameSoundGate(4)
    expect(gate.acceptMove(4, true)).toBe(false)
    expect(gate.acceptMove(5, true)).toBe(true)
    expect(gate.acceptMove(5, true)).toBe(false)
  })

  it('mute bloqueia som e permanece no armazenamento local', () => {
    const storage = memoryStorage()
    writeSoundPreference(storage, false)
    expect(readSoundPreference(storage)).toBe(false)
    expect(createGameSoundGate().acceptMove(1, false)).toBe(false)
  })

  it('diferencia movimento normal, captura e xeque pelo evento confirmado', () => {
    expect(soundForMove({})).toBe('move')
    expect(soundForMove({ captured: 'p' })).toBe('capture')
    expect(soundForMove({ captured: 'p', is_check: true })).toBe('check')
  })

  it('escolhe o efeito correto para cada lance SAN no review', () => {
    expect(soundForSan('e4')).toBe('move')
    expect(soundForSan('Nxe5')).toBe('capture')
    expect(soundForSan('Qh5+')).toBe('check')
    expect(soundForSan('Qh7#')).toBe('gameOver')
  })
})

describe('ação pós-jogo', () => {
  it('fica oculta durante a partida e aparece ao terminar', () => {
    expect(analysisAction('in_progress', false, 'game-id', 'missing')).toBe('hidden')
    expect(analysisAction('finished', false, 'game-id', 'missing')).toBe('button')
    expect(analysisAction('finished', false, 'game-id', 'completed')).toBe('button')
  })

  it('representa análise em processamento sem oferecer novo disparo', () => {
    expect(analysisAction('finished', false, 'game-id', 'processing')).toBe('processing')
  })
})

describe('tamanho do layout da partida', () => {
  it('usa padrão por default e persiste a escolha do jogador', () => {
    const storage = memoryStorage()
    expect(readBoardLayoutSize(storage)).toBe('standard')
    writeBoardLayoutSize(storage, 'large')
    expect(readBoardLayoutSize(storage)).toBe('large')
  })
})

describe('país', () => {
  it('normaliza ISO válido e mantém ausência de país', () => {
    expect(normalizeCountryCode('br')).toBe('BR')
    expect(normalizeCountryCode('BRA')).toBe('BR')
    expect(normalizeCountryCode('USA')).toBe('US')
    expect(countryFlag('BR')).toBe('🇧🇷')
    expect(countryFlag('BRA')).toBe('🇧🇷')
    expect(countryFlag(null)).toBe('')
  })
})

describe('planilha SAN', () => {
  it('reconstrói uma posição navegável para cada lance da partida', () => {
    const positions = buildReplayPositions([
      { from: 'e2', to: 'e4' }, { from: 'e7', to: 'e5' }, { from: 'g1', to: 'f3' }
    ])
    expect(positions).toHaveLength(4)
    expect(positions[0]?.lastMove).toBeNull()
    expect(positions[2]?.lastMove).toEqual(['e7', 'e5'])
    expect(positions[3]?.turn).toBe('black')
  })

  it('agrupa plies em full moves e permite a última coluna preta vazia', () => {
    const rows = groupMoveRows([
      { from: 'e2', to: 'e4' }, { from: 'e7', to: 'e5' },
      { from: 'g1', to: 'f3' }, { from: 'b8', to: 'c6' },
      { from: 'f1', to: 'b5' }
    ])
    expect(rows).toEqual([
      { number: 1, white: 'e4', black: 'e5' },
      { number: 2, white: 'Nf3', black: 'Nc6' },
      { number: 3, white: 'Bb5', black: '' }
    ])
  })

  it('usa SAN correta do chess.js para captura e roque', () => {
    expect(movesWithSan([
      { from: 'e2', to: 'e4' }, { from: 'd7', to: 'd5' }, { from: 'e4', to: 'd5' }
    ])).toEqual(['e4', 'd5', 'exd5'])
    expect(movesWithSan([{ from: 'e2', to: 'e4', san: 'O-O' }])).toEqual(['O-O'])
  })
})
