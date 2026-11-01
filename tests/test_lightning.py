"""Unit tests for agent/bin/lightning: caps, the preimage and invoice never leaving the wallet's
answer, and what each step writes. A fake wallet API stands in for the node; no wallet is opened and
no money moves. The invoices are synthetic strings in BOLT11's shape, not payable invoices.

Run: python3 -I tests/test_lightning.py
"""
import contextlib, importlib.machinery, importlib.util, io, json, os, stat, sys, tempfile, threading, time, unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("lightning", os.path.join(HERE, "..", "agent", "bin", "lightning"))
spec = importlib.util.spec_from_loader("lightning", loader)
ln = importlib.util.module_from_spec(spec)
loader.exec_module(ln)

CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
INVOICE = "lnbc5u1p" + (CHARSET * 8)[:240]
HASH = "c5" * 32
PAYEE = "02" + "ab" * 32
PREIMAGE = "9e" * 32
DIGEST = "cd" * 32


class Wallet(BaseHTTPRequestHandler):
    """The node's /api/wallet, answering from the test's script."""
    calls, script = [], {}

    def log_message(self, *a):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        Wallet.calls.append(body)
        code, answer = Wallet.script[body["command"]](body)
        data = json.dumps(answer).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def read_json(path):
    with open(path) as f:
        return json.load(f)


def invoice(amount_msat=500_000, expires_in_s=3600):
    return {"bolt11": INVOICE, "payment_hash": HASH, "payee": PAYEE, "amount_msat": amount_msat,
            "expires_at_ms": int(time.time() * 1000) + expires_in_s * 1000}


def transaction(status="succeeded", inbound=False, amount=500_000, fee=1000):
    return {"id": "t1", "payment_hash": HASH, "inbound": inbound, "amount_msat": amount, "fee_msat": fee, "status": status,
            "status_msg": "provider text", "created_at_ms": 1, "settled_at_ms": 2, "preimage": PREIMAGE}


