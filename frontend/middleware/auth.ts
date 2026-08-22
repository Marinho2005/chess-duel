export default defineNuxtRouteMiddleware(async () => {
  if (!import.meta.client) return

  const auth = useAuthStore()
  auth.restoreSession()

  if (!auth.token || !(await auth.fetchCurrentUser())) {
    return navigateTo('/?session=expired')
  }
})
