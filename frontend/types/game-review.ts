export type Evaluation = { type: 'cp' | 'mate'; value: number }

export type AnalyzedMove = {
  ply: number
  move_number: number
  color: 'white' | 'black'
  played_move: string
  best_move: string
  evaluation_before: Evaluation
  evaluation: Evaluation
  principal_variation: string[]
  centipawn_loss: number
  classification: 'best' | 'good' | 'inaccuracy' | 'mistake' | 'blunder'
}

export type ReviewPlayer = { id: string; nickname: string; avatar_url: string | null }
export type ReviewResponse = {
  id: string
  status: 'pending' | 'processing' | 'completed' | 'failed'
  results: { depth: number; initial_evaluation: Evaluation; moves: AnalyzedMove[] } | null
  error: string | null
  game: {
    id: string
    moves: Array<{ from: string; to: string; promotion?: string | null }>
    result: string
    end_reason: string
    viewer_color: 'white' | 'black'
    white_player: ReviewPlayer
    black_player: ReviewPlayer
  }
}
