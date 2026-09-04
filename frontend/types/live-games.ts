export type LiveMove = { san: string; from: string; to: string; promotion: string | null }
export type BroadcastPlayer = {
  name: string
  title: string | null
  rating: number | null
  country_code?: string | null
}
export type BroadcastLiveGame = {
  game_id: string
  tournament: string
  round: string
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
}
export type ChessDuelLiveGame = {
  game_id: string
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
export type LiveFeedItem =
  | { id: string; source: 'broadcast'; game: BroadcastGame }
  | { id: string; source: 'chessduel'; game: ChessDuelLiveGame }
