import { defineStore } from 'pinia'

export type AuthUser = {
  id: string
  email: string
  nickname: string
  country: string | null
  country_code: string | null
  avatar_url: string | null
  rating: number
  inserted_at: string
}

export type GuestIdentity = {
  id: string
  nickname: string
  guest: true
}

type AuthResponse = {
  token: string
  user: AuthUser
}

type RegistrationResponse = {
  status: 'pending_confirmation'
  message: string
}

type GuestResponse = {
  token: string
  guest: GuestIdentity
  expires_in: number
}

const tokenStorageKey = 'chess-duel:auth-token'

export const useAuthStore = defineStore('auth', () => {
  const token = ref<string | null>(null)
  const user = ref<AuthUser | null>(null)
  const guest = ref<GuestIdentity | null>(null)
  const error = ref('')
  const config = useRuntimeConfig()
  const isGuest = computed(() => guest.value !== null)
  const identityId = computed(() => guest.value?.id || user.value?.id || null)

  function restoreSession() {
    if (import.meta.client && !token.value) {
      token.value = sessionStorage.getItem(tokenStorageKey)
    }
  }

  function saveSession(response: AuthResponse) {
    token.value = response.token
    user.value = response.user
    guest.value = null
    error.value = ''

    if (import.meta.client) {
      sessionStorage.setItem(tokenStorageKey, response.token)
    }
  }

  async function register(email: string, password: string, nickname: string) {
    error.value = ''

    try {
      const response = await $fetch<RegistrationResponse>('/api/users/register', {
        baseURL: config.public.api.baseURL,
        method: 'POST',
        body: { user: { email, password, nickname } }
      })

      return response.status === 'pending_confirmation'
    } catch (requestError) {
      error.value = formatRequestError(requestError)
      return false
    }
  }

  async function logIn(email: string, password: string) {
    return authenticate('/api/users/log_in', { email, password })
  }

  async function startGuestSession() {
    error.value = ''

    try {
      const response = await $fetch<GuestResponse>('/api/guests/session', {
        baseURL: config.public.api.baseURL,
        method: 'POST'
      })

      token.value = response.token
      guest.value = response.guest
      user.value = null

      if (import.meta.client) {
        sessionStorage.removeItem(tokenStorageKey)
      }

      return true
    } catch (requestError) {
      error.value = formatRequestError(requestError)
      return false
    }
  }

  async function completeOAuth(tokenValue: string) {
    if (!tokenValue) return false

    token.value = tokenValue
    error.value = ''

    if (import.meta.client) {
      sessionStorage.setItem(tokenStorageKey, tokenValue)
    }

    return fetchCurrentUser()
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
    if (guest.value && token.value) return true

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
    if (guest.value) {
      clearSession()
      return
    }

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

  async function updateProfile(nickname: string, countryCode: string, country: string) {
    error.value = ''

    if (!token.value) {
      return false
    }

    try {
      const response = await $fetch<{ user: AuthUser }>('/api/users/me', {
        baseURL: config.public.api.baseURL,
        method: 'PATCH',
        headers: { Authorization: `Bearer ${token.value}` },
        body: { user: { nickname, country_code: countryCode || null, country: country || null } }
      })

      user.value = response.user
      return true
    } catch (requestError) {
      const status = (requestError as { status?: number; statusCode?: number }).statusCode
        || (requestError as { status?: number }).status

      if (status === 401) {
        clearSession()
      }

      error.value = formatRequestError(requestError)
      return false
    }
  }

  async function updateAvatar(file: File) {
    error.value = ''

    if (!token.value) return false

    const body = new FormData()
    body.append('avatar', file)

    try {
      const response = await $fetch<{ user: AuthUser }>('/api/users/me/avatar', {
        baseURL: config.public.api.baseURL,
        method: 'POST',
        headers: { Authorization: `Bearer ${token.value}` },
        body
      })

      user.value = response.user
      return true
    } catch (requestError) {
      const data = (requestError as { data?: { error?: string } }).data
      const messages: Record<string, string> = {
        avatar_too_large: 'A imagem deve ter no maximo 2 MB.',
        invalid_avatar_format: 'Escolha uma imagem JPEG, PNG ou WebP valida.'
      }
      error.value = messages[data?.error || ''] || 'Nao foi possivel enviar a foto.'
      return false
    }
  }

  function clearSession() {
    token.value = null
    user.value = null
    guest.value = null

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

      if (data?.error === 'email_not_confirmed') {
        return 'Confirme seu e-mail antes de entrar.'
      }
    }

    return 'Nao foi possivel concluir a solicitacao.'
  }

  return { token, user, guest, isGuest, identityId, error, restoreSession, register, logIn, startGuestSession, completeOAuth, fetchCurrentUser, updateProfile, updateAvatar, logOut }
})
