# Painel administrativo

O painel usa a autenticação existente e fica em `/admin`. Não há conta administrativa padrão nem senha criada automaticamente.

## Primeiro acesso

1. Cadastre e confirme uma conta normalmente.
2. Consulte o `id` da sua conta na resposta autenticada de `GET /api/users/me` (aba Network do navegador).
3. No terminal do operador, conceda a role:

```sh
docker compose exec backend mix admin.grant UUID_DA_CONTA
```

Na execução local, dentro de `backend/`, use `mix admin.grant UUID_DA_CONTA`.
A tarefa só aceita contas confirmadas e ativas. Ela é idempotente e não cria usuários.
Não existe endpoint de concessão ou remoção de roles.

4. Atualize a página e abra `http://localhost:3000/admin`. O header passa a oferecer Administração.

## Migration

`backend/priv/repo/migrations/20260907120000_add_account_moderation.exs` adiciona:

- `users.role`: `user` (padrão) ou `admin`;
- `users.account_status`: `active` (padrão), `suspended` ou `banned`;
- `users.suspended_until`, em UTC, com precisão de microssegundos;
- `moderation_actions`, com UUIDs, FKs restritivas, motivo, ação, prazo e timestamp;
- constraints de valores válidos, motivo não vazio, suspensão com prazo e proibição de automoderação;
- índices para status, auditoria e ordenação de partidas.

O Compose executa migrations na inicialização do backend. Para aplicar sem reiniciar:

```sh
docker compose exec backend mix ecto.migrate
```

## API

Todas as rotas abaixo exigem bearer de uma conta ativa com role `admin`. Respostas administrativas têm `Cache-Control: no-store`.

| Método | Endpoint | Uso |
|---|---|---|
| GET | `/api/admin/dashboard` | Contadores reais de usuários, partidas e jobs |
| GET | `/api/admin/users` | `q`, `status`, `page`, `per_page` |
| GET | `/api/admin/users/:id` | Perfil administrativo, resumo agregado de partidas e últimas 50 ações |
| POST | `/api/admin/users/:id/suspend` | `reason` e `suspended_until` ISO 8601 futuro |
| POST | `/api/admin/users/:id/ban` | `reason` obrigatório |
| POST | `/api/admin/users/:id/reactivate` | `reason` obrigatório |
| GET | `/api/admin/games` | `q`, `status`, `type`, `result`, `from`, `to`, `page`, `per_page` |
| GET | `/api/admin/games/:id` | Registro, jogadores, posição, lances e status da análise |
| GET | `/api/admin/system` | Conectividade do banco e estados de jobs de análise |

Paginação padrão: 20 registros; máximo: 50 por página. `q` busca apelido/e-mail em usuários e apelido/identificador público em partidas. `status` de usuários considera suspensões expiradas como ativas. Tipos de partida: `human` e `bot`. Datas `from`/`to` usam `YYYY-MM-DD` e incluem os dias informados, em UTC, pela criação da partida.

`:id` é sempre o UUID do registro. O `game_id` público das partidas ao vivo não é usado como chave do detalhe administrativo.

Erros: `401` para autenticação ausente/inválida; `403` para falta de role ou conta bloqueada; `404` para registros inexistentes/UUID inválido; `409` para automoderação ou transição incompatível; `422` para payload inválido; `400` para filtros inválidos.

## Decisões de segurança e operação

