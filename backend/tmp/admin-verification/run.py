import subprocess, os, time
from pathlib import Path
root=Path('/home/vimar/fullstack-projects/chess_duel')
folder=root/'backend/tmp/admin-verification'
log=open(folder/'server.log','w')
server=subprocess.Popen(['mix','run','--no-start','tmp/admin-verification/server.exs'],cwd=root/'backend',env={**os.environ,'MIX_ENV':'test'},stdout=log,stderr=subprocess.STDOUT)
try:
 for _ in range(60):
  if server.poll() is not None: raise RuntimeError('Test API failed to start')
  if 'BROWSER_CHECK_READY' in (folder/'server.log').read_text(): break
  time.sleep(.5)
 else: raise RuntimeError('Test API not ready')
 subprocess.run(['python3',str(folder/'browser.py')],check=True)
finally:
 server.terminate()
 try: server.wait(timeout=10)
 except subprocess.TimeoutExpired: server.kill()
