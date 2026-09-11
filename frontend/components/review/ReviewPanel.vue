<script setup lang="ts">
import { Chess } from 'chess.js'
import { Activity, ChevronDown, ChevronFirst, ChevronLast, ChevronLeft, ChevronRight } from 'lucide-vue-next'
import { resolveAvatarUrl } from '~/utils/avatar'
import type { AnalyzedMove, Evaluation, ReviewPlayer } from '~/types/game-review'

type DisplayMove = AnalyzedMove & { san: string }

type FormattedPvToken = {
  moveNumber?: number
  isBlackContinuation?: boolean
  figurine?: string
  text: string
}

const props = defineProps<{
  evaluation: Evaluation
  depth: number
  moves: DisplayMove[]
  positions?: Array<{ fen: string }>
  currentPly: number
  whitePlayer: ReviewPlayer | null
  blackPlayer: ReviewPlayer | null
}>()

const emit = defineEmits<{ select: [ply: number] }>()

const config = useRuntimeConfig()
const whiteAvatar = computed(() => resolveAvatarUrl(props.whitePlayer?.avatar_url, config.public.api.baseURL))
const blackAvatar = computed(() => resolveAvatarUrl(props.blackPlayer?.avatar_url, config.public.api.baseURL))

const isPvExpanded = ref(false)

const activeMove = computed(() => (props.currentPly ? props.moves[props.currentPly - 1] : null))

const evaluationLabel = computed(() => {
  if (props.evaluation.type === 'mate') {
    return `${props.evaluation.value < 0 ? '-' : ''}M${Math.abs(props.evaluation.value)}`
  }

  const pawns = props.evaluation.value / 100
  return `${pawns >= 0 ? '+' : ''}${pawns.toFixed(1)}`
})

const pvScoreLabel = computed(() => {
  const evalObj = activeMove.value?.evaluation_before || props.evaluation
  if (evalObj.type === 'mate') {
    return evalObj.value > 0 ? `+M${evalObj.value}` : `-M${Math.abs(evalObj.value)}`
  }
  const pawns = evalObj.value / 100
  return `${pawns >= 0 ? '+' : ''}${pawns.toFixed(2)}`
})

const formattedPv = computed<FormattedPvToken[]>(() => {
  if (!activeMove.value || !activeMove.value.principal_variation?.length) return []

  const fen = props.positions?.[props.currentPly - 1]?.fen
  const chess = fen ? new Chess(fen) : new Chess()
  const tokens: FormattedPvToken[] = []

  for (let i = 0; i < activeMove.value.principal_variation.length; i++) {
    const uci = activeMove.value.principal_variation[i]
    if (!uci || uci.length < 4) continue

    const from = uci.slice(0, 2)
    const to = uci.slice(2, 4)
    const promotion = uci[4] || undefined

    const turn = chess.turn()
    const fullMove = chess.moveNumber()

    try {
      const m = chess.move({ from, to, promotion })
      if (!m) break

      let figurine = ''
      if (m.piece !== 'p') {
        const whiteFig: Record<string, string> = { n: '♘', b: '♗', r: '♖', q: '♕', k: '♔' }
        const blackFig: Record<string, string> = { n: '♞', b: '♝', r: '♜', q: '♛', k: '♚' }
        figurine = turn === 'w' ? whiteFig[m.piece] : blackFig[m.piece]
      }

      let text = m.san
      if (m.piece !== 'p' && text.startsWith(m.piece.toUpperCase())) {
        text = text.slice(1)
      }

      tokens.push({
        moveNumber: turn === 'w' ? fullMove : (i === 0 ? fullMove : undefined),
        isBlackContinuation: turn === 'b' && i === 0,
        figurine,
        text
      })
    } catch {
      break
    }
  }

  return tokens
})

