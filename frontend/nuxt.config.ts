export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  devtools: { enabled: true },

  modules: ['@pinia/nuxt'],

  css: [
    '@lichess-org/chessground/assets/chessground.base.css',
    '@lichess-org/chessground/assets/chessground.brown.css',
    '@lichess-org/chessground/assets/chessground.cburnett.css',
  ],

  typescript: {
    strict: true,
    typeCheck: false,
  },

  ssr: false,

  runtimeConfig: {
    public: {
      api: {
        baseURL: process.env.NUXT_PUBLIC_API_URL || 'http://localhost:4000',
      },
    },
  },

  app: {
    head: {
      title: 'ChessDuel',
      link: [
        { rel: 'icon', type: 'image/png', href: '/favicon.png' },
      ],
      meta: [
        { charset: 'utf-8' },
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        { name: 'description', content: 'ChessDuel — xadrez em tempo real' },
      ],
    },
  },
})
