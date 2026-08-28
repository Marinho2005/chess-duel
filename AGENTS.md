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
| Deploy (planejado) | Fly.io (backend) + Cloudflare Pages (frontend) | Ainda não implementado — infraestrutura de produção fica para depois que o core do produto estiver validado. |

---

## Convenções do projeto

- Namespace do backend: `ChessDuelBackend` (lógica pura) e `ChessDuelBackendWeb` (Controllers, Channels, Router — tudo que fala com o mundo externo)
- Backend foi gerado com `--no-html --no-assets` (modo API puro) — não adicionar views HTML tradicionais
- Contextos seguem a convenção Phoenix: pasta com nome do domínio (ex: `games/`), schemas dentro dela (ex: `games/game.ex`)
- NÃO mexer no contexto `Blog`/`ArticleController` de exemplo, gerado durante o aprendizado inicial do framework — não faz parte do produto
- Toda funcionalidade nova é desenvolvida em uma branch própria (`feature/nome-da-tarefa`), criada a partir da `develop` atualizada; nunca trabalhar ou fazer push diretamente na `develop` ou `main`
- A interface oficial das partidas fica em `frontend/pages/game/[gameId].vue`; a antiga página manual `test-game.vue` foi removida após a validação da UI real.
- O projeto tem três pessoas trabalhando nele. Evitar decisões que quebrem trabalho em andamento nas outras branches e manter cada funcionalidade isolada em sua própria branch
- O ambiente completo de desenvolvimento pode ser iniciado com `docker compose up --build`; a execução local de backend e frontend continua disponível como alternativa.

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
- Antes de executar qualquer alteração, o agente deve conferir a branch atual e o estado do repositório, preservando o trabalho não commitado das outras pessoas

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
- [x] **2.2 OAuth (login social)** — Login com Google via Ueberauth, vinculado por ID/e-mail à mesma tabela de usuários e integrado ao bearer token do frontend.
- [x] **2.3 Perfil de jogador** — Página pública com foto de perfil (inicial como fallback), apelido, país, rating e data de criação; edição autenticada do próprio perfil e proteção das rotas privadas.
- [x] **2.4 Sistema de rating** — ELO com K=32 atualizado de forma assíncrona, atômica e idempotente ao fim da partida; snapshots e histórico de variações persistidos para auditoria.
- [x] **2.5 Histórico de partidas** — Lista paginada das partidas finalizadas do usuário, com oponente, resultado sob sua perspectiva, motivo, variação de rating e data.

### Fase 3 — Matchmaking sério

- [x] **3.1 Fila por rating** — Fila por formato no Valkey, com pareamento periódico por proximidade de rating, tolerância crescente e entrada/cancelamento pelo lobby em tempo real.
- [x] **3.2 Tempo configurável** — Bullet 1+0, Blitz 3+0, Blitz 5+3 e Rapid 10+0 selecionáveis nos desafios; tempo inicial e incremento Fischer são autoritativos no `GameServer` e persistidos por partida.
- [ ] **3.3 Salas privadas** — Criação de sala com link de convite, para jogar com amigos sem passar pela fila de matchmaking.

### Fase 4 — Puzzles e análise

- [ ] **4.1 Worker Stockfish separado** — Processo isolado do game service, para não competir por recursos com partidas ao vivo.
- [ ] **4.2 Análise pós-jogo assíncrona** — Fila de análise usando Stockfish depois que a partida termina.
- [ ] **4.3 Banco de puzzles táticos** — Curadoria/geração de puzzles a partir de partidas reais.
- [ ] **4.4 Puzzle Rush** — Modo de puzzles cronometrados, estilo chess.com.

### Fase 5 — Monetização (SaaS)

- [ ] **5.1 Integração Stripe** — Cobrança recorrente.
- [ ] **5.2 Planos free/premium** — Definição de limites do plano gratuito.
- [ ] **5.3 Features pagas** — Análise ilimitada, temas de tabuleiro, remoção de anúncio (se houver).

### Fase 6 — Social e escala

- [ ] **6.1 Torneios** — Sistema de inscrição, chaveamento, ranking de torneio.
- [ ] **6.2 Clubes e chat** — Comunidades dentro da plataforma.
- [ ] **6.3 Espectadores/streaming** — Assistir partidas ao vivo de outros jogadores.
- [ ] **6.4 Multi-região** — Escala geográfica, quando o volume de usuários justificar.

### Fora do roadmap numerado, mas necessária em algum momento

- [x] **UI real de jogo** — Rota `/game/:gameId` com Chessground oficial em componente Vue, destinos legais via chess.js, drag/clique, premove, orientação por cor, relógios, jogadores, histórico e resultado em tempo real; a antiga página manual `test-game.vue` foi removida.
- [x] **Dockerização completa (desenvolvimento)** — O Compose sobe Postgres, Valkey, Phoenix e Nuxt com dependências isoladas e código montado para recarga em desenvolvimento. Imagens e configuração de produção/deploy continuam pendentes.

---

## Como trabalhar neste projeto

1. Sempre ler este arquivo por completo antes de iniciar uma tarefa nova, para entender em qual etapa do roadmap ela se encaixa e quais decisões anteriores precisam ser respeitadas
2. Seguir rigorosamente o escopo definido no prompt de cada tarefa — não expandir escopo por conta própria (ex: não adicionar autenticação "de brinde" numa tarefa que não pediu isso, mesmo que pareça relacionado)
3. Quando houver ambiguidade de implementação sem uma resposta óbvia, escolher a abordagem mais simples e idiomática em Phoenix/Elixir, e comentar brevemente a decisão no código
4. Não modificar lógica já validada e funcionando (marcada com `[x]` no roadmap acima) a menos que a tarefa seja explicitamente sobre corrigir ou alterar essa parte
5. **Ao concluir uma tarefa, atualizar a marcação da etapa correspondente neste arquivo** (`[ ]` → `[~]` → `[x]`), como parte do commit da feature — isso mantém o roadmap sempre refletindo o estado real do projeto para qualquer sessão futura, sua ou de outro desenvolvedor
