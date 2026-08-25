# ChessDuel ♟️

**ChessDuel** é um SaaS de xadrez em tempo real — um projeto pessoal em desenvolvimento, inspirado em chess.com e lichess. A ideia é construir, do zero e com calma, um jogo online onde você desafia outros jogadores, joga em tempo real e acompanha o ranking. Comecei com o esqueleto: banco + cache no Docker, um backend Phoenix (API only) e um frontend Nuxt como SPA que já conversam entre si.

> **Status: fase inicial / aprendizado.** A lógica de xadrez ainda não existe — o foco atual é o ambiente rodando e a comunicação frontend ↔ backend funcionando.

## Badges

![Elixir](https://img.shields.io/badge/Elixir-4B275F?style=for-the-badge&logo=elixir&logoColor=white)
![Phoenix](https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white)
![Vue](https://img.shields.io/badge/Vue%2FNuxt-00C58E?style=for-the-badge&logo=vue.js&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)

## Stack

| Camada            | Tecnologia                                                              |
|-------------------|-------------------------------------------------------------------------|
| Backend           | Elixir + Phoenix (modo API)                                             |
| Frontend          | Nuxt 3 (Vue 3, Composition API, TypeScript, Pinia)                      |
| Banco de dados    | PostgreSQL 18                                                           |
| Cache / estado efêmero | Valkey (fork open source, compatível com Redis)                     |
| Orquestração local| Docker Compose                                                          |

## Status e roadmap

Projeto pessoal em fase inicial de aprendizado. Nada de lógica de jogo ainda — primeiro quero o esqueleto sólido e a comunicação funcionando. Roadmap breve:

- **Fase 1 — Core do jogo em tempo real** *(em andamento)*: partidas via WebSocket (Phoenix Channels), board state, validação de lances
- **Fase 2 — Contas e ranking**: autenticação, perfis, histórico de partidas
- **Fase 3 — Matchmaking**: fila de espera e pareamento automático
- **Fase 4 — Observabilidade e infra**: Traefik, Oban, Sentry, métricas (Prometheus/Grafana) — quando fizer sentido

## Pré-requisitos

- **Elixir / Erlang** — via [asdf](https://asdf-vm.com/). Este projeto usa Elixir `1.18.x` com Erlang/OTP `27` (defina via `.tool-versions` na raiz do backend).
- **Node.js** >= 20 (para o Nuxt 3)
- **Docker** + Docker Compose v2 (para Postgres e Valkey)
- **gh CLI** (opcional, para operações no GitHub)

## Como rodar

### 1. Subir a infra (Postgres + Valkey)

```bash
cp .env.example .env   # ajuste as credenciais se quiser
docker compose up -d
docker compose ps      # confira que os dois serviços estão healthy
```

### 2. Rodar o backend (Phoenix)

```bash
cd backend
set -a && source ../.env && set +a
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

O backend sobe em `http://localhost:4000`. Health check:

```bash
curl http://localhost:4000/api/health
# => {"status":"ok"}
```

### 3. Rodar o frontend (Nuxt) — em outro terminal

```bash
cd frontend
npm install
npm run dev
```

Acesse:

- **Frontend:** <http://localhost:3000> — a página inicial chama o `/api/health` do backend e mostra o status da comunicação
- **Backend health check:** <http://localhost:4000/api/health>

### Portas

| Serviço  | Porta |
|----------|-------|
| Postgres | 5432  |
| Valkey   | 6379  |
| Backend  | 4000  |
| Frontend | 3000  |

## Estrutura do projeto

```
chess_duel/
├── docker-compose.yml        # Postgres + Valkey (infra local)
├── .env.example              # modelo de variáveis de ambiente
├── backend/                  # Phoenix (API only)
│   └── lib/chess_duel_backend/
│       ├── games/            # contexto Games (estrutura vazia)
│       └── web/
│           ├── channels/     # UserSocket + GamesChannel (WebSocket base)
│           └── controllers/  # HealthController (health check)
└── frontend/                 # Nuxt 3 SPA
    ├── composables/          # useApi.ts (fetch wrapper)
    ├── pages/                # index.vue
    └── stores/               # Pinia
```

## Variáveis de ambiente

Existe um `.env.example` na raiz com as variáveis usadas pelo Docker Compose, backend e frontend (`DATABASE_URL`/`DB_*`, `VALKEY_URL`, `NUXT_PUBLIC_API_URL`, etc.).

Copie para `.env` e edite conforme sua máquina. ⚠️ **Nunca commite o `.env` real** — ele está no `.gitignore`. Apenas o `.env.example` (sem segredos) vai para o repositório.

Para testar o login social, crie uma aplicação OAuth no Google Cloud Console e preencha as credenciais indicadas no `.env.example`. Use este callback no ambiente local:

- Google: `http://localhost:4000/auth/google/callback`

## Licença

Sem licença definida por enquanto. Sugestão: **MIT** quando decidir publicar — basta criar um arquivo `LICENSE` no futuro.
