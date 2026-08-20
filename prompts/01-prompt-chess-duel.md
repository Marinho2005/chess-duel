# Prompt: Setup inicial do projeto ChessDuel

Quero criar o esqueleto inicial de um projeto chamado **ChessDuel** — um SaaS de xadrez em tempo real (concorrente do chess.com/lichess). Este é apenas o setup base: sem lógica de jogo ainda, só a fundação rodando.

## Stack

- **Backend:** Elixir + Phoenix (modo API, sem HTML/assets — `--no-html --no-assets`)
- **Frontend:** Nuxt 3 (Vue 3, Composition API) como SPA separada, consumindo o backend via WebSocket/REST
- **Banco relacional:** PostgreSQL 18
- **Cache/estado efêmero:** Valkey (fork open source do Redis, compatível)
- **Orquestração local:** Docker Compose

## O que preciso que você gere

### 1. Backend (`/backend`)
- Projeto Phoenix gerado com `mix phx.new chess_duel_backend --no-html --no-assets`
- Configurar conexão com Postgres via variáveis de ambiente (não hardcoded), lendo de `DATABASE_URL` ou host/porta/user/senha separados
- Configurar conexão com Valkey (usar a lib `redix`, compatível com Valkey)
- Adicionar suporte a CORS (lib `cors_plug`) liberado para o frontend rodar em `localhost:3000` (dev)
- Criar um contexto `Games` vazio (sem lógica ainda, só a estrutura: `lib/chess_duel_backend/games.ex`)
- Adicionar um endpoint de health check simples: `GET /api/health` retornando `{"status": "ok"}`
- Configurar Phoenix Channels básico (`UserSocket`, sem lógica de jogo ainda) só pra confirmar que WebSocket conecta

### 2. Frontend (`/frontend`)
- Projeto Nuxt 3 criado via `npx nuxi init frontend`
- TypeScript habilitado
- Pinia configurado como state management
- Estrutura de pastas: `components/`, `composables/`, `stores/`, `pages/`
- Criar um composable `useApi.ts` simples para chamar o backend (fetch wrapper com base URL vinda de variável de ambiente `NUXT_PUBLIC_API_URL`)
- Página inicial (`pages/index.vue`) que faz uma chamada pro endpoint `/api/health` do backend e mostra o status na tela (só pra validar que a comunicação frontend↔backend funciona)
- Sem SSR na estrutura de rotas de jogo ainda (não precisa criar `/play/:id` agora, é só o setup base)

### 3. Docker Compose (raiz do projeto)
Arquivo `docker-compose.yml` com:
- Serviço `postgres` (imagem `postgres:18`, variáveis de ambiente para user/senha/db, volume nomeado para persistência, porta `5432:5432`)
- Serviço `valkey` (imagem oficial `valkey/valkey:latest`, porta `6379:6379`)
- **Não** incluir o backend nem o frontend como serviços no compose ainda — eles vão rodar localmente via `mix phx.server` e `npm run dev` durante o desenvolvimento, só a infra (banco + cache) fica no Docker por enquanto
- Incluir um `.env.example` na raiz com as variáveis necessárias (senha do postgres, etc)

### 4. Documentação
- Um `README.md` na raiz explicando:
  - Como subir a infra (`docker compose up -d`)
  - Como rodar o backend (`cd backend && mix deps.get && mix ecto.create && mix phx.server`)
  - Como rodar o frontend (`cd frontend && npm install && npm run dev`)
  - Portas usadas por cada serviço

## O que NÃO fazer agora (importante)

- Não configurar Traefik, Oban, Sentry, Prometheus, Grafana, MinIO, ou qualquer outra ferramenta de observabilidade/infra avançada — isso é para fases futuras
- Não implementar lógica de xadrez, validação de lance, ou GenServer de partida ainda — isso vem depois
- Não configurar autenticação/login ainda
- Não criar CI/CD ainda
- Manter tudo o mais simples e enxuto possível — o objetivo desta etapa é só ter o ambiente rodando localmente, backend e frontend conversando entre si, e a infra de banco/cache disponível via Docker

## Critério de sucesso

Ao final, eu devo conseguir:
1. Rodar `docker compose up -d` e ter Postgres + Valkey no ar
2. Rodar o backend Phoenix localmente e acessar `http://localhost:4000/api/health` retornando `{"status": "ok"}`
3. Rodar o frontend Nuxt localmente e ver, na página inicial, a confirmação de que ele conseguiu chamar o backend com sucesso
