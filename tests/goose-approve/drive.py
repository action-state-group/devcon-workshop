"""Run goose in approve mode against the mock ACP agent and answer each approval card with Enter.
Passes only if the one card appears exactly once, the turn finishes ("done"), and goose does not print
the "already answered" error or show the card again afterwards (aaif-goose/goose#13273)."""
import os, pty, re, select, sys, time

pid, fd = pty.fork()
if pid == 0:
    os.execvp('goose', ['goose', 'run', '--recipe', sys.argv[1], '--interactive'])
raw, seen_cards, answered, done_at = b'', 0, 0, None
start = time.time()
while time.time() - start < 90:
    ready, _, _ = select.select([fd], [], [], 0.2)
    if ready:
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        raw += chunk
    text = re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)', b'', raw).decode('utf8', 'replace')
    seen_cards = text.count('Tool approval request')
    if seen_cards > answered:
        time.sleep(0.5)
        os.write(fd, b'\r')
        answered += 1
    if done_at is None and re.search(r'^\s*done', text, re.M):
        done_at = time.time()
    if done_at is not None and time.time() - done_at > 5:
        break
text = re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)', b'', raw).decode('utf8', 'replace')
try:
    os.kill(pid, 9)
except OSError:
    pass
if 'already answered' in text:
    print('FAIL goose exited with "already answered"'); sys.exit(1)
if done_at is None:
    print('FAIL the turn did not finish'); print(text[-1500:]); sys.exit(1)
if answered != 1 or text.count('Tool approval request') != 1:
    print(f'FAIL the approval card came back (answered {answered}, drawn {text.count("Tool approval request")} times)'); sys.exit(1)
print('ok one approval card, turn finished')
