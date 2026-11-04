"""Unit tests for agent/bin/lightning: caps, the preimage and invoice never leaving the wallet's
answer, and what each step writes. A fake lexe-sidecar (tests/fake_sidecar.py) stands in for the
wallet; no wallet is opened and no money moves. Its invoices are real, signed BOLT11 invoices made
with a test key; one more is a real Lexe-made invoice from lexe-app/lexe-public's tests.

Run: python3 -I tests/test_lightning.py
"""
import contextlib, io, json, os, stat, sys, tempfile, threading, time, unittest
from http.server import HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fake_sidecar as fake  # noqa: E402
from fake_sidecar import Handler as Wallet, HASH, PAYEE, PREIMAGE, ln, make_invoice  # noqa: E402

DIGEST = "cd" * 32
INVOICE = make_invoice(500_000)
# A real invoice from lexe-app/lexe-public (lexe-api-core tests): 50 sats, with fallback tags.
LEXE_INVOICE = ("lnbc500n1pnapns2dq68skjqnr90pjjqstwv3ex76tyyqpp54yl0p0ezxl2qasdc0ect5tmxj9rdcxry7paszzdpfa5ka79t4jgscqpcsp5fc7u3hs62lr9d77xkwnjaa4fs2fch99lh96gh40kzgnufq2rvmks9qyysgqxqyz5vqnp4q0vzagw8x7r9eyalw35t0u6syql8rtqf9tejep0z6xrwkqrua5advrzjqv22wafr68wtchd4vzq7mj7zf2uzpv67xsaxcemfzak7wp7p0r29wz2g6uqqt5cqqcqqqqqqqqqqhwqqfqfhue440klc35tlmacewtk6sm3jxvkf8ddcvpggfqf4xj6mny6s7zvjwjqrjy4map9av4t82vtxrqlcqnedlwp67l6zw2x3ctf8a6amgp9v6j74")
CHARSET = ln.BECH


def read_json(path):
    with open(path) as f:
        return json.load(f)


def payment(status="completed", inbound=False, amount=500_000, fee=1000):
    return fake.payment("inbound" if inbound else "outbound", amount, fee, status=status)


