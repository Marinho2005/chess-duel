import type { ModerationAction } from '~/types/admin'
export const accountLabels = { active: 'Ativa', suspended: 'Suspensa', banned: 'Banida' }
export const actionLabels = { suspend: 'Suspender', ban: 'Banir', reactivate: 'Reativar' }
export const historyLabels = { suspend: 'Suspensão', ban: 'Banimento', reactivate: 'Reativação' }
const labels: Record<string, string> = {
  waiting: 'Aguardando', in_progress: 'Em andamento', finished: 'Finalizada',
  white_wins: 'Vitória das brancas', black_wins: 'Vitória das pretas', draw: 'Empate', abandoned: 'Abandonada',
  checkmate: 'Xeque-mate', timeout: 'Tempo esgotado', stalemate: 'Afogamento', abandonment: 'Abandono',
  resignation: 'Desistência', aborted: 'Abortada', pending: 'Pendente', processing: 'Processando',
  completed: 'Concluída', failed: 'Com erro',
}
export function adminLabel(value: string | null | undefined) { return value ? labels[value] || value : '—' }
export function adminDate(value: string | null | undefined) {
  return value ? new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value)) : '—'
}
export function moderationPayload(action: ModerationAction, reason: string, duration: string, customDate: string, now = Date.now()) {
  if (!reason.trim()) throw new Error('Informe o motivo da ação.')
  if (reason.trim().length > 2000) throw new Error('Use até 2.000 caracteres no motivo.')
  const payload: { reason: string; suspended_until?: string } = { reason: reason.trim() }
  if (action === 'suspend') {
    const end = duration === 'custom' ? new Date(customDate).getTime() : now + Number(duration) * 1000
    if (!Number.isFinite(end) || end <= now) throw new Error('Escolha uma data futura para o fim da suspensão.')
    payload.suspended_until = new Date(end).toISOString()
  }
  return payload
}