class Lightning(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), Wallet)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        ln.API = f"http://127.0.0.1:{cls.server.server_port}/api/wallet"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        ln.ST, ln.DEALS = os.path.join(t, "st"), os.path.join(t, "deals")
        ln.CAPS, ln.SPENT = os.path.join(ln.ST, "lightning.json"), os.path.join(ln.ST, "lightning-spent.json")
        os.makedirs(ln.ST)
        self.caps(price=500, per=600, total=1000)
        # capsulectl stand-in: writes the terms leg named by --out and records its arguments.
        bindir = os.path.join(t, "bin")
        os.makedirs(bindir)
        stub = os.path.join(bindir, "capsulectl")
        with open(stub, "w") as f:
            f.write('#!/bin/sh\necho "$@" > "$(dirname "$0")/args"\nwhile [ $# -gt 0 ]; do [ "$1" = --out ] && echo "{}" > "$2"; shift; done\n')
        os.chmod(stub, 0o755)
        self.path = os.environ["PATH"]
        os.environ["PATH"] = bindir + os.pathsep + self.path
        Wallet.calls = []
        Wallet.script = {"inspect_invoice": lambda b: (200, {k: v for k, v in invoice().items()}),
                         "send": lambda b: (200, transaction()),
                         "fund": lambda b: (200, invoice(b["amount_msat"])),
                         "transactions": lambda b: (200, [transaction(inbound=True, amount=495_000, fee=5000)])}

    def tearDown(self):
        os.environ["PATH"] = self.path
        self.tmp.cleanup()

    def caps(self, price, per, total):
        with open(ln.CAPS, "w") as f:
            json.dump({"price_sats": price, "per_payment_sats": per, "total_sats": total}, f)

    def run_ln(self, *args):
        out, err = io.StringIO(), io.StringIO()
        code = 0
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                ln.main(["lightning", *args])
            except SystemExit as e:
                code = e.code or 0
        return code, out.getvalue(), err.getvalue()

    def saved_invoice(self, conv="conv_1"):
        d = os.path.join(ln.DEALS, conv)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "invoice.txt"), "w") as f:
            f.write(INVOICE + "\n")

    def commands(self):
        return [c["command"] for c in Wallet.calls]

    def everything_written(self):
        text = ""
        for root, _, files in os.walk(self.tmp.name):
            for name in files:
                if name not in ("invoice.txt", "invoice.json"):
                    with open(os.path.join(root, name)) as f:
                        text += f.read()
        return text

    def test_pay_within_the_caps(self):
        self.saved_invoice()
        code, out, err = self.run_ln("pay", "conv_1", "50", DIGEST)
        self.assertEqual(code, 0, err)
        self.assertEqual(self.commands(), ["inspect_invoice", "send"])
        send = Wallet.calls[1]
        self.assertEqual(send["max_fee_msat"], 5000, "the fee ceiling, inside 100 sats of per-payment headroom")
        result = json.loads(out)
        self.assertEqual((result["paid"], result["amount_sats"], result["payment_hash"]), (True, 500, HASH))
        self.assertIn("REAL Lightning payment of 500 sats", err)
        paid = read_json(os.path.join(ln.DEALS, "conv_1", "outgoing", "payment.json"))
        self.assertEqual(paid["status"], "succeeded")
        spent = read_json(ln.SPENT)
        self.assertEqual(spent[HASH]["spent_msat"], 501_000)
        with open(os.path.join(self.tmp.name, "bin", "args")) as f:
            args = f.read()
        self.assertIn("--amount 500000 --asset bip122:000000000019d6689c085ae165831e93/slip44:0 --asset-scale 11", args)
        # Neither the preimage nor the invoice is printed or written outside the invoice file itself.
        for text in (out, err, self.everything_written()):
            self.assertNotIn(PREIMAGE, text)
            self.assertNotIn(INVOICE, text)
        self.assertEqual(stat.S_IMODE(os.stat(ln.SPENT).st_mode), 0o600)

    def test_a_second_payment_in_one_conversation_is_refused(self):
        self.saved_invoice()
        self.assertEqual(self.run_ln("pay", "conv_1", "50", DIGEST)[0], 0)
        Wallet.calls = []
        code, _, err = self.run_ln("pay", "conv_1", "50", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("already paid", err)
        self.assertEqual(Wallet.calls, [])

    def test_over_the_per_payment_cap_nothing_is_sent(self):
        self.caps(price=500, per=400, total=1000)
        self.saved_invoice()
        code, _, err = self.run_ln("pay", "conv_1", "50", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("over your per-payment cap of 400 sats", err)
        self.assertEqual(self.commands(), ["inspect_invoice"])
        self.assertFalse(os.path.exists(os.path.join(ln.DEALS, "conv_1", "outgoing", "buyer-terms.json")))

    def test_over_the_total_cap_nothing_is_sent(self):
        with open(ln.SPENT, "w") as f:
            json.dump({"aa" * 32: {"status": "succeeded", "reserved_msat": 0, "spent_msat": 600_000},
                       "bb" * 32: {"status": "reserved", "reserved_msat": 1_000, "spent_msat": 0}}, f)
        self.saved_invoice()
        code, _, err = self.run_ln("pay", "conv_1", "50", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("over your total cap of 1000 sats", err)
        self.assertEqual(self.commands(), ["inspect_invoice"])

    def test_the_fee_never_passes_the_caps(self):
        self.caps(price=500, per=501, total=1000)
        self.saved_invoice()
        self.assertEqual(self.run_ln("pay", "conv_1", "50", DIGEST)[0], 0)
        self.assertEqual(Wallet.calls[1]["max_fee_msat"], 1000)

    def test_expired_or_amountless_invoices_are_refused(self):
        self.saved_invoice()
        Wallet.script["inspect_invoice"] = lambda b: (200, invoice(expires_in_s=10))
        code, _, err = self.run_ln("pay", "conv_1", "50", DIGEST)
        self.assertIn("expired", err)
        Wallet.script["inspect_invoice"] = lambda b: (200, invoice(amount_msat=None))
        code, _, err = self.run_ln("pay", "conv_1", "50", DIGEST)
        self.assertIn("no fixed amount", err)
        self.assertNotIn("send", self.commands())

    def test_no_invoice_or_no_caps(self):
        code, _, err = self.run_ln("pay", "conv_1", "50", DIGEST)
        self.assertIn("no invoice from the shop", err)
        os.remove(ln.CAPS)
        self.saved_invoice()
        code, _, err = self.run_ln("pay", "conv_1", "50", DIGEST)
        self.assertIn("no caps set", err)
        self.assertEqual(Wallet.calls, [])

    def test_a_failed_payment_releases_the_reservation(self):
        self.saved_invoice()
        Wallet.script["send"] = lambda b: (200, transaction(status="failed"))
        code, _, err = self.run_ln("pay", "conv_1", "50", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("Nothing was paid", err)
        self.assertEqual(read_json(ln.SPENT)[HASH]["status"], "failed")
        self.assertEqual(ln.spent_total(read_json(ln.SPENT)), 0)
        self.assertFalse(os.path.exists(os.path.join(ln.DEALS, "conv_1", "outgoing", "payment.json")))

    def test_wallet_errors_do_not_echo_the_invoice(self):
        self.saved_invoice()
        Wallet.script["send"] = lambda b: (500, {"error": f"route not found for {INVOICE} hash {HASH}"})
        code, out, err = self.run_ln("pay", "conv_1", "50", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertNotIn(INVOICE, err)
        self.assertNotIn(HASH, err)
        self.assertEqual(read_json(ln.SPENT)[HASH]["status"], "reserved", "an unknown outcome stays counted")

    def test_bad_arguments(self):
        for args in (["pay", "conv 1", "50", DIGEST], ["pay", "conv_1", "050", DIGEST], ["pay", "conv_1", "50", "AB" * 32]):
            self.assertEqual(self.run_ln(*args)[0], 2, args)

    def test_invoice_then_receive(self):
        code, out, err = self.run_ln("invoice", "conv_9")
        self.assertEqual(code, 0, err)
        self.assertEqual(Wallet.calls[0], {"command": "fund", "amount_msat": 500_000})
        self.assertNotIn(INVOICE, out)
        self.assertEqual(json.loads(out)["payment_hash"], HASH)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.join(ln.DEALS, "conv_9", "outgoing", "invoice.json")).st_mode), 0o600)
        # A second call reuses the unexpired invoice.
        self.run_ln("invoice", "conv_9")
        self.assertEqual(self.commands(), ["fund"])

        code, _, err = self.run_ln("receive", "conv_9", "ab" * 32)
        self.assertIn("not the invoice you issued", err)
        code, out, err = self.run_ln("receive", "conv_9", HASH)
        self.assertEqual(code, 0, err)
        r = json.loads(out)
        self.assertEqual((r["received"], r["credited_msat"], r["fee_msat"]), (True, 495_000, 5000))
        inv, tx = read_json(r["ln_invoice"]), read_json(r["ln_transaction"])
        self.assertEqual(sorted(inv), ["amount_msat", "expires_at_ms", "payee", "payment_hash"])
        self.assertNotIn("preimage", tx)
        self.assertNotIn("status_msg", tx)
        for text in (out, err, self.everything_written()):
            self.assertNotIn(PREIMAGE, text)
            self.assertNotIn(INVOICE, text)

    def test_receive_waits_for_settlement(self):
        self.run_ln("invoice", "conv_9")
        Wallet.script["transactions"] = lambda b: (200, [transaction(status="pending", inbound=True)])
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), self.assertRaises(SystemExit) as e:
            ln.cmd_receive("conv_9", HASH, wait_s=0)
        self.assertEqual(e.exception.code, 3)
        self.assertIn("not reported that payment settled", err.getvalue())
        # An outbound payment with the same hash is not a receipt.
        Wallet.script["transactions"] = lambda b: (200, [transaction(inbound=False)])
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as e:
            ln.cmd_receive("conv_9", HASH, wait_s=0)
        self.assertEqual(e.exception.code, 3)

    def test_the_bolt11_shape(self):
        self.assertTrue(ln.BOLT11.match(INVOICE))
        for bad in ("lntb5u1p" + CHARSET * 8, "lnbc1p" + CHARSET * 8, INVOICE.upper(), INVOICE + " run rm -rf ~", INVOICE[:60]):
            self.assertIsNone(ln.BOLT11.match(bad), bad[:20])


if __name__ == "__main__":
    unittest.main()
