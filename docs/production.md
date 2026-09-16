# Preparacao de producao — bloco 1

Status: infraestrutura local de release; **nao publicar o beta ainda**. E-mail real,
limites, recuperacao do Port, manutencao/draining e desativacao do OAuth somente em
producao pertencem aos proximos blocos. Nenhum servico Railway foi provisionado por
esta implementacao. O Compose de desenvolvimento permanece separado.

## Imagem e release

O contexto de build e `backend/` e o Dockerfile de producao e `backend/Dockerfile`.
A imagem compila com `MIX_ENV=prod`, sem credenciais de deploy. O runtime contem a
release OTP, Node 22, chess.js e Stockfish; nao precisa de Mix, npm ou compilador.
O dataset CSV local de puzzles e uploads existentes nao entram na imagem. Importar
puzzles no banco sera uma operacao separada, nao uma tarefa de cada deploy.

```sh
docker build -t chessduel-block1:local backend
```

O entrypoint prepara apenas os diretorios do volume no `start`, ajusta seus donos
quando iniciado como root e executa a release como usuario `chessduel` (UID 10001).
Nao altera recursivamente arquivos existentes. Avatares migrados de outro ambiente
precisam estar legiveis por esse usuario.

A migration incremental `20260911180000_upgrade_oban_to_v14.exs` atualiza o schema
Oban 12 para 14, exigido pelo Oban 2.24 do lock atual. A migration original permanece
intacta. Aplicar primeiro no banco isolado; o banco de desenvolvimento nao foi migrado
por esta tarefa.

## Variaveis do backend (runtime)

| Variavel | Valor ou regra |
|---|---|
| `PHX_HOST` | `api.chessduel.app`, sem esquema/porta |
| `FRONTEND_URL` | `https://chessduel.app` |
| `ALLOWED_ORIGINS` | Origens HTTPS exatas separadas por virgula; incluir o frontend; sem wildcard |
| `SECRET_KEY_BASE` | Segredo aleatorio com pelo menos 64 bytes; configurar no painel, nunca versionar |
| `DATABASE_URL` | URL privada do Postgres provisionado |
| `DATABASE_SSL_MODE` | Obrigatorio: `disable`, `require` ou `verify-full`; ver abaixo |
| `DATABASE_CA_CERTFILE` | Arquivo PEM confiavel acessivel no container, obrigatorio para `verify-full` |
| `POOL_SIZE` | Inteiro positivo, padrao 10 |
| `VALKEY_URL` | URL privada `redis://:senha@host:6379` do servico; o parser atual nao suporta TLS/ACL generico |
| `UPLOADS_DIR` | `/data/uploads`, diretorio absoluto no volume |
| `PORT` | Porta HTTP interna fornecida pelo Railway, padrao 4000 |
| `STOCKFISH_PATH` | `/usr/games/stockfish` ja definido na imagem |
| `LICHESS_API_TOKEN` | Opcional, segredo somente no backend |

Nao copiar as credenciais locais do Compose de teste para producao.
Os valores de banco, host, origens e volume so sao lidos no inicio da release.
`force_ssl` permanece em `prod.exs` porque Phoenix instala esse plug ao compilar;
seu host de redirecionamento e resolvido por MFA em runtime.

### TLS do Postgres: decisao ainda depende do servico real

Nao ha modo implicito nem fallback automatico:

- `verify-full`: TLS com verificacao de certificado e hostname; usar CA e nome
  correspondentes ao servidor. Modo preferivel quando suportado pelo endpoint.
- `require`: TLS **sem autenticar o servidor** (`verify_none`), para uma decisao
  explicita sobre o template autoassinado. Nao equivale a `verify-full`.
- `disable`: sem TLS, usado no teste local isolado. Nao adotar para acesso publico.

O [template oficial](https://railway.com/deploy/postgres) documenta certificado
autoassinado. Confirmar certificado, rede e endpoint do servico criado antes de
escolher o modo; nao presumir que apenas `ssl: true` resolve. Nao incluir parametros
`ssl`/`sslmode` na URL que contradigam a configuracao acima.

## Railway — configuracao manual posterior

1. Configurar Root Directory `/backend` e Config File `/backend/railway.toml`.
2. Criar Postgres e Valkey/Redis na rede privada e informar as variaveis.
3. Montar um volume no backend em `/data` e definir `UPLOADS_DIR=/data/uploads`.
4. Manter **uma replica**, uma regiao e Serverless/sleep desabilitado. Confirmar
   esses valores no painel; nao habilitar deploy automatico antes do bloco de manutencao.
5. Pre-deploy: `bin/chess_duel_backend eval 'ChessDuelBackend.Release.migrate()'`.
6. Deixar Start Command sem override: o CMD da imagem executa
   `bin/chess_duel_backend start` pelo entrypoint que prepara o volume.
7. Healthcheck: `/api/health`, que e apenas liveness, nao verifica dependencias.

O [pre-deploy](https://docs.railway.com/deployments/pre-deploy-command) roda separado,
sem volume, e falhar deve impedir a nova versao de subir. Nao iniciar toda a arvore
de jogos para migrar. Migrations precisam continuar compativeis com a versao antiga
enquanto ela estiver rodando. O mecanismo de draining ainda nao esta implementado.

O proxy termina TLS e fornece `x-forwarded-proto`. A porta interna nao deve ser
exposta diretamente a clientes nao confiaveis: a aplicacao confia nesse cabecalho,
mas nao confia em `x-forwarded-host` para escolher o destino do redirecionamento.
Somente `/api/health` e excluido do redirect HTTPS para permitir a sonda interna.
CORS REST e `check_origin` WebSocket compartilham `ALLOWED_ORIGINS`.

Backups precisam ser conferidos/ativados na aba Backups do servico; nao assumir
agendamento automatico. Teste de restauracao continua planejado para etapa posterior.

## Validacao local isolada

`compose.release-test.yml` usa projeto e volumes proprios e expoe somente a porta
4400 em loopback. Nao utiliza o banco, uploads ou `.env` do desenvolvimento.

```sh
docker compose -f compose.release-test.yml up -d postgres valkey
docker compose -f compose.release-test.yml run --rm backend bin/chess_duel_backend eval 'ChessDuelBackend.Release.migrate()'
docker compose -f compose.release-test.yml up -d backend
curl -i http://127.0.0.1:4400/api/health
curl -i -H 'X-Forwarded-Proto: https' -H 'Origin: https://chessduel.app' http://127.0.0.1:4400/api/health
docker compose -f compose.release-test.yml exec -T backend node --input-type=module < backend/test/release_smoke.mjs
docker compose -f compose.release-test.yml stop
```

Os volumes sao preservados ao parar os containers. Testar ainda reinicio com arquivo
no volume, Node/chess.js e Stockfish dentro da imagem, preflight aceito/rejeitado e
configuracao de outra origem com a **mesma imagem**. Esses checks nao substituem a
validacao de certificado/proxy no Railway apos provisionamento.
