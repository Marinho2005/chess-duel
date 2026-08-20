# Prompt: Validação de lance de xadrez no backend (via Port para chess.js)

Este é o próximo passo do backend ChessDuel, em cima da sincronização em tempo real já implementada (Channel + GenServer por partida). Agora precisamos validar cada lance recebido usando as regras reais do xadrez, no SERVIDOR (nunca confiar só no cliente).

## Estratégia escolhida

Usar a biblioteca `chess.js` (JavaScript/TypeScript, madura e testada, a mesma usada pelo lichess) rodando como um processo Node.js separado, comunicando com o Elixir via **Port**. NÃO implementar uma lógica de xadrez do zero em Elixir, e NÃO usar nenhuma lib Elixir de xadrez incompleta — o objetivo é aproveitar uma engine já testada em produção.

## O que preciso que você implemente

### 1. Script Node.js "validador" (novo diretório `backend/priv/chess_validator/`)

- Um pequeno projeto Node.js (`package.json` com dependência `chess.js`)
- Um script (`validator.js` ou `index.js`) que:
  - Lê uma linha JSON de `stdin` no formato: `{"fen": "<posição atual em FEN>", "from": "e2", "to": "e4", "promotion": null}`
  - Usa `chess.js` para carregar a posição a partir do FEN e tentar aplicar o lance
  - Escreve em `stdout` uma linha JSON de resposta:
    - Se o lance for válido: `{"valid": true, "new_fen": "<novo FEN>", "is_check": bool, "is_checkmate": bool, "is_stalemate": bool, "is_draw": bool, "captured": "<peça capturada ou null>"}`
    - Se o lance for inválido: `{"valid": false, "reason": "illegal_move"}`
  - O script deve rodar em loop contínuo, lendo uma linha de stdin, processando, escrevendo a resposta em stdout, e voltando a esperar a próxima linha (não deve terminar o processo a cada lance — deve ficar vivo, processando lance por lance, para evitar o custo de iniciar um novo processo Node a cada jogada)

### 2. Módulo Elixir que gerencia o Port

Criar `lib/chess_duel_backend/chess_validator.ex`:
- Um `GenServer` que inicia o processo Node (`priv/chess_validator/validator.js`) via `Port.open/2` quando a aplicação sobe
- Função pública `validate_move(fen, from, to, promotion \\ nil)` que:
  - Envia a requisição (JSON + newline) para o Port
  - Aguarda a resposta (também JSON + newline) do processo Node
  - Faz o parse da resposta e retorna `{:ok, %{new_fen: ..., is_check: ..., is_checkmate: ..., is_stalemate: ..., is_draw: ..., captured: ...}}` ou `{:error, :illegal_move}`
  - Implementar com cuidado o controle de concorrência: como múltiplas partidas podem chamar `validate_move` "ao mesmo tempo", mas o Port é um processo Node único compartilhado, é necessário serializar as chamadas (o próprio GenServer, sendo um processo único que atende `call` de forma sequencial, já resolve isso — garanta que a implementação realmente serializa e não gera race condition na leitura da resposta errada para a requisição errada)
- Registrar esse `GenServer` na árvore de supervisão em `lib/chess_duel_backend/application.ex`

### 3. Atualizar o `GameServer` (GenServer de partida) para validar antes de aceitar o lance

Em `lib/chess_duel_backend/games/game_server.ex`:
- A função `make_move/4` deve, ANTES de adicionar o lance à lista e alternar o turno:
  1. Chamar `ChessDuelBackend.ChessValidator.validate_move(estado_atual.fen, from, to, promotion)`
  2. Se `{:error, :illegal_move}`: retornar `{:error, :illegal_move}` sem alterar o estado
  3. Se `{:ok, resultado}`: atualizar o `fen` do estado da partida com `resultado.new_fen`, adicionar o lance à lista de lances, alternar `current_turn`, e incluir no estado retornado as flags `is_check`, `is_checkmate`, `is_stalemate`, `is_draw`
  4. Se `is_checkmate` ou `is_stalemate` ou `is_draw` for `true`, atualizar o `status` da partida para `"finished"` no estado do GenServer
- O estado inicial do GenServer (quando uma partida nova é criada) deve começar com o FEN padrão de início de jogo: `"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"`

### 4. Atualizar o `GameChannel` para repassar o resultado da validação

Em `lib/chess_duel_backend_web/channels/game_channel.ex`:
- O handler `handle_in("move", ...)` deve chamar `GameServer.make_move/4` e:
  - Se `{:error, :illegal_move}`: responder AO CLIENTE QUE ENVIOU (não fazer broadcast) com um erro, por exemplo `{:reply, {:error, %{reason: "illegal_move"}}, socket}`
  - Se sucesso: fazer `broadcast!` para todos no tópico com o evento `"move_made"`, incluindo `from`, `to`, `player`, `new_fen`, `current_turn`, `is_check`, `is_checkmate`, `is_stalemate`, `is_draw`
  - Se a partida terminou (`is_checkmate`, `is_stalemate` ou `is_draw` true), fazer também `broadcast!` de um evento adicional `"game_over"` com o motivo (`checkmate`, `stalemate`, ou `draw`) e o vencedor, se aplicável (no caso de xeque-mate, o vencedor é quem fez o lance)

### 5. Atualizar a página de teste no frontend (`frontend/pages/test-game.vue`)

- Mostrar na tela o FEN atual da partida (recebido via `move_made`)
- Se o servidor responder com erro de lance ilegal, mostrar uma mensagem simples de erro na tela (ex: "Lance ilegal") em vez de simplesmente ignorar
- Se receber o evento `"game_over"`, mostrar uma mensagem clara (ex: "Xeque-mate! Vencedor: brancas")

## Critério de sucesso

1. `mix phx.server` sobe sem erro, com o processo Node do validador iniciando junto (verificar nos logs que o Port foi aberto com sucesso)
2. Abrir duas abas em `/test-game`
3. Tentar um lance ilegal (ex: mover peão de "e2" direto para "e5") — deve ser rejeitado, com mensagem de erro aparecendo SÓ na aba que tentou o lance
4. Fazer uma sequência de lances válidos simples (ex: abertura normal) — devem ser aceitos e sincronizados nas duas abas, com o FEN atualizando corretamente
5. Simular um xeque-mate rápido (ex: Fool's Mate — 1. f3 e5 2. g4 Qh4#) e confirmar que o evento `"game_over"` aparece nas duas abas ao final

## Restrições importantes

- NÃO reescrever lógica de xadrez em Elixir puro — usar exclusivamente o `chess.js` via Port, conforme descrito
- NÃO implementar autenticação real ainda (continua sem login, igual à etapa anterior)
- NÃO implementar relógio/tempo de partida ainda (isso é uma etapa futura separada)
- NÃO mexer no contexto `Blog`/`ArticleController` de exemplo nem em outras partes não relacionadas a este escopo
- Manter consistência de namespace com o que já existe no projeto (`ChessDuelBackend`, `ChessDuelBackendWeb`)
- Documentar no README (ou em um comentário claro no `chess_validator.ex`) que o Node.js precisa estar instalado no ambiente para o Port funcionar, e como instalar as dependências do validador (`cd backend/priv/chess_validator && npm install`)
