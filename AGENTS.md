# ChessDuel — Contexto do Projeto

Este arquivo dá contexto de fundo sobre o projeto para qualquer sessão de agente de código (Codex, etc). **Leia isto integralmente antes de implementar qualquer tarefa**, para manter consistência com as decisões já tomadas e saber exatamente em qual etapa do roadmap a tarefa se encaixa.

---

## O que é o projeto

ChessDuel é um SaaS de xadrez em tempo real (inspirado em chess.com/lichess), em desenvolvimento. Projeto pessoal em fase de aprendizado e construção, com ambição de longo prazo, mas construído em etapas pequenas e testáveis — nunca implementar múltiplas funcionalidades grandes de uma vez sem validar cada uma isoladamente primeiro.

---

## Stack e por quê

| Camada | Tecnologia | Motivo da escolha |
|---|---|---|
| Backend | Elixir + Phoenix (modo API) | Modelo de processos leves (OTP/GenServer) é ideal para isolar cada partida como um processo independente, com tolerância a falha nativa. Escolhido em vez de Node/Go/Java por essa vantagem específica para jogos multiplayer em tempo real. |
| Validação de xadrez | Node.js + `chess.js`, via Port do Elixir | Bibliotecas Elixir nativas de xadrez ainda são imaturas (sem detecção completa de xeque-mate/empate). `chess.js` é madura, testada, e é a mesma engine usada pelo lichess. Decisão consciente: não reinventar validação de xadrez do zero. |
| Banco relacional | PostgreSQL | Cidadão de primeira classe no ecossistema Ecto/Phoenix. |
| Cache/estado efêmero | Valkey | Fork open source do Redis (Linux Foundation), compatível, sem risco de licença futura. |
| Frontend | Nuxt 3 (Vue 3, Composition API, TypeScript) | Preferido em vez de Next.js por modelo mental mais explícito/previsível e melhor flexibilidade de deploy multi-plataforma (Nitro). |
| Deploy (em preparação) | Railway (backend, Postgres e Valkey/Redis) + Cloudflare Pages (frontend) | Release local em preparação para o pré-beta; provisionamento e publicação ainda pendentes. |

---

## Convenções do projeto

