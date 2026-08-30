export type AnalysisStatus = 'idle' | 'checking' | 'missing' | 'pending' | 'processing' | 'completed' | 'failed'

export function analysisAction(
  gameStatus: 'waiting' | 'in_progress' | 'finished',
  guest: boolean,
  reviewGameId: string | null,
  status: AnalysisStatus
) {
  if (gameStatus !== 'finished' || guest || !reviewGameId) return 'hidden' as const
  if (['checking', 'pending', 'processing'].includes(status)) return 'processing' as const
  return 'button' as const
}
