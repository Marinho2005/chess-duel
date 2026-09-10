interface ApiResult<T = unknown> {
  data: T | null
  error: string | null
  status: number | null
}

type RequestOptions = Record<string, unknown> & { authenticated?: boolean }

export function useApi() {
  const config = useRuntimeConfig()
  const baseURL = config.public.api.baseURL

  async function request<T = unknown>(
    path: string,
    options: RequestOptions = {},
  ): Promise<ApiResult<T>> {
    const { authenticated, ...fetchOptions } = options
    const auth = useAuthStore()
    if (authenticated) {
      auth.restoreSession()
      if (!auth.token || auth.isGuest) return { data: null, error: 'Entre com sua conta.', status: 401 }
      fetchOptions.headers = { ...(options.headers as Record<string, string> || {}), Authorization: `Bearer ${auth.token}` }
    }
    try {
      const result = await $fetch<T>(path, {
        baseURL,
        ...fetchOptions,
      })
      return { data: result as T, error: null, status: 200 }
    } catch (err: unknown) {
      const body = (err as { data?: { error?: string; message?: string; errors?: Record<string, string[]> } })?.data
      if (body?.error && ['account_banned', 'account_suspended'].includes(body.error)) {
        auth.handleAccountBlock(body.error, body.message)
        if (import.meta.client) await navigateTo('/?session=blocked')
      }
      const errorLabels: Record<string, string> = {
        admin_required: 'Acesso exclusivo para administradores.',
        self_moderation: 'Você não pode moderar a própria conta.',
        invalid_transition: 'O estado da conta mudou. Atualize os dados antes de tentar novamente.',
        not_found: 'Registro não encontrado.',
        invalid_filters: 'Confira os filtros informados.',
      }
      const validation = body?.errors && Object.values(body.errors).flat().join(', ')
      const message = validation || body?.message || errorLabels[body?.error || ''] || (
        err && typeof err === 'object' && 'message' in err
          ? String((err as { message?: unknown }).message)
          : 'Erro desconhecido')
      const status =
        err && typeof err === 'object' && 'statusCode' in err
          ? Number((err as { statusCode?: unknown }).statusCode)
          : null
      return { data: null, error: message, status }
    }
  }

  return { request, baseURL }
}