- Namespace do backend: `ChessDuelBackend` (lógica pura) e `ChessDuelBackendWeb` (Controllers, Channels, Router — tudo que fala com o mundo externo)
- Backend foi gerado com `--no-html --no-assets` (modo API puro) — não adicionar views HTML tradicionais
- Contextos seguem a convenção Phoenix: pasta com nome do domínio (ex: `games/`), schemas dentro dela (ex: `games/game.ex`)
- NÃO mexer no contexto `Blog`/`ArticleController` de exemplo, gerado durante o aprendizado inicial do framework — não faz parte do produto
- Toda funcionalidade nova é desenvolvida em uma branch própria (`feature/nome-da-tarefa`), criada a partir da `develop` atualizada; nunca trabalhar ou fazer push diretamente na `develop` ou `main`
- A interface oficial das partidas ao vivo fica em `frontend/pages/game/[gameId]/live.vue`, na rota `/game/:gameId/live`; a análise pós-jogo fica em `frontend/pages/game/[gameId]/review.vue`, na rota `/game/:gameId/review`. As duas são rotas irmãs para impedir que o Nuxt monte a partida ao vivo como página pai da análise.
- Na rota ao vivo, `:gameId` representa `Game.game_id`, identificador público usado pelo `GameServer` e pelo tópico Phoenix. Na rota de review, representa `Game.id`, chave primária UUID usada pelos endpoints de análise. Não intercambiar os dois valores.
- As páginas principais usam `frontend/layouts/default.vue`, que renderiza o header compartilhado `frontend/components/navigation/AppHeader.vue`. O menu Social abre por hover ou teclado/clique e oferece Amigos e Clubes; no celular, os links ficam na navegação expansível. No desktop, configurações e logout aparecem ao lado das notificações, e o avatar leva diretamente ao perfil público do usuário, sem menu ou ícone separado de perfil. Partidas ao vivo e reviews usam `layout: false` para permanecerem em tela cheia.
- Os três temas (`navy`, `black`, `white`) usam os tokens de `frontend/assets/css/theme.css`, selecionados por `useTheme`; novas interfaces devem reutilizar essas variáveis.
- A tipografia do frontend é autocontida e independente das fontes instaladas no sistema operacional: `Inter Variable` é a sans-serif padrão, `Lora Variable` cobre marca e destaques serifados, e `Roboto Mono Variable` cobre notação e valores monoespaçados. As três fontes do catálogo Google Fonts são instaladas via Fontsource e carregadas globalmente em `frontend/nuxt.config.ts`; novas telas devem usar os tokens `--font-sans`, `--font-serif`, `--font-mono` e `--font-brand` definidos em `frontend/assets/css/theme.css`, sempre com fallback genérico.
- Os botões de modalidade do ranking usam `frontend/public/icons/bullet.svg`, `blitz.svg` e `rapid.svg` (bala, raio e relógio), redesenhados com traço único e pontas arredondadas no estilo Lucide. As máscaras CSS acompanham a cor do botão nos três temas.
- `GameCategoryIcon.vue` compartilha esses ícones entre o ranking, os cards e o resumo de ritmo em `/play`, e os ratings do perfil público em `/user/:username`.
- O painel "Seu desempenho" do lobby separa Bullet, Blitz e Rápidas em abas; cada aba usa o rating da categoria, consulta histórico e total filtrados e desenha um gráfico compacto com as 20 alterações de rating mais recentes. Partidas sem variação de rating continuam no histórico recente sem o rótulo textual "Casual". No card de amigos, a presença é indicada somente pela bolinha sobre o avatar, sem repetir o status em texto.
- O ranking mantém sua própria conexão `games:lobby` enquanto está aberto para registrar a presença do usuário. Eventos `lobby_updated` atualizam os status pela API sem recarregar a página; uma consulta a cada 15 segundos também cobre mudanças de conexão em partidas. A conexão e os timers são encerrados ao sair da página, e o modo Invisível aparece offline para os demais.
- As buscas de jogadores em `/social/friends` e de clubes em `/social/clubs` são incrementais, com debounce de 350 ms e indicação visual durante a requisição.
- Os botões "Desafiar" nos perfis públicos, no lobby e em `/social/friends` levam a `/play?opponent=:nickname`, onde o card mostra avatar, presença e rating do ritmo selecionado antes do envio pelo evento `challenge_user`. O lobby e `/play` também oferecem o painel "Desafie alguém", que pesquisa qualquer conta confirmada por apelido e preserva a opção de sala privada por link. `/play` exibe os desafios enviados como uma pilha crescente de adversários, com remoção individual por `cancel_challenge`; `cancel_challenges` remove de uma vez todos os desafios enviados pelo usuário. Desafios diretos podem ser enviados a vários destinatários diferentes, inclusive offline, e permanecem em memória por até 24 horas. Desafios comuns iniciados na lista de jogadores online preservam as regras anteriores de presença e desconexão.
- O projeto tem três pessoas trabalhando nele. Evitar decisões que quebrem trabalho em andamento nas outras branches e manter cada funcionalidade isolada em sua própria branch
- O ambiente completo de desenvolvimento pode ser iniciado com `docker compose up --build`; a execução local de backend e frontend continua disponível como alternativa.
- Os tabuleiros compartilhados `GameBoard.vue` e `ReadonlyBoard.vue` não exibem coordenadas nas casas nem nas bordas. Listas de lances e destaques funcionais permanecem. Evitar sombras coloridas com blur/brilho nas interfaces; usar sombras neutras e preservar contornos de foco acessíveis.
- Cards de preview e painéis do lobby usam superfícies planas, sem sombras largas ou sombras internas nos mini-tabuleiros. Títulos de broadcasts quebram linha sem reticências; textos auxiliares do desempenho usam pelo menos 13 px (nota explicativa: 14 px). Badges de resultado usam texto do tema sobre fundo semântico para manter contraste nos três temas.
- O indicador “Online agora” do lobby e o status online do header usam pontos sólidos, sem brilho. O avatar principal do header e `PresenceAvatar.vue` usam `referrerpolicy="no-referrer"` e mostram a inicial em falhas de imagem, permitindo nova tentativa quando a URL muda.
- A tela de login inclui o crédito “developed by Victor Marinho Lima” abaixo do formulário, usando `--font-serif` (Lora Variable) e as cores do tema, sem dependência de fonte do sistema.

