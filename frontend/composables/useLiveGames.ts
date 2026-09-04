import type { BroadcastLiveGame, ChessDuelLiveGame, LiveGame } from '~/types/live-games'

type GamesResponse<T> = { games: T[] }

export function useLiveGames(pollIntervalMs = 20_000) {
  const api = useApi()
  const broadcasts = ref<BroadcastLiveGame[]>([])
  const chessDuelGames = ref<ChessDuelLiveGame[]>([])
  const loading = ref(true)
  const broadcastError = ref(false)
  const chessDuelError = ref(false)
  let timer: ReturnType<typeof setInterval> | null = null

  const games = computed<LiveGame[]>(() => [
    ...broadcasts.value.map(game => ({ source: 'broadcast' as const, game })),
    ...chessDuelGames.value.map(game => ({ source: 'chessduel' as const, game })),
  ])
  const totalError = computed(() => broadcastError.value && chessDuelError.value)
  const partialError = computed(() => broadcastError.value !== chessDuelError.value)

  async function refresh() {
    const [broadcastResult, chessDuelResult] = await Promise.all([
      api.request<GamesResponse<BroadcastLiveGame>>('/api/broadcasts/live'),
      api.request<GamesResponse<ChessDuelLiveGame>>('/api/games/live'),
    ])

    broadcastError.value = Boolean(broadcastResult.error)
    chessDuelError.value = Boolean(chessDuelResult.error)
    if (broadcastResult.data) broadcasts.value = broadcastResult.data.games
    if (chessDuelResult.data) chessDuelGames.value = chessDuelResult.data.games
    loading.value = false
  }

  onMounted(() => {
    void refresh()
    timer = setInterval(() => void refresh(), pollIntervalMs)
  })
  onBeforeUnmount(() => {
    if (timer) clearInterval(timer)
    timer = null
  })

  return { broadcasts, chessDuelGames, games, loading, totalError, partialError, refresh }
}
