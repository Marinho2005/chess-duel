import { describe, it, expect } from 'vitest'
import { moderationPayload } from '../utils/admin'

describe('confirmação de moderação', () => {
  const now = Date.parse('2026-09-08T12:00:00Z')
  it('converte durações em um instante UTC futuro', () => {
    expect(moderationPayload('suspend', ' Abuso ', '3600', '', now)).toEqual({ reason: 'Abuso', suspended_until: '2026-09-08T13:00:00.000Z' })
    expect(moderationPayload('suspend', 'Motivo', 'custom', '2026-09-09T12:00:00Z', now).suspended_until).toBe('2026-09-09T12:00:00.000Z')
  })
  it('exige motivo para todas as ações', () => {
    for (const action of ['suspend', 'ban', 'reactivate'] as const) {
      expect(() => moderationPayload(action, '  ', '3600', '', now)).toThrow('motivo')
    }
  })
  it('recusa datas inválidas, passadas e duração zero', () => {
    for (const date of ['', 'bad', '2026-09-08T11:00:00Z', '2026-09-08T12:00:00Z']) {
      expect(() => moderationPayload('suspend', 'Motivo', 'custom', date, now)).toThrow('data futura')
    }
    expect(() => moderationPayload('suspend', 'Motivo', '0', '', now)).toThrow('data futura')
  })
  it('banimento e reativação nunca carregam prazo de suspensão', () => {
    expect(moderationPayload('ban', 'Motivo', '3600', '', now)).toEqual({ reason: 'Motivo' })
    expect(moderationPayload('reactivate', 'Revisão', 'custom', 'invalid', now)).toEqual({ reason: 'Revisão' })
  })
})