---

## Fluxo Git da equipe

O repositório segue este fluxo de branches:

- `main`: versão estável do projeto
- `develop`: integração das funcionalidades prontas
- `feature/*`: desenvolvimento isolado de cada funcionalidade

Antes de começar uma funcionalidade nova, atualizar a `develop` local e criar a branch a partir dela:

```bash
git switch develop
git pull origin develop
git switch -c feature/nome-da-feature
```

Durante o desenvolvimento, commits e pushes devem ser feitos somente na branch da feature:

```bash
git add .
git commit -m "feat: descreve a funcionalidade"
git push -u origin feature/nome-da-feature
```

Quando a funcionalidade estiver pronta, abrir um Pull Request de `feature/*` para `develop`. Pelo menos uma das outras pessoas deve revisar o PR antes do merge.

Regras obrigatórias:

- Não trabalhar, fazer commits ou dar push diretamente na `main` ou na `develop`
- Não criar a branch da feature pelo site do GitHub; criá-la localmente a partir da `develop` atualizada e depois fazer o primeiro push
- Usar uma branch `feature/*` separada para cada funcionalidade
- Não trocar para a `develop` sem necessidade durante uma feature em andamento; usá-la para atualização e como base de uma nova branch
- Integrar uma feature à `develop` somente por Pull Request revisado
- Integrar `develop` à `main` somente quando houver uma versão estável
- Antes de solicitar qualquer alteração, o desenvolvedor deve conferir a branch atual e o estado do repositório e informar ao agente quando houver trabalho não commitado que precise ser preservado
- O agente de código nunca deve executar comandos Git, incluindo `git status`, `git add`, `git commit`, `git push`, `git pull`, `git fetch`, `git switch`, `git merge` ou equivalentes
- Toda a gestão Git é feita manualmente pelo desenvolvedor no terminal; o agente pode orientar o fluxo, revisar saídas fornecidas e sugerir mensagens de commit

Fluxo resumido:

```text
develop atualizada -> feature/* -> commits -> push -> Pull Request revisado -> develop
develop estável -> Pull Request -> main
```

---

## Princípios de engenharia adotados no projeto

- **Servidor é sempre autoritativo**: nunca confiar no cliente para decidir se um lance é válido, se o tempo acabou, ou se a partida terminou. O cliente pode fazer estimativas visuais (ex: relógio contando localmente), mas a decisão real sempre vem do servidor.
- **Construir em camadas pequenas e testáveis**: cada etapa prova um mecanismo isolado antes de combinar com o próximo.
- **Evitar engenharia prematura**: não adicionar ferramentas de infraestrutura (Traefik, Sentry, Prometheus, Docker completo para dev, etc) antes de haver necessidade real e comprovada. Priorizar o core do produto funcionando primeiro.
- **Preferir bibliotecas maduras a reescrever do zero**, especialmente em domínios onde bugs sutis são fáceis de introduzir e difíceis de notar (ex: regras de xadrez).
- **Autenticação local foi implementada na Fase 2.1** com email/senha e bearer token revogável. A identidade das partidas vem do `user_id` autenticado; OAuth permanece reservado para a etapa 2.2.
- O cadastro local pede confirmação de senha no cliente e aceita `birth_date` opcional. A data de nascimento não pode ser futura, é privada e aparece somente para o próprio usuário em `/api/users/me` e nas configurações; nunca integra o perfil público.
- **Escritas em banco nunca bloqueiam a experiência em tempo real** — qualquer persistência durante uma partida ao vivo deve ser assíncrona; o estado em memória do GenServer é sempre a fonte de verdade imediata para os jogadores.

---

## Roadmap completo, por fase e etapa

**Legenda:** `[x]` concluído · `[~]` em andamento · `[ ]` pendente

### Fase 1 — Core do jogo

