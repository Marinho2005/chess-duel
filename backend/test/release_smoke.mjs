// Executar por stdin com node --input-type=module dentro do container de release.
// Nao imprime token de convidado, credenciais ou corpos de autenticacao.
import assert from 'node:assert/strict'
import http from 'node:http'
import { randomBytes } from 'node:crypto'
import { readdir, readFile, writeFile, access } from 'node:fs/promises'
import { spawn } from 'node:child_process'

const origin = process.env.FRONTEND_URL
const deniedOrigin = process.env.RELEASE_TEST_REJECTED_ORIGIN || 'https://untrusted.example'
const url = 'http://127.0.0.1:' + (process.env.PORT || '4000')
const headers = { 'x-forwarded-proto': 'https', origin }
const health = await fetch(url + '/api/health', { headers })
assert.equal(health.status, 200)
assert.equal(health.headers.get('access-control-allow-origin'), origin)
const live = await fetch(url + '/api/games/live', { headers })
assert.equal(live.status, 200)
assert.ok(live.headers.get('strict-transport-security'))
assert.equal((await fetch(url + '/api/health')).status, 200)

const preflight = await fetch(url + '/api/games/live', {
  method: 'OPTIONS', headers: { ...headers, 'access-control-request-method': 'GET' },
})
assert.equal(preflight.status, 204)
assert.equal(preflight.headers.get('access-control-allow-origin'), origin)
const denied = await fetch(url + '/api/health', {
  headers: { ...headers, origin: deniedOrigin },
})
assert.equal(denied.headers.get('access-control-allow-origin'), null)
const redirect = await fetch(url + '/api/games/live', { redirect: 'manual' })
assert.equal(redirect.status, 301)
assert.equal(redirect.headers.get('location'), 'https://' + process.env.PHX_HOST + '/api/games/live')

const guest = await fetch(url + '/api/guests/session', { method: 'POST', headers })
assert.equal(guest.status, 200)
const { token } = await guest.json()
assert.equal(typeof token, 'string')
function handshake(requestOrigin) {
  return new Promise((resolve, reject) => {
    const request = http.request(url + '/socket/websocket?vsn=2.0.0&token=' + encodeURIComponent(token), {
      headers: { ...headers, origin: requestOrigin, connection: 'Upgrade', upgrade: 'websocket',
        'sec-websocket-key': randomBytes(16).toString('base64'), 'sec-websocket-version': '13' },
    })
    request.setTimeout(5000, () => request.destroy(new Error('WebSocket timeout')))
    request.on('upgrade', (response, socket) => { socket.destroy(); resolve(response.statusCode) })
    request.on('response', response => { response.resume(); resolve(response.statusCode) })
    request.on('error', reject)
    request.end()
  })
}
assert.equal(await handshake(origin), 101)
assert.equal(await handshake(deniedOrigin), 403)

const app = (await readdir('/app/lib')).find(name => name.startsWith('chess_duel_backend-'))
const script = '/app/lib/' + app + '/priv/chess_validator/validator.js'
function subprocess(command, args, input, marker) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['pipe', 'pipe', 'pipe'] })
    let output = ''
    const timeout = setTimeout(() => { child.kill(); reject(new Error('Subprocess timeout')) }, 10000)
    child.on('error', error => { clearTimeout(timeout); reject(error) })
    child.stdout.on('data', data => { output += data })
    child.stderr.resume()
    child.on('close', code => {
      clearTimeout(timeout)
      try { assert.equal(code, 0); assert.ok(output.includes(marker)); resolve() } catch (error) { reject(error) }
    })
    child.stdin.end(input)
  })
}
await subprocess('node', [script], JSON.stringify({ action: 'validate_move',
  fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', from: 'e2', to: 'e4' }) + '\n', '"san":"e4"')
await subprocess(process.env.STOCKFISH_PATH, [], 'uci\nquit\n', 'uciok')
await assert.rejects(access('/usr/local/bin/npm'))
await assert.rejects(access('/app/bin/mix'))

// Preservar o marcador entre reinicios para comprovar que o volume nao e efemero.
const marker = process.env.UPLOADS_DIR + '/avatars/release-smoke.txt'
try {
  assert.equal(await readFile(marker, 'utf8'), 'persistent-release-smoke')
  console.log('Upload persistente encontrado em execucao posterior.')
} catch (error) {
  if (error.code !== 'ENOENT') throw error
  await writeFile(marker, 'persistent-release-smoke')
}
const uploaded = await fetch(url + '/uploads/avatars/release-smoke.txt', { headers })
assert.equal(uploaded.status, 200)
assert.equal(await uploaded.text(), 'persistent-release-smoke')
console.log('PASS: HTTP, HTTPS/proxy, CORS, WebSocket 101/403, Node/chess.js, Stockfish e uploads.')
