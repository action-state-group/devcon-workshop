"""Run goose against the mock ACP agent, whose first turn never ends on its own. After Ctrl-C and a typed
line, goose must have told the agent to stop (session/cancel) and the typed line must reach the agent, which
answers "second-ok". goose 1.57.0 unpatched sends no cancel, so the agent stays busy and the line never
arrives (aaif-goose/goose#10619)."""
import os, pty, re, select, sys, time

log = os.environ['ACP_LOG']
def agent_log():
    return open(log).read() if os.path.exists(log) else ''
pid, fd = pty.fork()
if pid == 0:
    os.execvp('goose', ['goose', 'run', '--recipe', sys.argv[1], '--interactive'])
raw = b''
def pump(seconds, until=lambda: False):
    global raw
    end = time.time() + seconds
    while time.time() < end and not until():
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return
            if not chunk:
                return
            raw += chunk
def screen():
    return re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)', b'', raw).decode('utf8', 'replace')
def fail(msg):
    print('FAIL ' + msg); print('agent log: ' + repr(agent_log())); print(screen()[-1200:])
    try: os.kill(pid, 9)
    except OSError: pass
    sys.exit(1)
pump(60, lambda: 'prompt 1' in agent_log())
if 'prompt 1' not in agent_log():
    fail('the agent never got the first prompt')
time.sleep(1)
os.write(fd, b'\x03')
pump(15, lambda: 'cancel' in agent_log())
if 'cancel' not in agent_log():
    fail('Ctrl-C sent no session/cancel to the agent')
time.sleep(1)
os.write(fd, b'second\r')
pump(20, lambda: 'second-ok' in screen())
if 'prompt 2' not in agent_log() or 'second-ok' not in screen():
    fail('the typed line did not reach the agent after Ctrl-C')
try: os.kill(pid, 9)
except OSError: pass
print('ok Ctrl-C cancelled the agent turn and the typed line reached it')
