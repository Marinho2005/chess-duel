import subprocess, re, time, json
from pathlib import Path
cli='/home/vimar/.npm/_npx/6de2aa2fded2970c/node_modules/agent-browser/bin/agent-browser-linux-x64'
base='http://localhost:3001'
def run(*args):
 r=subprocess.run([cli,'--session','chess-admin-test',*args],capture_output=True,text=True,timeout=35)
 if r.returncode: raise RuntimeError(r.stdout+r.stderr)
 return r.stdout.strip()
def snapshot(): return run('snapshot','-i')
def ref(kind,label):
 s=snapshot()
 for line in s.splitlines():
  line = line.strip()
  if line.startswith('- '+kind+' "'+label+'"'):
   return '@'+re.search(r'ref=(\w+)',line).group(1)
 raise RuntimeError('Missing '+label+'\n'+s)
def click(label):
 run('eval', "Array.from(document.querySelectorAll('button')).find(el => el.textContent.trim() === " + json.dumps(label) + ").click()")
def await_text(text):
 end=time.time()+20
 while time.time()<end:
  if text in run('get','text','body'): return
  time.sleep(.3)
 raise RuntimeError('Missing text '+text+'\n'+run('get','text','body'))
def navigate(path,text):
 run('open',base+path);await_text(text)
 print('PASS page '+path,flush=True)
run('open',base)
run('eval',"sessionStorage.removeItem('chess-duel:auth-token')")
run('open',base)
run('fill',ref('textbox','E-mail'),'browser_admin@example.test')
run('fill',ref('textbox','Senha'),'BrowserCheck123!')
run('eval',"document.querySelector('form').requestSubmit()")
await_text('Seu desempenho')
navigate('/admin','Usuários cadastrados')
run('screenshot','/home/vimar/fullstack-projects/chess_duel/backend/tmp/admin-verification/dashboard.png')
navigate('/admin/users','browser_player')
run('eval', "Array.from(document.querySelectorAll('a')).find(el=>el.textContent.trim()==='browser_player').click()");await_text('Histórico de moderação')
# Um token e socket emitidos antes da suspensão devem ser bloqueados.
run('eval',"""(async () => { const r = await fetch('http://localhost:4002/api/users/log_in', {method:'POST', headers:{'Content-Type':'application/json'},body:JSON.stringify({email:'browser_player@example.test',password:'BrowserCheck123!'})}); const d=await r.json(); window.testToken=d.token; window.testSocketClosed=false; window.testSocket=new WebSocket('ws://localhost:4002/socket/websocket?vsn=2.0.0&token='+d.token); window.testSocket.onclose=()=>window.testSocketClosed=true; return r.status; })()""")
click('Suspender')
assert run('eval',"document.querySelector('dialog').contains(document.activeElement)")=='true'
run('fill',ref('textbox','Motivo obrigatório'),'Verificação de suspensão pelo navegador')
run('select',ref('combobox','Duração'),'3600')
click('Confirmar: suspender');await_text('Ação registrada com sucesso.');await_text('Histórico de moderação')
assert 'Suspensa' in run('get','text','body')
assert 'Reativar' in snapshot()
result=run('eval',"""(async()=> { const r=await fetch('http://localhost:4002/api/users/me',{headers:{Authorization:'Bearer '+window.testToken}}); return {status:r.status, socketClosed:window.testSocketClosed}; })()""")
assert '403' in result and 'true' in result, result
print('PASS suspend + existing token 403 + socket disconnected',flush=True)
click('Reativar');run('fill',ref('textbox','Motivo obrigatório'),'Revisão de suspensão');click('Confirmar: reativar');await_text('Ação registrada com sucesso.');await_text('Histórico de moderação')
assert 'Suspender' in snapshot()
click('Banir');run('fill',ref('textbox','Motivo obrigatório'),'Verificação de banimento pelo navegador')
run('check',ref('checkbox','Confirmo o banimento de browser_player.'))
click('Confirmar: banir');await_text('Ação registrada com sucesso.');await_text('Histórico de moderação')
assert 'Banida' in run('get','text','body')
assert 'button "Suspender"' not in snapshot() and 'button "Banir"' not in snapshot()
click('Reativar');run('fill',ref('textbox','Motivo obrigatório'),'Revisão de banimento');click('Confirmar: reativar');await_text('Ação registrada com sucesso.');await_text('Histórico de moderação')
assert 'Verificação de suspensão pelo navegador' in run('get','text','body')
assert 'Verificação de banimento pelo navegador' in run('get','text','body')
print('PASS ban + reactivate + audit preserved',flush=True)
for theme,label in [('navy','Azul-marinho Midnight premium'),('black','Preto Grafite clássico'),('white','Branco Creme ChessDuel')]:
 click(label)
 assert theme in run('eval','document.documentElement.dataset.theme')
 run('screenshot',f'/home/vimar/fullstack-projects/chess_duel/backend/tmp/admin-verification/{theme}.png')
 print('PASS theme '+theme,flush=True)
navigate('/admin/games','browser-game')
run('eval', "Array.from(document.querySelectorAll('a')).find(el=>el.textContent.trim()==='browser-game').click()");await_text('Detalhe da partida');await_text('Posição e lances registrados')
print('PASS game detail read only',flush=True)
navigate('/admin/system','Conexão disponível')
run('set','viewport','390','844')
navigate('/admin/users','browser_player')
assert run('eval','document.documentElement.scrollWidth <= window.innerWidth')=='true'
run('screenshot','/home/vimar/fullstack-projects/chess_duel/backend/tmp/admin-verification/mobile.png')
print('PASS mobile no page overflow',flush=True)
errors=run('errors')
assert not errors,errors
print('PASS no uncaught browser errors',flush=True)
