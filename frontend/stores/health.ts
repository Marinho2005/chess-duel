import { defineStore } from 'pinia'

interface HealthState {
  status: 'idle' | 'loading' | 'ok' | 'error'
  message: string
}

export const useHealthStore = defineStore('health', {
  state: (): HealthState => ({
    status: 'idle',
    message: '',
  }),
  actions: {
    setLoading() {
      this.status = 'loading'
      this.message = 'Verificando o backend...'
    },
    setOk() {
      this.status = 'ok'
      this.message = 'Backend online'
    },
    setError(message: string) {
      this.status = 'error'
      this.message = message
    },
  },
})
