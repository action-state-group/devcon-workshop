"""fake_sidecar.py PORT LOG: a stand-in for lexe-sidecar's local HTTP API, for tests/sim-lightning.sh
and tests/test_lightning.py. `create_invoice` issues a real, signed mainnet BOLT11 invoice (made here
with a test key) and records it received (495 of its sats credited, 5 sats of fee); `pay_invoice`
pays any invoice and `payment_by_id` reports both. Its answers carry the preimage, as a real
sidecar's do, so the tests can check that none is kept. No wallet is opened and no money moves. Each
request's path is appended to LOG.

Importable: make_invoice() builds a signed invoice for the unit tests; Handler.script maps a
sidecar path to fn(body_or_query) -> (http_code, answer) to override one endpoint."""
import decimal, hashlib, importlib.machinery, importlib.util, json, os, sys, time, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("lightning", os.path.join(HERE, "..", "agent", "bin", "lightning"))
_spec = importlib.util.spec_from_loader("lightning", _loader)
ln = importlib.util.module_from_spec(_spec)
_loader.exec_module(ln)

PREIMAGE = "9e" * 32
HASH = hashlib.sha256(bytes.fromhex(PREIMAGE)).hexdigest()
KEY = 0x1111111111111111111111111111111111111111111111111111111111111111
_q = ln._ec_mul(KEY, ln.G)
PAYEE = (bytes([2 + (_q[1] & 1)]) + _q[0].to_bytes(32, "big")).hex()


def _groups(data):
    """Bytes as bech32's 5-bit groups, zero-padded."""
    bits = "".join(f"{b:08b}" for b in data)
    bits += "0" * (-len(bits) % 5)
    return [int(bits[i:i + 5], 2) for i in range(0, len(bits), 5)]


def _int_groups(v, n):
    return [(v >> (5 * (n - 1 - i))) & 31 for i in range(n)]


def make_invoice(amount_msat=500_000, payment_hash=HASH, created=None, expiry=3600, key=KEY):
    """A mainnet BOLT11 invoice for amount_msat (None: no amount), signed with key."""
    created = int(time.time()) if created is None else created
    hrp = "lnbc" + (f"{amount_msat * 10}p" if amount_msat is not None else "")
    body = _int_groups(created, 7)
    body += [1, 1, 20] + _groups(bytes.fromhex(payment_hash))[:52]
    body += [6, 0, 3] + _int_groups(expiry, 3)
    raw = hrp.encode() + ln._bits_to_bytes(body)
    e = int.from_bytes(hashlib.sha256(raw).digest(), "big")
    k = int.from_bytes(hashlib.sha256(raw + b"k").digest(), "big") % ln.N
    r_pt = ln._ec_mul(k, ln.G)
    r = r_pt[0] % ln.N
    s = pow(k, -1, ln.N) * (e + r * key) % ln.N
    recid = (r_pt[1] & 1) | (2 if r_pt[0] >= ln.N else 0)
    sig = _groups(r.to_bytes(32, "big") + s.to_bytes(32, "big") + bytes([recid]))
    data = body + sig[:104]
    # bech32 checksum over hrp and data
    values = [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp] + data
    mod = ln._polymod(values + [0] * 6) ^ 1
    check = [(mod >> 5 * (5 - i)) & 31 for i in range(6)]
    return hrp + "1" + "".join(ln.BECH[g] for g in data + check)


def sats(msat):
    return format(decimal.Decimal(msat) / 1000, "f")


def payment(direction, amount_msat, fee_msat, status="completed", payment_hash=HASH, preimage=PREIMAGE, invoice=None):
    now = int(time.time() * 1000)
    return {"index": f"{now:020d}-{direction[:2]}", "rail": "invoice", "kind": "invoice", "direction": direction,
            "hash": payment_hash, "preimage": preimage if status == "completed" else None, "amount": sats(amount_msat),
            "fees": sats(fee_msat), "status": status, "status_msg": "provider text", "invoice": invoice,
            "created_at": now - 2000, "finalized_at": now - 1000 if status != "pending" else None}


class Handler(BaseHTTPRequestHandler):
    script = {}
    calls = []
    payments = []

    def log_message(self, *a):
        pass

    def answer(self, code, value):
        data = json.dumps(value).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_any(self, method):
        url = urllib.parse.urlparse(self.path)
        name = url.path.rsplit("/", 1)[-1]
        n = int(self.headers.get("Content-Length") or 0)
        arg = json.loads(self.rfile.read(n)) if n else {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        Handler.calls.append((method, name, arg))
        if len(sys.argv) > 2:
            with open(sys.argv[2], "a") as f:
                f.write(name + "\n")
        fn = Handler.script.get(name, DEFAULTS.get(name))
        if fn is None:
            return self.answer(404, {"error": "no such endpoint"})
        self.answer(*fn(arg))

    do_GET = lambda self: self.handle_any("GET")
    do_POST = lambda self: self.handle_any("POST")
    do_PUT = lambda self: self.handle_any("PUT")


def _create_invoice(body):
    msat = int(decimal.Decimal(body["amount"]) * 1000)
    inv = make_invoice(msat, expiry=body.get("expiration_secs", 86400))
    Handler.payments.append(payment("inbound", msat - 5000, 5000))
    return 200, {"index": "i1", "invoice": inv, "payment_hash": HASH, "amount": body["amount"], "created_at": int(time.time() * 1000),
                 "expires_at": int(time.time() * 1000) + 86_400_000}


def _pay_invoice(body):
    d = ln.decode_invoice(body["invoice"])
    p = payment("outbound", d["amount_msat"], 1000, payment_hash=d["payment_hash"])
    Handler.payments.append(p)
    return 200, p


def _provision(body):
    # A file named by FAKE_PROVISION_FAIL makes the next provision fail once, as a Lexe outage would.
    flag = os.environ.get("FAKE_PROVISION_FAIL")
    if flag and os.path.exists(flag):
        os.remove(flag)
        return 503, {"error": "node unavailable"}
    return 200, {}


def _payment_by_id(q):
    h = q["id"].removeprefix("ln_")
    found = [p for p in Handler.payments if p["hash"] == h]
    return (200, found[-1]) if found else (404, {"error": "Payment not found"})


DEFAULTS = {
    "health": lambda b: (200, {"status": "ok"}),
    "signup": lambda b: (200, {}),
    "provision": _provision,
    "node_info": lambda b: (200, {"balance": "100000", "lightning_sendable_balance": "100000", "num_usable_channels": 1}),
    "create_invoice": _create_invoice,
    "pay_invoice": _pay_invoice,
    "payment_by_id": _payment_by_id,
}

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
