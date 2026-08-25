export function resolveAvatarUrl(value: string | null | undefined, apiBaseUrl: string) {
  if (!value) return null
  if (/^https?:\/\//i.test(value)) return value
  return `${apiBaseUrl.replace(/\/$/, '')}${value}`
}
