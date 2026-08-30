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

## Como rodar com Docker Compose (recomendado)

O único pré-requisito é ter Docker com Compose v2. Na primeira execução:

```bash
cp .env.example .env
# Preencha as credenciais dos provedores sociais que quiser usar.
docker compose up --build
```

O Compose constrói e inicia PostgreSQL, Valkey, Phoenix e Nuxt. As migrations são
aplicadas automaticamente antes de o backend iniciar. Depois, acesse:

- **Frontend:** <http://localhost:3000>
- **Backend/health check:** <http://localhost:4000/api/health>

O código de `backend/` e `frontend/` é montado nos containers. Alterações no Nuxt
são refletidas pelo Vite; alterações no Phoenix são recompiladas na próxima
requisição. Dependências (`node_modules`, `deps` e `_build`) ficam isoladas em
volumes Docker.

Comandos úteis:

```bash
docker compose ps
docker compose logs -f backend frontend
docker compose exec backend mix ecto.migrate
docker compose exec -e MIX_ENV=test backend mix test
docker compose down
```

## Como rodar localmente (alternativa)

Neste modo, é necessário ter Elixir `1.18.x`/OTP 27, Node.js 20 ou superior, Stockfish e
Docker Compose instalados. Como o backend roda no host, ajuste no `.env`:

```env
DB_HOST=localhost
VALKEY_URL=redis://localhost:6379
NUXT_PUBLIC_API_URL=http://localhost:4000
```

Suba somente a infraestrutura:

```bash
cp .env.example .env
# Faça os ajustes acima e preencha as credenciais desejadas.
docker compose up -d postgres valkey
```

### Backend (Phoenix)

```bash
cd backend
set -a && source ../.env && set +a
mix deps.get
cd priv/chess_validator && npm install && cd ../..
mix ecto.create
mix ecto.migrate
mix phx.server
```

O executável do Stockfish é detectado automaticamente no `PATH`. Se estiver em
outro local, defina `STOCKFISH_PATH` (por exemplo, `/usr/games/stockfish`). No
Docker Compose ele já é instalado na imagem do backend. As análises pós-partida
são executadas de forma assíncrona pela fila `analysis` do Oban.

### Força dos bots

O container usa Stockfish 15.1. As opções UCI disponíveis incluem `Skill Level`
(0–20), `UCI_LimitStrength`, `UCI_Elo` (1350–2850), `Threads` e `Hash`. Como o
limite UCI não alcança os níveis iniciantes, o catálogo aplica este mapeamento:

| Bot | Força exibida | Configuração Stockfish |
|---|---:|---|
| Clark | 800 | `Skill Level 0`, busca de 70 ms |
| Jonathan | 1200 | `Skill Level 3`, busca de 110 ms |
| Renan | 1600 | `UCI_LimitStrength=true`, `UCI_Elo=1600`, busca de 180 ms |
| Boris | 2400 | `UCI_LimitStrength=true`, `UCI_Elo=2400`, busca de 350 ms |
| Terminator | 2800 | `UCI_LimitStrength=true`, `UCI_Elo=2800`, busca de 600 ms |

Esses números representam níveis aproximados de produto, não uma certificação
de Elo. Toda jogada calculada retorna ao `GameServer`, que continua responsável
por validar o lance, descontar o relógio e finalizar a partida.

O backend sobe em `http://localhost:4000`. Health check:

```bash
curl http://localhost:4000/api/health
# => {"status":"ok"}
```

### Frontend (Nuxt) — em outro terminal

```bash
cd frontend
npm install
npm run dev
```

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
├── docker-compose.yml        # Ambiente completo de desenvolvimento
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

Existe um `.env.example` na raiz com as variáveis usadas pelo Docker Compose, backend e frontend (`DATABASE_URL`/`DB_*`, `VALKEY_URL`, `NUXT_PUBLIC_API_URL`, etc.). Os valores padrão usam os nomes internos `postgres` e `valkey`, próprios do Compose. Para executar o backend diretamente no host, altere esses hosts para `localhost`.

Copie para `.env` e edite conforme sua máquina. ⚠️ **Nunca commite o `.env` real** — ele está no `.gitignore`. Apenas o `.env.example` (sem segredos) vai para o repositório.

Para testar o login social, crie aplicações OAuth nos painéis dos provedores e
preencha as credenciais indicadas no `.env.example`. Os secrets ficam somente no
backend. Use estes callbacks no ambiente local:

- Google: `http://localhost:4000/auth/google/callback`
- Discord: `http://localhost:4000/auth/discord/callback`
- GitHub: `http://localhost:4000/auth/github/callback`

Variáveis necessárias por provedor:

- Google: `GOOGLE_CLIENT_ID` e `GOOGLE_CLIENT_SECRET`
- Discord: `DISCORD_CLIENT_ID` e `DISCORD_CLIENT_SECRET`
- GitHub: `GITHUB_CLIENT_ID` e `GITHUB_CLIENT_SECRET`

## Licença

Sem licença definida por enquanto. Sugestão: **MIT** quando decidir publicar — basta criar um arquivo `LICENSE` no futuro.