- [x] **1.1 Sincronização (Channel + GenServer)** — Dois clientes conectam na mesma partida via WebSocket (Phoenix Channel). Cada partida é um processo isolado (GenServer via Registry + DynamicSupervisor). Lances trocam em tempo real.
- [x] **1.2 Validação de xadrez real** — Port do Elixir para processo Node rodando `chess.js`. Cada lance é validado no servidor antes de ser aceito.
- [x] **1.3 Relógio da partida** — Formato fixo de 3 minutos por jogador, sem incremento. Cálculo baseado em timestamp (servidor autoritativo). Contagem visual decrescente implementada no frontend (estimativa local, sempre realinhada pelo servidor).
- [x] **1.4 Detecção de fim de jogo** — Xeque-mate, afogamento, empate e timeout disparam corretamente o evento de fim de jogo, com mensagem diferenciada para vencedor/perdedor.
- [x] **1.5 Reconexão robusta** — Identidade estável do jogador (branco/preto) entre reconexões, via `player_id` persistido em `localStorage` no cliente de teste. Timeout de graça de 60 segundos antes de declarar abandono quando um jogador desconecta.
- [x] **1.6 Persistência real no Postgres** — Salvar a partida no banco (lances, FEN, tempos, resultado) tanto durante o jogo (escrita assíncrona a cada lance) quanto ao final (resultado, motivo, timestamp de término). Opcionalmente, permitir recuperação de estado do GenServer a partir do banco em caso de restart do servidor.

### Fase 2 — Contas e ranking — COMPLETA

- [x] **2.1 Autenticação local (email/senha)** — `mix phx.gen.auth`, integrado à tabela de usuários que substituirá o `player_id` temporário usado nos testes. Contas locais precisam confirmar o e-mail antes de receber token ou acessar o sistema; em desenvolvimento, o link é exibido no log do backend.
- [x] **2.2 OAuth (login social)** — Login com Google, Discord e GitHub via Ueberauth e identidades externas genéricas; somente Google verificado vincula automaticamente por e-mail. Todos reutilizam o bearer token do frontend.
- [x] **2.3 Perfil de jogador** — Página pública em `/user/:username` com cabeçalho e abas de visão geral, partidas paginadas, estatísticas com evolução de rating, amigos e clubes. Exibe presença, foto, país, data de criação e contador de visualizações incrementado somente por visitantes autenticados diferentes do dono; a edição do próprio perfil permanece protegida.
- [x] **2.4 Sistema de rating** — ELO com K=32 atualizado de forma assíncrona, atômica e idempotente ao fim da partida; ratings independentes para Bullet, Blitz (compartilhado por 3+0 e 5+0) e Rapid, com snapshots e histórico por categoria persistidos para auditoria.
- [x] **2.5 Histórico de partidas** — Lista paginada das partidas finalizadas do usuário, com oponente, resultado sob sua perspectiva, motivo, variação de rating e data.

### Fase 3 — Matchmaking sério — COMPLETA

- [x] **3.1 Fila por rating** — Fila por formato no Valkey, com pareamento periódico por proximidade de rating, tolerância crescente e entrada/cancelamento pelo lobby em tempo real.
- [x] **3.2 Tempo configurável** — Bullet 1+0, Blitz 3+0, Blitz 5+0 e Rapid 10+0 selecionáveis nos desafios; os relógios sem incremento são autoritativos no `GameServer` e persistidos por partida.
- [x] **3.3 Salas privadas** — Criação de sala com link de convite, para jogar com amigos sem passar pela fila de matchmaking.

### Fase 4 — Puzzles e análise

