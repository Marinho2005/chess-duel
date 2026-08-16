interface ApiResult<T = unknown> {
  data: T | null
  error: string | null
  status: number | null
}

type RequestOptions = Record<string, unknown>

export function useApi() {
  const config = useRuntimeConfig()
  const baseURL = config.public.api.baseURL

  async function request<T = unknown>(
    path: string,
    options: RequestOptions = {},
  ): Promise<ApiResult<T>> {
    try {
      const result = await $fetch<T>(path, {
        baseURL,
        ...options,
      })
      return { data: result as T, error: null, status: 200 }
    } catch (err: unknown) {
      const message =
        err && typeof err === 'object' && 'message' in err
          ? String((err as { message?: unknown }).message)
          : 'Erro desconhecido'
      const status =
        err && typeof err === 'object' && 'statusCode' in err
          ? Number((err as { statusCode?: unknown }).statusCode)
          : null
      return { data: null, error: message, status }
    }
  }

  return { request, baseURL }
}
