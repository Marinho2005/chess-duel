export default defineNuxtRouteMiddleware(async () => {
  if (!import.meta.client) return

  const auth = useAuthStore()
  auth.restoreSession()

  if (!auth.token || auth.isGuest) return

  const config = useRuntimeConfig()
  try {
    const data = await $fetch<{ active: boolean; game_id?: string }>('/api/games/active', {
      baseURL: config.public.api.baseURL,
      headers: { Authorization: `Bearer ${auth.token}` },
    })

    if (data?.active && data.game_id) {
      return navigateTo(`/game/${data.game_id}/live`)
    }
  } catch {
    // Ignore error and allow normal navigation
  }
})

