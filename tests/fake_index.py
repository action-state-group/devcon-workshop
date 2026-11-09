"""fake_index.py PORT LOG [drop]: a stand-in for the Agent Box gateway and the NANDA Index, for
tests/test_nanda_offer.sh. It serves what `devcon8 nanda offer` calls: the mailbox's org id, the reset
mail in the inbox, the Index sign-in, GET/PUT of the org record and resolve. The org record starts with
other metadata the command must leave alone. With "drop" a PUT forgets trust_manifest.metadata, as an
Index that did not keep it would. Every request is appended to LOG."""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

TOKEN = "ab" * 16
org = {"org_id": "o1", "display_name": "Devcon 8 workshop agent", "description": "demo", "tags": ["fox"], "ttl_seconds": 86400,
       "version": None, "extensions": {"org.projectnanda": {"x": 1}}, "registry_url": "https://r.example/agents/m1",
       "domain": None, "trust_manifest": {"identity": "m1", "metadata": {"keep": "me"}}}
sent_reset = []
drop = sys.argv[3:] == ["drop"]


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

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def record(self, b=None):
        with open(sys.argv[2], "a") as f:
            f.write(f"{self.command} {self.path} {json.dumps(b) if b else ''}\n")

    def authed(self):
        return self.headers.get("Authorization") == "Bearer jwt1"

    def do_GET(self):
        self.record()
        if self.path == "/api/agent/mailboxes/m1":
            return self.reply(200, {"mailbox": {"id": "m1"}, "discovery": {"orgId": "o1", "status": "indexed"}})
        if self.path.startswith("/api/v1/inbox"):
            after = int(dict(kv.split("=") for kv in self.path.split("?", 1)[1].split("&")).get("after", 0))
            msgs = [{"seq": 1, "kind": "general"}]
            for n in range(len(sent_reset)):  # one reset mail per request, each newer than the last
                msgs.append({"seq": 2 + n, "kind": "email", "sender": "urn:ai:email:noreply@nandaindex.org",
                             "email": {"subject": "Reset your password"}, "text": "https://x/reset?token=" + TOKEN})
            return self.reply(200, {"messages": [m for m in msgs if m["seq"] > after]})
        if self.path == "/api/v1/orgs/o1":
            return self.reply(200, org) if self.authed() else self.reply(401, {"error": "no"})
        if self.path.startswith("/api/v1/resolve"):
            tm = org.get("trust_manifest") or {}
            return self.reply(200, {"entry": {"trustManifest": tm, "extensions": {"org.projectnanda": {"status": "active"}}}})
        self.reply(404, {"error": "no route"})

    def do_POST(self):
        b = self.body()
        self.record(b)
        if self.path == "/auth/forgot-password":
            sent_reset.append(1)
            return self.reply(200, {})
        if self.path == "/auth/reset-password":
            return self.reply(200 if b.get("token") == TOKEN else 400, {})
        if self.path == "/auth/login":
            return self.reply(200, {"token": "jwt1"})
        self.reply(404, {"error": "no route"})

    def do_PUT(self):
        b = self.body()
        self.record(b)
        if self.path != "/api/v1/orgs/o1" or not self.authed():
            return self.reply(401, {"error": "no"})
        tm = b.get("trust_manifest")
        if drop and isinstance(tm, dict):
            tm = {k: v for k, v in tm.items() if k != "metadata"}
        org["trust_manifest"] = tm
        self.reply(200, org)


HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