class Lightning(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), Wallet)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        ln.API = f"http://127.0.0.1:{cls.server.server_port}"

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
        Wallet.calls, Wallet.payments, Wallet.script = [], [], {}

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

    def saved_invoice(self, text=None, conv="conv_1"):
        d = os.path.join(ln.DEALS, conv)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "invoice.txt"), "w") as f:
            f.write((text or INVOICE) + "\n")

    def commands(self):
        return [name for _, name, _ in Wallet.calls]

    def sent(self):
        return [b for _, name, b in Wallet.calls if name == "pay_invoice"]

    def everything_written(self, skip=()):
        text = ""
        for root, _, files in os.walk(self.tmp.name):
            for name in files:
                if name not in ("invoice.txt", "invoice.json") + tuple(skip):
                    with open(os.path.join(root, name)) as f:
                        text += f.read()
        return text

    def test_pay_within_the_caps(self):
        self.saved_invoice()
        code, out, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertEqual(code, 0, err)
        self.assertEqual(self.commands(), ["pay_invoice"], "the invoice is decoded here, not by the wallet")
        self.assertEqual(self.sent(), [{"invoice": INVOICE}])
        result = json.loads(out)
        self.assertEqual((result["paid"], result["amount_msat"], result["payment_hash"]), (True, 500_000, HASH))
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
        self.assertEqual(self.run_ln("pay", "conv_1", "500000", DIGEST)[0], 0)
        Wallet.calls = []
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("already paid", err)
        self.assertEqual(Wallet.calls, [])

    def test_over_the_per_payment_cap_nothing_is_sent(self):
        self.caps(price=500, per=400, total=1000)
        self.saved_invoice()
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("over your per-payment cap of 400 sats", err)
        self.assertEqual(self.commands(), [])
        self.assertFalse(os.path.exists(os.path.join(ln.DEALS, "conv_1", "outgoing", "buyer-terms.json")))

    def test_over_the_total_cap_nothing_is_sent(self):
        with open(ln.SPENT, "w") as f:
            json.dump({"aa" * 32: {"status": "succeeded", "reserved_msat": 0, "spent_msat": 600_000},
                       "bb" * 32: {"status": "reserved", "reserved_msat": 1_000, "spent_msat": 0}}, f)
        self.saved_invoice()
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("over your total cap of 1000 sats", err)
        self.assertEqual(self.commands(), [])

    def test_the_expected_fee_must_fit_the_caps(self):
        # 500 sats at 3201 ppm + 3 sats is 4.6 sats: a cap of 504 sats is too small, 505 is not.
        self.assertEqual(ln.est_fee(500_000), 4_601)
        self.caps(price=500, per=504, total=1000)
        self.saved_invoice()
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("fee is expected to be about 4601 msat more, over your per-payment cap of 504 sats", err)
        self.assertEqual(self.commands(), [])
        self.caps(price=500, per=505, total=504)
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertIn("over your total cap of 504 sats", err)
        self.assertEqual(self.commands(), [])
        self.caps(price=500, per=505, total=505)
        self.assertEqual(self.run_ln("pay", "conv_1", "500000", DIGEST)[0], 0)
        self.assertEqual(read_json(ln.SPENT)[HASH]["reserved_msat"], 504_601)

    def test_a_fee_over_the_estimate_is_recorded_and_said(self):
        self.saved_invoice()
        Wallet.script["pay_invoice"] = lambda b: (200, payment(fee=9_000))
        code, out, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertEqual(code, 0, err)
        self.assertIn("Lexe charged a fee of 9 sats, more than the 4601 msat expected", err)
        self.assertEqual(read_json(ln.SPENT)[HASH]["spent_msat"], 509_000)
        self.assertEqual(json.loads(out)["fee_msat"], 9_000)

    def test_expired_or_amountless_invoices_are_refused(self):
        self.saved_invoice(make_invoice(500_000, expiry=10))
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertIn("expired", err)
        self.saved_invoice(make_invoice(None))
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertIn("not a mainnet BOLT11 invoice with an amount", err)
        self.assertEqual(self.commands(), [])

    def test_no_invoice_or_no_caps(self):
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertIn("no invoice from the shop", err)
        os.remove(ln.CAPS)
        self.saved_invoice()
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertIn("no caps set", err)
        self.assertEqual(self.commands(), [])

    def test_a_failed_payment_releases_the_reservation(self):
        self.saved_invoice()
        Wallet.script["pay_invoice"] = lambda b: (200, payment(status="failed"))
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("Nothing was paid", err)
        self.assertEqual(read_json(ln.SPENT)[HASH]["status"], "failed")
        self.assertEqual(ln.spent_total(read_json(ln.SPENT)), 0)
        self.assertFalse(os.path.exists(os.path.join(ln.DEALS, "conv_1", "outgoing", "payment.json")))

    def test_a_failed_invoice_is_not_paid_again(self):
        self.saved_invoice()
        Wallet.script["pay_invoice"] = lambda b: (200, payment(status="failed"))
        self.run_ln("pay", "conv_1", "500000", DIGEST)
        Wallet.calls = []
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertIn("already failed", err)
        self.assertEqual(self.commands(), [])
        self.assertEqual(read_json(ln.SPENT)[HASH]["status"], "failed")

    def test_no_proxy_and_an_unanswered_send(self):
        os.environ["http_proxy"] = os.environ["HTTP_PROXY"] = "http://127.0.0.1:9"
        try:
            self.saved_invoice()

            def slow(b):
                time.sleep(1.5)
                return 200, payment()
            Wallet.script["pay_invoice"] = slow
            real = ln.wallet
            ln.wallet = lambda command, timeout=30, refused_ok=False: real(command, timeout=1 if command["command"] == "send" else timeout, refused_ok=refused_ok)
            try:
                code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
            finally:
                ln.wallet = real
            self.assertEqual(self.commands()[0], "pay_invoice", "the proxy in the environment was not used")
            self.assertIn("may still be in flight", err)
            self.assertEqual(read_json(ln.SPENT)[HASH]["status"], "reserved")
        finally:
            del os.environ["http_proxy"], os.environ["HTTP_PROXY"]

    def test_only_the_sats_the_user_approved(self):
        self.saved_invoice()
        code, _, err = self.run_ln("pay", "conv_1", "400000", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("asks 500 sats, not the 400 sats your user said yes to", err)
        self.assertEqual(self.commands(), [])

    def test_a_stale_terms_leg_is_not_attached(self):
        self.saved_invoice()
        out = os.path.join(ln.DEALS, "conv_1", "outgoing")
        os.makedirs(out)
        with open(os.path.join(out, "buyer-terms.json"), "w") as f:
            json.dump({"settlement": {"amount": {"value": "300000"}}}, f)
        self.assertEqual(self.run_ln("pay", "conv_1", "500000", DIGEST)[0], 0)
        self.assertEqual(read_json(os.path.join(out, "buyer-terms.json")), {}, "rewritten by terms-leg for 500000 msat")
        with open(os.path.join(self.tmp.name, "bin", "args")) as f:
            self.assertIn("--amount 500000", f.read())

    def test_the_reservation_is_made_against_the_log_as_it_is_now(self):
        # Another run's reservation written after this run first read the log still counts.
        self.caps(price=500, per=600, total=1000)
        self.saved_invoice()
        real = ln.subprocess.run

        def other_run_reserves(*a, **k):
            with open(ln.SPENT, "w") as f:
                json.dump({"ee" * 32: {"status": "reserved", "reserved_msat": 600_000, "spent_msat": 0}}, f)
            return real(*a, **k)
        ln.subprocess.run = other_run_reserves
        try:
            code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        finally:
            ln.subprocess.run = real
        self.assertIn("over your total cap", err)
        self.assertNotIn("send", self.commands())
        self.assertIn("ee" * 32, read_json(ln.SPENT), "the other run's entry is kept")

    def test_inspect_shows_sats_node_and_expiry(self):
        self.saved_invoice()
        code, out, err = self.run_ln("inspect", "conv_1")
        self.assertEqual(code, 0, err)
        r = json.loads(out)
        self.assertEqual((r["invoice_msat"], r["pays_node"], r["expired"]), (500_000, PAYEE, False))
        self.assertNotIn(INVOICE, out)
        self.assertEqual(self.commands(), [], "inspecting pays and asks nothing")

    def test_a_malformed_caps_file_is_refused_cleanly(self):
        with open(ln.CAPS, "w") as f:
            f.write("{not json")
        self.saved_invoice()
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertEqual(code, 1)
        self.assertIn("not valid JSON", err)
        self.assertEqual(self.commands(), [])

    def test_an_invoice_missing_what_receive_needs_is_refused_at_issue(self):
        good = fake._create_invoice({"amount": "500"})[1]
        for what, mutate in (("not an invoice", lambda r: dict(r, invoice="lnbc1nonsense")),
                             ("another payment hash", lambda r: dict(r, payment_hash="ab" * 32)),
                             ("a bad checksum", lambda r: dict(r, invoice=r["invoice"][:-1] + ("q" if r["invoice"][-1] != "q" else "p"))),
                             ("another amount", lambda r: dict(r, invoice=make_invoice(400_000)))):
            Wallet.script["create_invoice"] = lambda b, mutate=mutate: (200, mutate(good))
            code, _, err = self.run_ln("invoice", "conv_x")
            self.assertEqual(code, 1, what)
            self.assertIn("not a mainnet invoice for your price", err, what)

    def test_amounts_below_one_sat(self):
        # Ethan's live re-run pays 10 msat: caps, invoice and payment all work in msat.
        with open(ln.CAPS, "w") as f:
            json.dump({"price_msat": 10, "per_payment_msat": 3011, "total_msat": 9000}, f)
        code, out, err = self.run_ln("invoice", "conv_m")
        self.assertEqual(code, 0, err)
        self.assertEqual(Wallet.calls[-1][2]["amount"], "0.01", "the sidecar counts sats")
        self.assertEqual(json.loads(out)["amount_msat"], 10)
        self.saved_invoice(make_invoice(10))
        Wallet.script["pay_invoice"] = lambda b: (200, payment(amount=10, fee=0))
        code, out, err = self.run_ln("pay", "conv_1", "10", DIGEST)
        self.assertEqual(code, 0, err)
        self.assertIn("REAL Lightning payment of 10 msat", err)
        self.assertEqual(read_json(ln.SPENT)[HASH]["spent_msat"], 10)

    def test_a_refused_send_the_wallet_failed_releases_the_reservation(self):
        # Live 2026-11-01: a 10 msat send came back HTTP 400 "Lightning payment failed" and the
        # wallet recorded it failed ("could not find usable route ..."): nothing was paid.
        self.saved_invoice()
        Wallet.script["pay_invoice"] = lambda b: (400, {"error": "Lightning payment failed"})
        failed = dict(payment(status="failed"), status_msg="could not find usable route to send payment over")
        Wallet.script["payment_by_id"] = lambda b: (200, failed)
        code, _, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertIn("could not find usable route", err)
        self.assertIn("Nothing was paid", err)
        self.assertEqual(read_json(ln.SPENT)[HASH]["status"], "failed")
        self.assertEqual(ln.spent_total(read_json(ln.SPENT)), 0)

    def test_a_refused_send_the_wallet_completed_counts_as_paid(self):
        self.saved_invoice()
        Wallet.script["pay_invoice"] = lambda b: (500, {"error": "timeout waiting for the provider"})
        Wallet.script["payment_by_id"] = lambda b: (200, payment())
        code, out, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertEqual(code, 0, err)
        self.assertTrue(json.loads(out)["paid"])
        self.assertEqual(read_json(ln.SPENT)[HASH]["status"], "succeeded")
        self.assertNotIn(PREIMAGE, out + err)

    def test_wallet_errors_do_not_echo_the_invoice(self):
        self.saved_invoice()
        Wallet.script["pay_invoice"] = lambda b: (500, {"error": f"route not found for {INVOICE} hash {HASH}"})
        code, out, err = self.run_ln("pay", "conv_1", "500000", DIGEST)
        self.assertNotEqual(code, 0)
        self.assertNotIn(INVOICE, err)
        self.assertNotIn(HASH, err)
        self.assertEqual(read_json(ln.SPENT)[HASH]["status"], "reserved", "an unknown outcome stays counted")

    def test_bad_arguments(self):
        for args in (["pay", "conv 1", "500000", DIGEST], ["pay", "conv_1", "0500", DIGEST], ["pay", "conv_1", "500000", "AB" * 32]):
            self.assertEqual(self.run_ln(*args)[0], 2, args)

    def test_invoice_then_receive(self):
        code, out, err = self.run_ln("invoice", "conv_9")
        self.assertEqual(code, 0, err)
        self.assertEqual(Wallet.calls[0][2]["amount"], "500")
        self.assertNotIn(INVOICE, out)
        self.assertEqual(json.loads(out)["payment_hash"], HASH)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.join(ln.DEALS, "conv_9", "outgoing", "invoice.json")).st_mode), 0o600)
        # A second call reuses the unexpired invoice.
        self.run_ln("invoice", "conv_9")
        self.assertEqual(self.commands(), ["create_invoice"])

        code, _, err = self.run_ln("receive", "conv_9", "ab" * 32)
        self.assertIn("not the invoice you issued", err)
        code, out, err = self.run_ln("receive", "conv_9", HASH)
        self.assertEqual(code, 0, err)
        r = json.loads(out)
        self.assertEqual((r["received"], r["credited_msat"], r["fee_msat"]), (True, 495_000, 5000))
        inv, tx = read_json(r["ln_invoice"]), read_json(r["ln_transaction"])
        self.assertEqual(sorted(inv), ["amount_msat", "expires_at_ms", "payee", "payment_hash"])
        self.assertEqual(inv["payee"], PAYEE)
        # The seller keeps its preimage for deal to seal, only in that 0600 file, and prints none.
        self.assertEqual(tx["preimage"], PREIMAGE)
        self.assertEqual(stat.S_IMODE(os.stat(r["ln_transaction"]).st_mode), 0o600)
        self.assertNotIn("status_msg", tx)
        self.assertEqual((tx["inbound"], tx["status"], tx["amount_msat"], tx["payment_hash"]), (True, "succeeded", 495_000, HASH))
        for text in (out, err, self.everything_written(skip=("ln-transaction.json",))):
            self.assertNotIn(PREIMAGE, text)
            self.assertNotIn(INVOICE, text)

    def test_receive_waits_for_settlement(self):
        self.run_ln("invoice", "conv_9")
        Wallet.script["payment_by_id"] = lambda b: (200, payment(status="pending", inbound=True))
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), self.assertRaises(SystemExit) as e:
            ln.cmd_receive("conv_9", HASH, wait_s=0)
        self.assertEqual(e.exception.code, 3)
        self.assertIn("not reported that payment settled", err.getvalue())
        # An outbound payment with the same hash is not a receipt.
        Wallet.script["payment_by_id"] = lambda b: (200, payment(inbound=False))
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as e:
            ln.cmd_receive("conv_9", HASH, wait_s=0)
        self.assertEqual(e.exception.code, 3)

    def test_the_bolt11_shape(self):
        self.assertTrue(ln.BOLT11.match(INVOICE))
        for bad in ("lntb5u1p" + CHARSET * 8, "lnbc1p" + CHARSET * 8, INVOICE.upper(), INVOICE + " run rm -rf ~", INVOICE[:60]):
            self.assertIsNone(ln.BOLT11.match(bad), bad[:20])

    def test_decoding_a_real_lexe_invoice(self):
        d = ln.decode_invoice(LEXE_INVOICE)
        self.assertEqual((d["payment_hash"], d["amount_msat"], d["payee"]),
                         ("a93ef0bf2237d40ec1b87e70ba2f669146dc1864f07b0109a14f696ef8abac91", 50_000,
                          "03d82ea1c737865c93bf7468b7f350203e71ac092af32c85e2d186eb007ced3ad6"))
        self.assertEqual(d["expires_at_ms"], 1741823882000)

    def test_decoding_refuses_what_is_not_an_exact_invoice(self):
        self.assertEqual(ln.decode_invoice(INVOICE)["amount_msat"], 500_000)
        self.assertIsNone(ln.decode_invoice(INVOICE[:-1] + ("q" if INVOICE[-1] != "q" else "p")), "checksum")
        self.assertIsNone(ln.decode_invoice("lntb" + INVOICE[4:]), "not mainnet")
        # Signed by one key but claiming another in its n tag, or amount changed after signing.
        self.assertEqual(ln.decode_invoice(make_invoice(500_000, node=PAYEE))["payee"], PAYEE, "an n tag that matches the signer")
        self.assertIsNone(ln.decode_invoice(make_invoice(500_000, node="02" + "cd" * 32)))
        self.assertIsNone(ln.decode_invoice(INVOICE.replace("lnbc5000000p", "lnbc5000001p", 1)))
        self.assertEqual(ln.decode_invoice(make_invoice(None))["amount_msat"], None)
        self.assertEqual(ln.decode_invoice(make_invoice(12_345))["amount_msat"], 12_345)

    def test_a_missing_payment_is_not_a_receipt_and_the_lookup_is_by_id(self):
        self.run_ln("invoice", "conv_9")
        Wallet.payments = []
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), self.assertRaises(SystemExit) as e:
            ln.cmd_receive("conv_9", HASH, wait_s=0)
        self.assertEqual(e.exception.code, 3)
        self.assertEqual(Wallet.calls[-1][1:], ("payment_by_id", {"id": "ln_" + HASH}))

    def test_wallet_down_says_how_to_open_it(self):
        self.saved_invoice()
        real, ln.API = ln.API, "http://127.0.0.1:9"
        try:
            code, _, err = self.run_ln("invoice", "conv_d")
        finally:
            ln.API = real
        self.assertEqual(code, 1)
        self.assertIn("'devcon8 wallet' opens it", err)


if __name__ == "__main__":
    unittest.main()