- [x] **4.1 Worker Stockfish separado** — Processo UCI isolado do game service, executado por uma fila Oban dedicada para não competir por recursos com partidas ao vivo.
- [x] **4.2 Análise pós-jogo assíncrona** — Stockfish analisa partidas finalizadas em background; participantes acompanham o processamento e revisam a partida em uma tela interativa com replay, classificações e barra de avaliação.
- [x] **4.3 Banco de puzzles táticos** — Importação streaming de um subconjunto distribuído do dataset CC0 do Lichess, seleção por rating, tentativas persistidas e interface interativa com Chessground. O FEN antecede a sequência: o lance de índice 0 é preparação automática, o usuário joga os índices ímpares e as respostas pares são automáticas. O `puzzle_rating` começa em 1200 e é independente do rating de partidas.
- [x] **4.4 Puzzle Rush** — Sessões autoritativas cronometradas em GenServers próprios, sequência crescente por dificuldade, limite de três erros, placares separados e interface com modos de 3 e 5 minutos.
- [x] **4.5 Partidas contra bots** — Stockfish com cinco níveis de força, integrado ao `GameServer`, com personagens ilustrados, preparação autoritativa, abortar, desistir e partidas sem alteração de rating.
- [x] **4.6 Puzzle Battle** — Matchmaking separado por duração e proximidade de `battle_rating`, duelos autoritativos em Phoenix Channels com a mesma sequência para ambos, progresso independente, reconexão, desempate determinístico e rating Elo próprio.

### Fase 5 — Monetização (SaaS)

- [ ] **5.1 Integração Stripe** — Cobrança recorrente.
- [ ] **5.2 Planos free/premium** — Definição de limites do plano gratuito.
- [ ] **5.3 Features pagas** — Análise ilimitada, temas de tabuleiro, remoção de anúncio (se houver).

### Fase 6 — Social e escala

- [ ] **6.1 Torneios** — Sistema de inscrição, chaveamento, ranking de torneio.
- [~] **6.2 Clubes e chat** — Clubes estão implementados com criação, descoberta, entrada aberta ou por aprovação, múltiplos administradores e avatares. Chat continua pendente para uma etapa separada.
- [~] **6.3 Espectadores/streaming** — Broadcasts profissionais do Lichess podem ser assistidos em tempo real dentro do ChessDuel; a página `/observar` lista todos os broadcasts em andamento do catálogo público `/api/broadcast/top` do Lichess, sem corte local de torneios, exibe suas imagens oficiais e mantém até 30 previews por torneio no feed. A página do torneio oferece todas as partidas da rodada selecionada e acesso às rodadas anteriores, com resultado e replay por links que preservam `round`. Metadados e PGNs históricos usam cache limitado sob demanda; a leitura de PGNs é isolada da validação das partidas internas. A página também permite filtrar os previews de partidas humanas por Bullet, Blitz 3+0, Blitz 5+0 e Rapid. Os avatares indicam presença no canto inferior direito, e o lobby alterna entre os dois feeds. O tabuleiro do broadcast anima os movimentos em 300 ms e reproduz lotes de lances em sequência, com som sincronizado, preservando a navegação pelo histórico. Os relógios ao lado dos jogadores usam os tempos `%clk` do Lichess: ao vivo, o jogador na vez tem contagem estimada por tempo decorrido, realinhada pelos relógios do JSON (centissegundos) e `thinkTime` (segundos já gastos no turno), incluindo a idade do snapshot no cache. Os tempos ao vivo só são associados ao PGN quando os FENs coincidem; snapshots repetidos não reiniciam a contagem. Histórico, reprodução de lotes e transmissões encerradas mostram os tempos registrados, e dados ausentes aparecem como “—”. Espectação completa das partidas internas continua pendente.
- [ ] **6.4 Multi-região** — Escala geográfica, quando o volume de usuários justificar.

### Fora do roadmap numerado, mas necessária em algum momento

- [x] **Painel administrativo e moderação** — `/admin` oferece dashboard, usuários e partidas paginados, detalhes somente leitura e visão básica de sistema. Role global `admin` persistida, estados `active`/`suspended`/`banned`, suspensão com expiração temporal e histórico transacional de moderação. APIs e Channels revalidam o bloqueio, e a moderação desconecta sockets existentes. Primeiro acesso por `mix admin.grant UUID`, sem conta padrão ou gerenciamento de roles pelo painel. Operação e validação documentadas em `docs/admin.md`.

