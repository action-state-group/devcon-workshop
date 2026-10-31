"""fake_agentbox.py PORT LOG: a stand-in for the Agent Box gateway and the NANDA Index resolve call,
for tests/test_nanda.sh. It answers as the real gateway did for a key that REJOINED a mailbox
someone already verified: GET /mailboxes/<id> says mailbox.verified true, but this key is off duty
until it is verified itself. Every request is appended to LOG."""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

state = {"key_verified": False, "on_duty": False}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def record(self, body=None):
        with open(sys.argv[2], "a") as f:
            f.write(f"{self.command} {self.path} {json.dumps(body) if body else ''}\n")

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def do_GET(self):
        self.record()
        if self.path.startswith("/api/v1/resolve"):
            ok = state["key_verified"]
            return self.reply(200 if ok else 404, {"entry": {"extensions": {"org.projectnanda": {"status": "active"}}}} if ok else {"error": "not_found"})
        if self.path == "/api/agent/mailboxes/m1":
            return self.reply(200, {"mailbox": {"id": "m1", "verified": True}, "discovery": {"orgId": "o1", "status": "indexed"}})
        if self.path == "/api/v1/me":
            return self.reply(200, {"onDuty": state["on_duty"]})
        self.reply(404, {"error": "no route"})

    def do_POST(self):
        b = self.body()
        self.record(b)
        if self.path == "/api/agent/mailboxes":
            return self.reply(201, {"mailbox": {"id": "m1", "emailAddress": "m1@agentboxnanda.org", "verified": True},
                                    "token": "test-token", "existing": True, "verified": False, "codeSentTo": "p@example.com"})
        if self.path == "/api/agent/mailboxes/m1/verify":
            state["key_verified"] = b.get("code") == "123456"
            return self.reply(200 if state["key_verified"] else 400, {"verified": state["key_verified"]})
        if self.path == "/api/agent/mailboxes/m1/duty":
            if not state["key_verified"]:
                return self.reply(409, {"error": {"code": "not_verified"}})
            state["on_duty"] = True
            return self.reply(200, {"onDuty": True})
        if self.path == "/api/agent/mailboxes/m1/nanda":
            return self.reply(200, {})
        self.reply(404, {"error": "no route"})


HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
