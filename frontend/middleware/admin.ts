export default defineNuxtRouteMiddleware(async () => {
  if (!import.meta.client) return
  const auth = useAuthStore()
  auth.restoreSession()
  if (!auth.token || auth.isGuest || !(await auth.fetchCurrentUser())) return navigateTo('/?session=expired')
  if (auth.user?.role !== 'admin' || auth.user.account_status !== 'active') {
    return abortNavigation(createError({ statusCode: 403, statusMessage: 'Acesso exclusivo para administradores.' }))
  }
})
