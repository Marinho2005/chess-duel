export type AppTheme = 'navy' | 'black' | 'white'

const storageKey = 'chess-duel:theme'
const validThemes: AppTheme[] = ['navy', 'black', 'white']

export function useTheme() {
  const theme = useState<AppTheme>('app-theme', () => 'white')

  function applyTheme(value: AppTheme) {
    theme.value = value
    if (!import.meta.client) return
    document.documentElement.dataset.theme = value
    localStorage.setItem(storageKey, value)
  }

  function restoreTheme() {
    if (!import.meta.client) return
    const saved = localStorage.getItem(storageKey) as AppTheme | null
    applyTheme(saved && validThemes.includes(saved) ? saved : 'white')
  }

  return { theme: readonly(theme), applyTheme, restoreTheme }
}