const formattedBestMove = computed<{ figurine?: string; text: string } | null>(() => {
  if (!activeMove.value || !activeMove.value.best_move) return null
  const uci = activeMove.value.best_move
  if (uci.length < 4) return null

  const fen = props.positions?.[props.currentPly - 1]?.fen
  const chess = fen ? new Chess(fen) : new Chess()
  const from = uci.slice(0, 2)
  const to = uci.slice(2, 4)
  const promotion = uci[4] || undefined

  try {
    const turn = chess.turn()
    const m = chess.move({ from, to, promotion })
    if (!m) return null

    let figurine = ''
    if (m.piece !== 'p') {
      const whiteFig: Record<string, string> = { n: '♘', b: '♗', r: '♖', q: '♕', k: '♔' }
      const blackFig: Record<string, string> = { n: '♞', b: '♝', r: '♜', q: '♛', k: '♚' }
      figurine = turn === 'w' ? whiteFig[m.piece] : blackFig[m.piece]
    }

    let text = m.san
    if (m.piece !== 'p' && text.startsWith(m.piece.toUpperCase())) {
      text = text.slice(1)
    }

    return { figurine, text }
  } catch {
    return { figurine: '', text: uci }
  }
})

const classificationLabels = {
  best: 'Melhor lance',
  good: 'Bom lance',
  inaccuracy: 'Imprecisão',
  mistake: 'Erro',
  blunder: 'Erro grave'
}
</script>

<template>
  <aside class="analysis-panel">
    <header class="engine-summary">
      <div class="engine-score">
        <span class="engine-status"><Activity :size="18" aria-hidden="true" /></span>
        <strong>{{ evaluationLabel }}</strong>
      </div>
      <div class="engine-meta">
        <b>Stockfish</b>
        <span>Profundidade {{ depth }}</span>
      </div>
    </header>

    <section class="players" aria-label="Jogadores da partida">
      <NuxtLink
        v-if="whitePlayer?.nickname"
        :to="`/user/${encodeURIComponent(whitePlayer.nickname)}`"
        class="player-card white-side"
        :title="`Ver perfil de ${whitePlayer.nickname}`"
      >
        <div class="player-avatar-wrapper">
          <img v-if="whiteAvatar" :src="whiteAvatar" :alt="`Foto de ${whitePlayer.nickname}`" class="player-avatar" />
          <span v-else class="player-avatar fallback">{{ whitePlayer.nickname.charAt(0).toUpperCase() }}</span>
          <i class="piece-badge white-piece" title="Peças Brancas" />
        </div>
        <div class="player-meta">
          <span class="player-name">{{ whitePlayer.nickname }}</span>
          <ProfileCountryFlag v-if="whitePlayer.country_code" :code="whitePlayer.country_code" />
        </div>
      </NuxtLink>
      <div v-else class="player-card white-side anonymous">
        <div class="player-avatar-wrapper">
          <span class="player-avatar fallback">B</span>
          <i class="piece-badge white-piece" />
        </div>
        <span class="player-name">Brancas</span>
      </div>

      <span class="versus">vs</span>

      <NuxtLink
        v-if="blackPlayer?.nickname"
        :to="`/user/${encodeURIComponent(blackPlayer.nickname)}`"
        class="player-card black-side"
        :title="`Ver perfil de ${blackPlayer.nickname}`"
      >
        <div class="player-meta">
          <ProfileCountryFlag v-if="blackPlayer.country_code" :code="blackPlayer.country_code" />
          <span class="player-name">{{ blackPlayer.nickname }}</span>
        </div>
        <div class="player-avatar-wrapper">
          <img v-if="blackAvatar" :src="blackAvatar" :alt="`Foto de ${blackPlayer.nickname}`" class="player-avatar" />
          <span v-else class="player-avatar fallback">{{ blackPlayer.nickname.charAt(0).toUpperCase() }}</span>
          <i class="piece-badge black-piece" title="Peças Pretas" />
        </div>
      </NuxtLink>
      <div v-else class="player-card black-side anonymous">
        <span class="player-name">Pretas</span>
        <div class="player-avatar-wrapper">
          <span class="player-avatar fallback">P</span>
          <i class="piece-badge black-piece" />
        </div>
      </div>
    </section>

    <section class="variation-container">
      <div
        v-if="activeMove?.principal_variation.length"
        class="variation-bar"
        :class="{ expanded: isPvExpanded }"
        @click="isPvExpanded = !isPvExpanded"
      >
        <span class="pv-eval-badge">{{ pvScoreLabel }}</span>
        <div class="pv-moves">
          <span v-for="(token, idx) in formattedPv" :key="idx" class="pv-move-item">
            <span v-if="token.moveNumber" class="pv-num">
              {{ token.moveNumber }}{{ token.isBlackContinuation ? '...' : '.' }}
            </span>
            <span v-if="token.figurine" class="pv-figurine">{{ token.figurine }}</span>
            <span class="pv-san">{{ token.text }}</span>
          </span>
        </div>
        <button
          type="button"
          class="pv-toggle-btn"
          :aria-label="isPvExpanded ? 'Recolher linha' : 'Expandir linha'"
        >
          <ChevronDown :size="15" :class="{ rotated: isPvExpanded }" />
        </button>
      </div>
      <div v-else class="variation-empty">
        <small>Selecione um lance para ver a variante calculada.</small>
      </div>
    </section>

    <MoveList :moves="moves" :current-ply="currentPly" @select="emit('select', $event)" />

    <section v-if="activeMove" class="move-insight">
      <div>
        <span class="classification" :class="activeMove.classification">
          {{ classificationLabels[activeMove.classification] }}
        </span>
        <strong>{{ activeMove.san }}</strong>
      </div>
      <div v-if="formattedBestMove" class="best-move-hint">
        <span>Melhor lance na posição era:</span>
        <strong class="best-move-badge">
          <span v-if="formattedBestMove.figurine" class="best-move-figurine">{{ formattedBestMove.figurine }}</span>
          <span class="best-move-san">{{ formattedBestMove.text }}</span>
        </strong>
      </div>
    </section>

    <nav aria-label="Navegação pelos lances">
      <button type="button" title="Posição inicial" :disabled="currentPly === 0" @click="emit('select', 0)">
        <ChevronFirst :size="21" aria-hidden="true" />
      </button>
      <button type="button" title="Lance anterior" :disabled="currentPly === 0" @click="emit('select', currentPly - 1)">
        <ChevronLeft :size="23" aria-hidden="true" />
      </button>
      <span>{{ currentPly }} / {{ moves.length }}</span>
      <button type="button" title="Próximo lance" :disabled="currentPly === moves.length" @click="emit('select', currentPly + 1)">
        <ChevronRight :size="23" aria-hidden="true" />
      </button>
      <button type="button" title="Posição final" :disabled="currentPly === moves.length" @click="emit('select', moves.length)">
        <ChevronLast :size="21" aria-hidden="true" />
      </button>
    </nav>
  </aside>
