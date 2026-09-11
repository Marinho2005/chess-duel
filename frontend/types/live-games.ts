export type LiveMove = { clock_ms?: number | null; san: string; from: string; to: string; promotion: string | null }
export type BroadcastPlayer = {
  name: string
  title: string | null
  rating: number | null
  country_code?: string | null
}
export type BroadcastLiveGame = {
  game_id: string
  tournament_id: string
  tournament: string
  tournament_image?: string | null
  round: string
  round_id?: string
  result?: string
  initial_fen?: string | null
  white: BroadcastPlayer
  black: BroadcastPlayer
  fen: string
  last_move: LiveMove | null
  moves: LiveMove[]
  lichess_url: string
}
export type ChessDuelLivePlayer = {
  id: string
  nickname: string
  rating: number
  country_code?: string | null
  avatar_url?: string | null
  status: 'online' | 'offline' | 'away' | 'dnd'
}
export type ChessDuelLiveGame = {
  game_id: string
  category: 'bullet' | 'blitz' | 'blitz_increment' | 'rapid'
  white: ChessDuelLivePlayer
  black: ChessDuelLivePlayer
  fen: string
  current_turn: 'white' | 'black'
  white_time_remaining_ms: number
  black_time_remaining_ms: number
  initial_time_ms: number
  increment_ms: number
}
export type LiveGame =
  | { source: 'broadcast'; game: BroadcastLiveGame }
  | { source: 'chessduel'; game: ChessDuelLiveGame }

// Nomes usados pelo feed do lobby. Mantêm o contrato HTTP explícito sem
// duplicar estruturas equivalentes.
export type BroadcastGame = BroadcastLiveGame
export type BroadcastsApiResponse = { games: BroadcastGame[] }
export type ChessDuelLiveApiResponse = { games: ChessDuelLiveGame[] }
export type BroadcastTournament = { tournament_id: string; name: string; image_url: string | null; live_games: number | null }
export type BroadcastTournamentsApiResponse = { tournaments: BroadcastTournament[] }
export type LiveFeedItem =
  | { id: string; source: 'broadcast'; game: BroadcastGame }
  | { id: string; source: 'chessduel'; game: ChessDuelLiveGame }

export type BroadcastRound = { id: string; name: string; ongoing: boolean; finished: boolean; starts_at: number | null }
export type BroadcastTournamentDetail = { tournament_id: string; name: string; image_url: string | null; rounds: BroadcastRound[] }