- [x] **Sistema de amizades e menu Social** — `/social/friends` permite buscar jogadores por apelido em tempo real, enviar, aceitar, recusar e cancelar pedidos, remover amizades e abrir perfis públicos. Os botões "Desafiar" no perfil público de outra pessoa, no lobby e na lista de amigos abrem `/play` com o adversário, sua foto e seu rating já selecionados; o jogador pode manter desafios pendentes para várias pessoas e remover cada um. No lobby e em `/play`, "Desafie alguém" permite buscar qualquer conta confirmada por apelido, preparar um desafio direto ou gerar uma sala privada por link. Separa amigos, pedidos recebidos e enviados, reutiliza o avatar com presença e atualiza as listas a cada 15 segundos enquanto a aba está visível. A descoberta de clubes também pesquisa com debounce enquanto o usuário digita. Usuários invisíveis aparecem offline. O header oferece Amigos e Clubes nos três temas, central de notificações sem destaque dourado no hover, configurações ao lado e acesso ao perfil pela própria foto.
- [x] **UI real de jogo** — Rota `/game/:gameId/live` com Chessground oficial em componente Vue, destinos legais via chess.js, drag/clique, premove, orientação por cor, relógios, jogadores, histórico e resultado em tempo real; a antiga página manual `test-game.vue` foi removida.
- [x] **Dockerização completa (desenvolvimento)** — O Compose sobe Postgres, Valkey, Phoenix e Nuxt com dependências isoladas e código montado para recarga em desenvolvimento. Imagens e configuração de produção/deploy continuam pendentes.
- [~] **Preparação de produção / pré-beta** — Bloco 1 adiciona `backend/Dockerfile`, release OTP com `Release.migrate/0`, `backend/railway.toml` e teste isolado em `compose.release-test.yml`. Segredos, URLs, `ALLOWED_ORIGINS`, modo TLS explícito do Postgres e caminhos de uploads são configurados em runtime. CORS REST e WebSocket compartilham as origens; uploads usam volume `/data` com `UPLOADS_DIR=/data/uploads`. Começar com uma réplica sempre ligada. Operação em `docs/production.md`; e-mail real, limites, recuperação do Port, manutenção de deploy e OAuth desabilitado apenas em produção permanecem para os próximos blocos. Nenhum deploy público foi concluído.
- [x] **Modo convidado** — Sessões temporárias assinadas permitem partidas casuais exclusivamente entre convidados, com fila FIFO em memória, sem criar usuários, persistir partidas ou calcular rating.
- [x] **Navegação das funcionalidades** — Os itens "Puzzles" e "Bots" levam às interfaces funcionais implementadas nas etapas 4.3–4.6; o hub de puzzles separa Classic, Rush e Battle.
- [x] **Polimento de UX/UI da partida** — Sons discretos com preferência local, país ISO com bandeira reutilizável, ação pós-jogo para análise, planilha SAN por full move e microinterações acessíveis na navegação.
- [x] **Revanche e preferência de layout** — Partidas encerradas permitem revanche com cores invertidas contra humanos ou bots; o tamanho conjunto do tabuleiro e das identidades dos jogadores é configurável e persistido, e o replay aceita navegação pelas setas do teclado.

---

## Como trabalhar neste projeto

### API de clubes

- Todos os endpoints de clubes exigem bearer token. `POST /api/clubs` cria o clube e o vínculo ativo de administrador do criador na mesma transação; aceita formulário JSON ou multipart com `avatar` opcional JPG, PNG ou WebP de até 2 MB.
- `GET /api/clubs?q=&page=` pesquisa parcialmente por nome, sem diferenciar maiúsculas, e pagina 12 clubes por vez. `GET /api/clubs/:id` retorna membros ativos, o vínculo do usuário atual e, somente para administradores, os pedidos pendentes.
- `POST /api/clubs/:id/join` ativa imediatamente em clubes abertos e cria pedido pendente em clubes por aprovação. Um usuário mantém no máximo um vínculo por clube.
- Administradores usam `PATCH /api/clubs/:id`, e as ações `approve`, `decline` e `promote` em `/api/clubs/:id/memberships/:membership_id/*`. O próprio membro pode sair e administradores podem remover membros com `DELETE`; o último administrador ativo não pode sair nem ser removido.
- Nomes de clubes não são únicos. Um usuário pode participar de vários clubes, e membros promovidos têm os mesmos poderes administrativos. Chat, torneios internos e competições de clube não fazem parte desta etapa.

### API de amizades

