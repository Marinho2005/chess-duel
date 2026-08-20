# Prompt: Relógio da partida (formato fixo: 3 minutos por jogador, sem incremento)

Este é o próximo passo do backend ChessDuel, em cima da sincronização (Channel + GenServer) e da validação de xadrez (Port + chess.js) já implementadas. Agora precisamos adicionar um relógio de partida no estilo bullet: cada jogador começa com 3 minutos (180 segundos), sem incremento por lance. Quando o tempo de um jogador chega a zero, ele perde a partida por tempo esgotado (a menos que o oponente não tenha material suficiente para dar xeque-mate, mas essa regra específica pode ficar de fora por enquanto — se o tempo acabar, apenas declare derrota por tempo).

## Princípio importante: servidor é sempre autoritativo

O cliente pode (e deve, em uma etapa futura de frontend) decrementar o relógio visualmente a cada segundo para dar feedback fluido ao usuário, mas quem decide de verdade quando o tempo acabou é o SERVIDOR. Não implemente nenhuma lógica de tempo real (tipo `Process.send_after` disparando a cada segundo) que dependa de "contar" no servidor a cada tick — em vez disso, use o padrão de calcular o tempo restante com base em timestamps, e agendar um único evento futuro para quando o tempo daquele jogador efetivamente zerar.

## O que preciso que você implemente

### 1. Atualizar o estado do `GameServer` (GenServer de partida)

Em `lib/chess_duel_backend/games/game_server.ex`, adicionar ao estado:
- `white_time_remaining_ms` (inteiro, inicializado em `180_000` — 3 minutos em milissegundos)
- `black_time_remaining_ms` (inteiro, inicializado em `180_000`)
- `turn_started_at` (timestamp de quando o turno atual começou — use `System.monotonic_time(:millisecond)` para evitar problemas com ajuste de relógio do sistema)
- `clock_timer_ref` (referência do timer agendado via `Process.send_after/3`, para poder cancelar e reagendar quando necessário)

### 2. Lógica de cálculo do relógio

- Quando a partida inicia (primeiro lance ainda não foi feito), o relógio de ambos os jogadores fica parado até o primeiro lance das brancas ser feito (padrão comum em xadrez: o relógio só começa a contar de verdade quando a partida realmente começa a se mover)
- A cada lance válido feito (dentro de `make_move/4`, depois que o lance for validado com sucesso pelo `ChessValidator`):
  1. Calcular quanto tempo se passou desde `turn_started_at` até agora
  2. Subtrair esse tempo do `time_remaining_ms` do jogador que ACABOU de jogar (não do próximo a jogar)
  3. Cancelar o timer anterior (`Process.cancel_timer(clock_timer_ref)`, se existir)
  4. Agendar um novo timer com `Process.send_after(self(), :time_expired, tempo_restante_do_proximo_jogador)` — ou seja, o timer é sempre agendado para o momento exato em que o relógio do jogador que VAI jogar agora chegaria a zero, não um tick por segundo
  5. Atualizar `turn_started_at` para o momento atual, marcando o início do novo turno
- Implementar o `handle_info(:time_expired, state)`: quando esse evento disparar, verificar se realmente o tempo do jogador da vez chegou a zero (proteção contra timer desatualizado, caso um lance tenha sido feito bem perto do disparo do timer — se um lance válido já foi processado antes do timer dispersar, o timer antigo deve ter sido cancelado no passo 4, mas é bom ter essa checagem de segurança); se confirmado, marcar a partida como `status: "finished"`, determinar o vencedor (o jogador que NÃO ficou sem tempo), e fazer o Channel correspondente fazer `broadcast!` de um evento `"game_over"` com `reason: "timeout"` e o vencedor

### 3. Expor o tempo restante para os clientes

- Sempre que o `GameChannel` fizer `broadcast!` do evento `"move_made"` (já implementado na etapa anterior), incluir também `white_time_remaining_ms` e `black_time_remaining_ms` atualizados no payload
- No `join/3` do Channel (quando um cliente entra/reconecta), incluir o tempo restante atual de cada jogador na resposta de sincronização inicial (para o cliente saber onde retomar o relógio visualmente)

### 4. Atualizar a página de teste (`frontend/pages/test-game.vue`)

- Mostrar na tela o tempo restante de cada jogador (pode ser só o valor em segundos, não precisa de formatação bonita tipo "mm:ss" ainda — isso é polimento visual para depois)
- Atualizar esses valores sempre que um evento `"move_made"` for recebido
- Se receber `"game_over"` com `reason: "timeout"`, mostrar uma mensagem clara (ex: "Fim de jogo por tempo esgotado. Vencedor: pretas")

## Critério de sucesso

1. Iniciar uma partida nova — os relógios começam em 180000ms (3 min) cada, parados
2. Fazer o primeiro lance das brancas — o relógio das brancas deve começar a "correr" a partir desse momento (ou seja, o tempo restante delas só deve começar a diminuir de fato a partir do lance seguinte que elas fizerem, refletindo o tempo gasto pensando)
3. Trocar alguns lances entre as duas abas de teste, e confirmar que o tempo restante de cada jogador é decrescido corretamente, correspondente ao tempo real gasto entre os lances daquele jogador
4. Para testar o timeout sem esperar 3 minutos inteiros: é aceitável, apenas para fins de teste manual, adicionar uma forma temporária de reduzir o tempo inicial (por exemplo, uma variável de configuração ou um parâmetro que eu possa ajustar manualmente no código para simular um tempo bem curto, tipo 10 segundos, durante o teste) — mas o valor padrão em produção deve continuar sendo 180000ms; deixe claro no código onde esse valor está definido para eu poder ajustar facilmente durante testes
5. Deixar o tempo de um jogador se esgotar (sem fazer lance) e confirmar que o evento `"game_over"` com `reason: "timeout"` é disparado corretamente, identificando o vencedor certo

## Restrições importantes

- NÃO implementar incremento por lance (Fischer increment) nesta etapa — é sempre 3 minutos fixos, sem adicionar tempo a cada lance
- NÃO implementar tempo configurável por partida ainda (não precisa de UI para escolher "5 min", "10 min" etc — o valor fica fixo em 180000ms no código por enquanto)
- NÃO implementar a regra de "material insuficiente do oponente impede vitória por tempo" — se o tempo acabar, é derrota por tempo, ponto final, independente da posição no tabuleiro
- NÃO usar `Process.send_after` com tick a cada segundo/intervalo curto repetido — a lógica deve ser baseada em agendar UM evento para o momento exato em que o tempo zeraria, recalculado a cada lance, conforme descrito acima
- NÃO mexer no contexto `Blog`/`ArticleController` de exemplo nem em partes não relacionadas a este escopo
- Manter consistência de namespace com o projeto existente (`ChessDuelBackend`, `ChessDuelBackendWeb`)