- `AccountAccess` centraliza o status efetivo. Quando `suspended_until` expira, não é necessário atualizar a linha nem executar cron. O prazo original permanece no registro até outra ação; a auditoria permanece sempre.
- `UserAuth` verifica a conta atual no banco, inclusive com tokens emitidos anteriormente e na autenticação opcional. Login local, OAuth e conexão de socket também verificam o bloqueio.
- Suspender/banir transmite `disconnect` ao tópico `users_socket:<id>` após o commit. `ChannelAccess`, integrado ao macro existente de Channels, revalida a conta no join e nos eventos de entrada; isso cobre sockets antigos e a corrida entre autenticação do transporte e inscrição no tópico.
- A revalidação de Channels faz uma leitura de banco por evento autenticado. Não adiciona persistência síncrona ao GameServer. Convidados mantêm seu fluxo separado.
- Tokens não são apagados pela moderação: permanecem bloqueados durante a restrição e podem voltar a funcionar após expiração/reativação, se ainda válidos.
- A moderação bloqueia as linhas do administrador e do alvo em ordem estável. A autorização é revalidada dentro da transação, que grava status e auditoria juntos. Não há automoderação, exclusão de contas nem alteração de rating/resultado.
- Cadastro, OAuth e edição de perfil não aceitam os campos administrativos. Serialização administrativa é explícita e não retorna hashes, tokens, identidades OAuth ou data de nascimento.
- O painel usa o `useApi`, store Pinia, header, seletor de temas, tokens CSS e componentes de perfil existentes. O middleware frontend controla a navegação; o backend é a autoridade.

## Significado das métricas

- `active_games`: processos no servidor atual em `in_progress`, incluindo contas, bots e convidados. É uma observação, não um contador distribuído.
- `games_today` e `bot_games_today`: registros criados no dia UTC. Convidados não persistem partidas e ficam fora desses totais.
- `pending_analysis_jobs`: jobs do worker `GameAnalysis.Job` em `available`, `scheduled` ou `retryable`.
- `failed_analysis_jobs`: jobs em `discarded` (falha definitiva), não o status `failed` de `game_analyses`, que pode anteceder uma nova tentativa.
- Sistema mostra concorrência configurada, sem afirmar que o Stockfish está saudável. Nenhum comando ou controle de processo é exposto.
- Ratings da partida mostram snapshots quando existentes; valores atuais e força do bot são identificados separadamente. O detalhe é somente leitura e pode refletir o atraso normal da persistência assíncrona.

## Arquivos da implementação

Novos no backend: `admin.ex`, `accounts/account_access.ex`, `accounts/moderation_action.ex`, `chess_duel_backend_web/channel_access.ex`, controllers `admin_controller.ex`/`admin_json.ex`, tarefa `mix/tasks/admin.grant.ex`, migration e `test/chess_duel_backend_web/admin_controller_test.exs`.

Alterados no backend: `accounts/user.ex`, `chess_duel_backend_web.ex`, `user_auth.ex`, `router.ex`, `channels/user_socket.ex` e controllers `auth_controller.ex`, `user_session_controller.ex`, `user_json.ex`.

Novos no frontend: `layouts/admin.vue`, `middleware/admin.ts`, `types/admin.ts`, `utils/admin.ts`, `components/admin/{Pagination,ModerationDialog}.vue`, as seis páginas sob `pages/admin/` e `tests/admin.test.ts`.

Alterados no frontend: `composables/useApi.ts`, `stores/auth.ts`, `components/navigation/AppHeader.vue` e `pages/index.vue`. Roadmap atualizado em `AGENTS.md`.

## Validação desta entrega

- Backend: 147 testes passaram no container, com Stockfish disponível; 39 testes focados em administração, autenticação, OAuth e sockets também passaram localmente.
- Frontend: typecheck aprovado; 31/32 testes passaram fora do sandbox, incluindo os quatro testes novos de moderação.
- Falha frontend restante: `tests/live-games.test.ts` exige a antiga URL de partidas por torneio, enquanto a página existente usa partidas por rodada. Esses arquivos não foram alterados nesta tarefa.
- Build Nuxt de produção aprovado usando a API `loadNuxt`/`buildNuxt` e saída temporária. O comando padrão encontrou `EACCES` no diretório `.output` preexistente, pertencente a outro usuário.
- `mix format` executado nos arquivos Elixir alterados. O projeto não oferece script separado de lint frontend.
- Página inicial verificada em navegador após corrigir a tag Vue inválida. A verificação administrativa autenticada completa ficou pendente quando Docker/PostgreSQL ficaram indisponíveis na sessão.