- Todos os endpoints exigem bearer token de uma conta autenticada. `GET /api/users/search?q=...` busca apelidos parcialmente, sem diferenciar maiúsculas, com 2–32 caracteres e até 20 resultados; exclui o próprio usuário e contas não confirmadas, sem expor e-mail.
- `POST /api/friendships` recebe `user_id` ou `username`. Pedidos repetidos retornam `409`; um pedido no sentido inverso aceita automaticamente a amizade. Pedidos recusados podem ser reenviados reutilizando o registro e atualizando o remetente.
- `GET /api/friendships` aceita `status=pending|accepted|declined`; sem filtro retorna todos os status. Cada item contém `id`, `status`, `direction=incoming|outgoing`, `user` (o outro jogador) e timestamps.
- `PATCH /api/friendships/:id/accept` e `/decline` exigem que o usuário seja o destinatário de um pedido pendente. `DELETE /api/friendships/:id` permite remover amizade aceita por qualquer participante ou cancelar pedido pendente apenas pelo remetente.
- O contexto `ChessDuelBackend.Social` usa um índice único do par ordenado, validação contra autoamizade e transações com locks para serializar pedidos mútuos e respostas concorrentes. A migration adiciona constraints de status e de usuários distintos.

### Perfil público

- `GET /api/users/:nickname?page=` aceita autenticação opcional e retorna visão geral, histórico paginado, estatísticas detalhadas, evolução dos ratings Bullet, Blitz e Rapid, amigos e clubes do jogador.
- `GET /api/users/me/games` aceita `category=bullet|blitz|rapid`; quando informado, jogos e metadados de paginação são filtrados pela modalidade.
- Uma abertura autenticada por outro usuário incrementa `users.profile_views`; o próprio perfil, visitantes anônimos e consultas internas com `count_view=false` não incrementam o contador.

### API e rotas de observação

- `GET /api/broadcasts/tournaments` lista os broadcasts em andamento do catálogo público do Lichess sem limite local de torneios, com identificador, nome, imagem oficial e quantidade de previews ao vivo (nula quando indisponível). Falhas de uma rodada não removem o torneio do catálogo.
- `GET /api/broadcasts/tournaments/:tournament_id` retorna metadados e todas as rodadas, com status em andamento, encerrada ou programada.
- `GET /api/broadcasts/rounds/:round_id/games` retorna todas as partidas disponíveis da rodada, incluindo encerradas, com resultado, lances e FEN inicial quando aplicável. O replay `/watch/broadcast/:gameId?round=:roundId` pode ser reaberto mesmo depois do fim da transmissão; avaliações Stockfish permanecem restritas ao feed ao vivo.
- `GET /api/broadcasts/tournaments/:tournament_id/games` lista até 30 partidas ao vivo exclusivamente do torneio informado.
- `GET /api/games/live` aceita o filtro opcional `category=bullet|blitz|blitz_increment|rapid`; `blitz_increment` identifica o segundo controle Blitz atualmente configurado como 5+0.
- `/observar` oferece as abas Torneios e ChessDuel; `/observar/torneio/:tournamentId` abre as partidas agrupadas e reutiliza `/watch/broadcast/:gameId` para a espectação em tempo real.

1. Sempre ler este arquivo por completo antes de iniciar uma tarefa nova, para entender em qual etapa do roadmap ela se encaixa e quais decisões anteriores precisam ser respeitadas
2. Seguir rigorosamente o escopo definido no prompt de cada tarefa — não expandir escopo por conta própria (ex: não adicionar autenticação "de brinde" numa tarefa que não pediu isso, mesmo que pareça relacionado)
3. Quando houver ambiguidade de implementação sem uma resposta óbvia, escolher a abordagem mais simples e idiomática em Phoenix/Elixir, e comentar brevemente a decisão no código
4. Não modificar lógica já validada e funcionando (marcada com `[x]` no roadmap acima) a menos que a tarefa seja explicitamente sobre corrigir ou alterar essa parte
5. **Ao concluir uma tarefa, atualizar a marcação da etapa correspondente neste arquivo** (`[ ]` → `[~]` → `[x]`), como parte do commit da feature — isso mantém o roadmap sempre refletindo o estado real do projeto para qualquer sessão futura, sua ou de outro desenvolvedor
