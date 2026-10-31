"""fake_conversations.py PORT: a stand-in for the Agent Box gateway's agent-to-agent messaging, for
tests/test_trade_protocol.sh. It enforces the conversation rule the real gateway applies
(dhve/nanda-messagebox-skill legacy/SKILL.md, "Conversation state"; the real gateway answered a
seller's confirm with 409 invalid_transition "Confirmation must reference latest acceptance", 10-31):
a request opens a conversation and names its original requester; either side proposes; the other
side accepts the latest proposal (proposalId); only the original requester confirms, naming the
latest acceptance (acceptanceId). Two mailboxes: tokens tok-buyer and tok-seller."""
import json, sys, uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlsplit, parse_qs

URN = "urn:air:host39.org:personal:"
BOXES = {"tok-buyer": "buyer@agentboxnanda.org", "tok-seller": "shop@agentboxnanda.org"}
inbox = {a: [] for a in BOXES.values()}
convs = {}
seq = [0]


def deliver(to, msg):
    seq[0] += 1
    inbox[to].append(dict(msg, seq=seq[0]))


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

    def me(self):
        return BOXES.get(self.headers.get("Authorization", "").removeprefix("Bearer "))

    def do_GET(self):
        me = self.me()
        u = urlsplit(self.path)
        if u.path == "/api/v1/inbox" and me:
            after = int(parse_qs(u.query).get("after", ["0"])[0])
            return self.reply(200, {"messages": [m for m in inbox[me] if m["seq"] > after][:10]})
        self.reply(404, {"error": "no route"})

    def do_POST(self):
        me = self.me()
        b = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        if not me:
            return self.reply(401, {"error": {"code": "invalid_token"}})
        if self.path == "/api/v1/messages":
            to = b.get("to", "").removeprefix(URN)
            if to not in inbox or to == me:
                return self.reply(409, {"error": {"code": "invalid_recipient"}})
            cid, mid = uuid.uuid4().hex, uuid.uuid4().hex
            convs[cid] = {"requester": me, "other": to, "proposal": None, "acceptance": None, "done": False}
            deliver(to, {"id": mid, "conversationId": cid, "kind": "request", "sender": URN + me,
                         "text": b.get("text", ""), "constraints": b.get("constraints", {})})
            return self.reply(201, {"message": {"id": mid, "conversationId": cid}})
        parts = self.path.split("/")
        if len(parts) == 6 and parts[1:4] == ["api", "v1", "conversations"] and parts[5] == "replies":
            c = convs.get(parts[4])
            if not c or me not in (c["requester"], c["other"]) or c["done"]:
                return self.reply(404, {"error": {"code": "not_found"}})
            kind, k = b.get("kind"), b.get("constraints") or {}
            mid = uuid.uuid4().hex
            if kind == "proposal":
                c["proposal"] = (mid, me); c["acceptance"] = None
            elif kind == "accept":
                if not c["proposal"] or k.get("proposalId") != c["proposal"][0] or c["proposal"][1] == me:
                    return self.reply(409, {"error": {"code": "invalid_transition", "message": "Acceptance must reference latest proposal"}})
                c["acceptance"] = mid
            elif kind == "confirm":
                if me != c["requester"] or not c["acceptance"] or k.get("acceptanceId") != c["acceptance"]:
                    return self.reply(409, {"error": {"code": "invalid_transition", "message": "Confirmation must reference latest acceptance"}})
                c["done"] = True
            elif kind in ("decline", "cancel"):
                c["done"] = True
            else:
                return self.reply(400, {"error": {"code": "bad_kind"}})
            to = c["other"] if me == c["requester"] else c["requester"]
            deliver(to, {"id": mid, "conversationId": parts[4], "kind": kind, "sender": URN + me,
                         "text": b.get("text", ""), "constraints": k})
            return self.reply(201, {"message": {"id": mid, "conversationId": parts[4]}})
        self.reply(404, {"error": "no route"})


HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
