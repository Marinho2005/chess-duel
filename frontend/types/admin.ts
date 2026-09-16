import type { PlayerRatings } from '~/stores/auth'
export type AccountStatus = 'active' | 'suspended' | 'banned'
export type ModerationAction = 'suspend' | 'ban' | 'reactivate'
export type Pagination = { page: number; per_page: number; total: number; total_pages: number; has_more: boolean }
export type AdminUser = {
  id: string; nickname: string; email: string; rating: number; ratings: PlayerRatings
  puzzle_rating: number; battle_rating: number; role: 'user' | 'admin'; account_status: AccountStatus
  suspended_until: string | null; inserted_at: string; country: string | null
  country_code: string | null; avatar_url: string | null; confirmed_at: string | null
}
export type UserDetail = {
  user: AdminUser
  game_summary: { total_games: number; finished_games: number; bot_games: number; wins: number }
  moderation_actions: Array<{ id: string; action: ModerationAction; reason: string
    admin: { id: string; nickname: string }; suspended_until: string | null; inserted_at: string }>
}
export type AdminPlayer = { id: string | null; nickname: string; bot: boolean; rating: number | null; rating_before: number | null; rating_after: number | null }
export type AdminGame = {
  id: string; game_id: string; status: string; white: AdminPlayer; black: AdminPlayer
  type: 'human' | 'bot'; result: string | null; end_reason: string | null
  time_control: { label: string; initial_time_ms: number; increment_ms: number }
  inserted_at: string; finished_at: string | null
  analysis: { id: string; status: string; inserted_at: string; updated_at: string } | null
  moves?: Array<{ san?: string; from?: string; to?: string; fen?: string }>
  final_fen?: string | null; white_time_remaining_ms?: number; black_time_remaining_ms?: number
}
export type AnalysisJobs = { pending_analysis_jobs: number; failed_analysis_jobs: number; executing_analysis_jobs: number }
export type Dashboard = AnalysisJobs & { total_users: number; active_games: number; games_today: number; bot_games_today: number; day_timezone: string }
export type SystemStatus = { database: string; analysis_jobs: AnalysisJobs; analysis_queue_concurrency: number | null; observed_at: string }
