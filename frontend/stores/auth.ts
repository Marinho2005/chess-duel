import { defineStore } from 'pinia'

export type AuthUser = {
  id: string
  email: string
  nickname: string
  rating: number
}

type AuthResponse = {
  token: string
  user: AuthUser
}

const tokenStorageKey = 'chess-duel:auth-token'

export const useAuthStore = defineStore('auth', () => {
  const token = ref<string | null>(null)
  const user = ref<AuthUser | null>(null)
  const error = ref('')
  const config = useRuntimeConfig()

  function restoreSession() {
    if (import.meta.client && !token.value) {
      token.value = sessionStorage.getItem(tokenStorageKey)
    }
  }

  function saveSession(response: AuthResponse) {
    token.value = response.token
    user.value = response.user
    error.value = ''

    if (import.meta.client) {
      sessionStorage.setItem(tokenStorageKey, response.token)
    }
  }

  async function register(email: string, password: string, nickname: string) {
    return authenticate('/api/users/register', { email, password, nickname })
  }

  async function logIn(email: string, password: string) {
    return authenticate('/api/users/log_in', { email, password })
  }

  async function authenticate(path: string, userData: Record<string, string>) {
    error.value = ''

    try {
      const response = await $fetch<AuthResponse>(path, {
        baseURL: config.public.api.baseURL,
        method: 'POST',
        body: { user: userData }
      })

      saveSession(response)
      return true
    } catch (requestError) {
      error.value = formatRequestError(requestError)
      return false
    }
  }

  async function fetchCurrentUser() {
    restoreSession()

    if (!token.value) {
      return false
    }

    try {
      const response = await $fetch<{ user: AuthUser }>('/api/users/me', {
        baseURL: config.public.api.baseURL,
        headers: { Authorization: `Bearer ${token.value}` }
      })

      user.value = response.user
      return true
    } catch {
      clearSession()
      return false
    }
  }

  async function logOut() {
    if (token.value) {
      try {
        await $fetch('/api/users/log_out', {
          baseURL: config.public.api.baseURL,
          method: 'DELETE',
          headers: { Authorization: `Bearer ${token.value}` }
        })
      } finally {
        clearSession()
      }
    }
  }

  function clearSession() {
    token.value = null
    user.value = null

    if (import.meta.client) {
      sessionStorage.removeItem(tokenStorageKey)
    }
  }

  function formatRequestError(requestError: unknown) {
    if (requestError && typeof requestError === 'object' && 'data' in requestError) {
      const data = (requestError as { data?: { error?: string; errors?: Record<string, string[]> } }).data

      if (data?.errors) {
        return Object.entries(data.errors)
          .flatMap(([field, messages]) => messages.map(message => `${field}: ${message}`))
          .join(', ')
      }

      if (data?.error === 'invalid_email_or_password') {
        return 'Email ou senha invalidos.'
      }
    }

    return 'Nao foi possivel autenticar.'
  }

  return { token, user, error, restoreSession, register, logIn, fetchCurrentUser, logOut }
})
