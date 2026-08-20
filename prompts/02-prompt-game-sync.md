# Prompt: Implementar sincronização de partida em tempo real (Channel + GenServer)

Este é o próximo passo do backend ChessDuel. O objetivo AGORA é apenas provar que dois clientes conseguem se conectar à mesma partida e trocar mensagens de "lance" em tempo real, sincronizadas pelo servidor. **NÃO valide se o lance é legal segundo as regras do xadrez** — isso vem em uma etapa futura separada. Por enquanto, qualquer lance enviado deve ser aceito e retransmitido.

## Contexto atual do projeto

- Backend Phoenix (modo API, `--no-html --no-assets`) em `backend/`
- Já existe um contexto `Games` vazio (`lib/chess_duel_backend/games.ex`)
- Já existe um `UserSocket` básico configurado
- Postgres e Valkey rodando via Docker Compose

## O que preciso que você implemente

### 1. Schema e migration de `Game`

No contexto `Games`, criar o schema `Game` com os campos:
- `id` (padrão, UUID se possível, para servir como identificador da partida na URL/tópico do canal)
- `status` (string, default `"waiting"` — valores possíveis: `waiting`, `in_progress`, `finished`)
- `board_state` (string ou map/jsonb — representar o estado do tabuleiro; pode ser uma string FEN simples ou uma lista de lances já feitos, o que for mais simples de implementar agora)
- `current_turn` (string, `"white"` ou `"black"`, default `"white"`)
- `inserted_at` / `updated_at` (timestamps padrão)

Adicionar ao contexto `Games` as funções básicas: `create_game/1`, `get_game!/1`, `update_game/2`.

### 2. GenServer por partida

Criar `lib/chess_duel_backend/games/game_server.ex`:
- Um `GenServer` que representa o estado **em memória** de uma partida em andamento (não confundir com o schema do banco, que é a persistência — o GenServer é o estado "vivo" enquanto os jogadores estão jogando)
- Deve ser iniciado dinamicamente por `game_id`, usando um `Registry` (criar `ChessDuelBackend.GameRegistry`) para conseguir localizar o processo correto a partir do `game_id`
- Deve ser supervisionado por um `DynamicSupervisor` (criar `ChessDuelBackend.GameSupervisor`), registrado na árvore de supervisão da `Application`
- Estado do GenServer: `game_id`, lista de lances feitos (`moves`, lista de mapas `%{from: ..., to: ..., player: ...}`), `current_turn`
- Funções públicas do GenServer: `start_or_get(game_id)` (inicia se não existir, retorna o pid se já existir), `make_move(game_id, from, to, player)` (adiciona o lance à lista, alterna o turno, retorna `{:ok, new_state}`), `get_state(game_id)`

### 3. Phoenix Channel de partida

Criar `lib/chess_duel_backend_web/channels/game_channel.ex`:
- Tópico no formato `"game:<game_id>"`
- `join/3`: quando um cliente entra no tópico, chamar `GameServer.start_or_get(game_id)` para garantir que o processo da partida existe, e responder com o estado atual da partida (lista de lances, turno atual) para sincronizar o cliente que acabou de entrar
- Handler `handle_in("move", %{"from" => from, "to" => to}, socket)`: chama `GameServer.make_move/4` passando o `game_id` do tópico e um identificador do jogador (pode ser algo simples por enquanto, tipo um `player_id` recebido nos params de conexão do socket — não precisa de autenticação real ainda), e faz `broadcast!` do lance para todos no tópico (`"move_made"`, com `from`, `to`, `player`, e o novo `current_turn`)
- Registrar o `GameChannel` no `UserSocket` (`channel "game:*", ChessDuelBackendWeb.GameChannel`)

### 4. Registrar o Registry e o DynamicSupervisor na Application

Editar `lib/chess_duel_backend/application.ex` para adicionar `{Registry, keys: :unique, name: ChessDuelBackend.GameRegistry}` e `{DynamicSupervisor, name: ChessDuelBackend.GameSupervisor, strategy: :one_for_one}` na lista de children supervisionados.

### 5. Página de teste simples no frontend (Nuxt)

Não precisa ser bonita nem definitiva — só uma página temporária em `frontend/pages/test-game.vue` que:
- Conecta ao WebSocket do backend usando a lib `phoenix` (adicionar como dependência do frontend se ainda não estiver: `npm install phoenix`)
- Entra no canal `game:test-game-1` (game_id fixo, só para teste manual)
- Tem um formulário simples com dois campos de texto (`from` e `to`) e um botão "Enviar lance", que dispara `channel.push("move", { from, to })`
- Mostra em tela, em tempo real, a lista de lances recebidos via evento `"move_made"`

O objetivo desta página é permitir abrir DUAS abas do navegador nessa mesma rota e confirmar visualmente que um lance enviado em uma aba aparece na outra em tempo real.

## Critério de sucesso

1. `mix phx.server` sobe sem erro
2. Abrir `http://localhost:3000/test-game` em duas abas diferentes do navegador
3. Enviar um lance na aba 1 (ex: from "e2", to "e4")
4. O lance aparece automaticamente na aba 2, sem precisar recarregar a página
5. Se eu fechar e reabrir uma aba (reconectar ao mesmo `game_id`), a lista de lances já feitos deve ser reenviada pelo servidor, para o cliente conseguir "recuperar" o estado da partida em andamento

## Restrições importantes

- NÃO implementar validação de regras de xadrez (lance ilegal deve ser aceito normalmente por enquanto)
- NÃO implementar autenticação/login — o `player_id` pode ser algo simples enviado manualmente pelo cliente por enquanto (ex: um input de texto na página de teste, ou um valor fixo)
- NÃO mexer no `ArticleController`/contexto `Blog` de exemplo, nem em nenhuma outra parte do projeto não relacionada a este escopo
- Manter os nomes de módulo consistentes com o namespace já existente no projeto (`ChessDuelBackend`, `ChessDuelBackendWeb`)
