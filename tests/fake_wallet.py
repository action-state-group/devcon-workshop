"""fake_wallet.py PORT LOG: a stand-in for a node's local wallet API (/api/wallet), for
tests/sim-lightning.sh. One synthetic 500 sat invoice: `fund` issues it, `inspect_invoice` decodes
it, `send` pays it and `transactions` reports it received (495,000 msat credited, 5,000 msat fee).
Its answers carry a preimage, as a real wallet's do, so the test can check that none is kept.
No wallet is opened and no money moves. Each request's command is appended to LOG."""
import json, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer

CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
INVOICE = "lnbc5u1p" + (CHARSET * 8)[:240]
HASH = "c5" * 32
PAYEE = "02" + "ab" * 32
PREIMAGE = "9e" * 32
NOW = int(time.time() * 1000)
invoice = {"bolt11": INVOICE, "payment_hash": HASH, "payee": PAYEE, "amount_msat": 500_000, "expires_at_ms": NOW + 3_600_000}


def tx(inbound, amount, fee):
    return {"id": "t-in" if inbound else "t-out", "payment_hash": HASH, "inbound": inbound, "amount_msat": amount, "fee_msat": fee,
            "status": "succeeded", "created_at_ms": NOW - 2000, "settled_at_ms": NOW - 1000, "preimage": PREIMAGE}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(sys.argv[2], "a") as f:
            f.write(body["command"] + "\n")
        answer = {"fund": invoice, "inspect_invoice": invoice, "send": tx(False, 500_000, 1000),
                  "transactions": [tx(True, 495_000, 5000)]}.get(body["command"])
        data = json.dumps(answer).encode()
        self.send_response(200 if answer is not None else 400)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