</template>

<style scoped>
.analysis-panel { display: flex; min-height: 0; flex-direction: column; overflow: hidden; color: var(--text); background: color-mix(in srgb, var(--surface) 97%, transparent); border: 1px solid var(--border); border-radius: 12px; box-shadow: var(--shadow); }
.engine-summary { display: flex; min-height: 72px; align-items: center; gap: .9rem; padding: .85rem 1rem; background: var(--surface-strong); border-top: 3px solid var(--success); border-bottom: 1px solid var(--border); }
.engine-score { display: flex; align-items: center; gap: .65rem; }.engine-score strong { min-width: 66px; color: var(--text); font: 700 1.8rem/1 var(--font-mono); }.engine-status { display: grid; width: 32px; height: 32px; place-items: center; color: var(--accent-ink); background: var(--success); border-radius: 7px; }.engine-meta { display: grid; gap: .15rem; }.engine-meta b { font-size: .9rem; }.engine-meta span { color: var(--text-muted); font-size: .75rem; }
.players { display: flex; padding: .6rem .85rem; align-items: center; justify-content: space-between; gap: .5rem; border-bottom: 1px solid var(--border); background: var(--surface); }
.player-card { display: flex; align-items: center; gap: .55rem; min-width: 0; flex: 1; padding: .25rem .45rem; border-radius: 8px; text-decoration: none; color: var(--text); transition: background 0.15s ease; }
.player-card:hover { background: var(--surface-hover); }
.player-card:hover .player-name { color: var(--accent); }
.player-card.black-side { justify-content: flex-end; }
.player-avatar-wrapper { position: relative; width: 32px; height: 32px; flex-shrink: 0; }
.player-avatar { display: block; width: 32px; height: 32px; border-radius: 50%; object-fit: cover; border: 1px solid var(--border); }
.player-avatar.fallback { display: grid; place-items: center; background: var(--accent); color: var(--accent-ink); font-weight: 800; font-size: .82rem; font-family: var(--font-serif); }
.piece-badge { position: absolute; right: -2px; bottom: -2px; width: 11px; height: 11px; border-radius: 50%; border: 2px solid var(--surface); }
.white-piece { background: #ffffff; box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.2); }
.black-piece { background: #222222; box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.2); }
.player-meta { display: flex; align-items: center; gap: .35rem; min-width: 0; overflow: hidden; }
.player-name { font-weight: 700; font-size: .83rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; transition: color 0.15s ease; }
.versus { flex-shrink: 0; color: var(--text-muted); font-size: .68rem; font-weight: 800; text-transform: uppercase; letter-spacing: .08em; padding: .15rem .4rem; background: var(--surface-strong); border-radius: 6px; border: 1px solid var(--border-subtle); }

.variation-container { padding: .55rem .85rem; background: var(--surface); border-bottom: 1px solid var(--border); }
.variation-bar { display: flex; align-items: center; gap: .65rem; background: var(--surface-strong); border: 1px solid var(--border-subtle); border-radius: 8px; padding: .4rem .7rem; cursor: pointer; user-select: none; transition: background 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease; }
.variation-bar:hover { background: var(--surface-hover); border-color: var(--border); }
.pv-eval-badge { flex-shrink: 0; display: inline-flex; align-items: center; justify-content: center; padding: .2rem .5rem; background: var(--surface); color: var(--text); border: 1px solid var(--border); font-family: var(--font-mono); font-weight: 800; font-size: .78rem; line-height: 1.2; border-radius: 5px; box-shadow: 0 1px 3px var(--shadow); }
.pv-moves { flex: 1; min-width: 0; display: flex; align-items: center; gap: .35rem; overflow: hidden; white-space: nowrap; font-family: var(--font-sans); font-size: .84rem; font-weight: 600; color: var(--text); mask-image: linear-gradient(to right, black 86%, transparent 100%); -webkit-mask-image: linear-gradient(to right, black 86%, transparent 100%); }
.variation-bar.expanded .pv-moves { white-space: normal; flex-wrap: wrap; mask-image: none; -webkit-mask-image: none; }
.pv-move-item { display: inline-flex; align-items: center; gap: .15rem; }
.pv-num { color: var(--text-muted); font-weight: 700; }
.pv-figurine { font-size: .95rem; line-height: 1; }
.pv-san { color: var(--text); font-weight: 600; }
.pv-toggle-btn { flex-shrink: 0; display: flex; align-items: center; justify-content: center; background: transparent; border: 0; padding: 0; color: var(--text-muted); cursor: pointer; transition: transform 0.2s ease, color 0.15s ease; }
.variation-bar:hover .pv-toggle-btn { color: var(--accent); }
.pv-toggle-btn .rotated { transform: rotate(180deg); }
.variation-empty { padding: .35rem 0; color: var(--text-muted); font-size: .78rem; }

.move-insight { display: grid; gap: .6rem; margin-top: auto; padding: .9rem 1rem; border-top: 1px solid var(--border); }
.move-insight > div:first-child { display: flex; align-items: center; gap: .65rem; }
.move-insight > div > strong { font: 700 1.05rem var(--font-mono); }
.classification { padding: .3rem .55rem; color: #fff; background: #71865d; border-radius: 6px; font-size: .7rem; font-weight: 800; }
.classification.inaccuracy { background: #c18a2e; }
.classification.mistake { background: #c5643f; }
.classification.blunder { background: #a94332; }
.best-move-hint { display: flex; align-items: center; gap: .45rem; flex-wrap: wrap; color: var(--text-muted); font-size: .8rem; }
.best-move-badge { display: inline-flex; align-items: center; gap: .2rem; padding: .18rem .45rem; background: var(--surface-strong); border: 1px solid var(--border-subtle); border-radius: 6px; font-size: .84rem; font-weight: 700; color: var(--text); }
.best-move-figurine { font-size: .95rem; line-height: 1; }
.best-move-san { color: var(--accent); }
nav { display: grid; padding: .65rem; grid-template-columns: repeat(2, 1fr) 1.25fr repeat(2, 1fr); gap: .35rem; background: var(--surface-strong); border-top: 1px solid var(--border); }nav button { display: grid; min-height: 40px; place-items: center; color: var(--text); background: var(--surface); border: 1px solid var(--border); border-radius: 7px; cursor: pointer; }nav button:hover:not(:disabled) { color: var(--accent-ink); background: var(--accent); border-color: var(--accent); }nav button:disabled { opacity: .35; cursor: default; }nav > span { display: grid; place-items: center; color: var(--text-muted); font-size: .72rem; }
</style>
