"""Two tiny stdlib servers over the vault, no daemon needed.

  brain-loop mcp                     MCP server on stdio: tools brain, brain_open, brain_mark
                                     register: claude mcp add -s user brain -- brain-loop mcp
  brain-loop page [--port 8790]      the /brain page on 127.0.0.1 (graph, open items, notes); read-only

HTTP routes (all under /brain): /  graph.json  note?id=  open[?owner=&kind=&limit=]  open.txt[?n=]  entity?q=
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from . import common as C
from .vault import Vault

PAGE = Path(__file__).resolve().parent.parent / "page" / "brain.html"
VERSION = "0.4.2"

TOOLS = [
    {"name": "brain",
     "description": "The brain note for a project, person, commitment, decision or plan (fuzzy name, alias, email, or a "
                    "question naming one): its open items (owner, age, chase date), money, key facts, decisions, plus "
                    "1-hop linked neighbors. The vault is an Obsidian-compatible folder of linked notes.",
     "inputSchema": {"type": "object", "properties": {"entity": {"type": "string"}}, "required": ["entity"]}},
    {"name": "brain_open",
     "description": "Every open commitment: the owner's asks, items waiting on the owner, money owed. Sorted by chase_after "
                    "(chase first). owner: filter, e.g. 'owner' or a tab name. kind: ask | waiting-on-owner | money-in | money-out.",
     "inputSchema": {"type": "object", "properties": {"owner": {"type": "string"}, "kind": {"type": "string"},
                                                      "limit": {"type": "integer", "default": 60}}}},
    {"name": "brain_mark",
     "description": "Close, reassign or snooze a brain item by its id (e.g. 'c-order-3'): status 'done'/'dropped' closes it, "
                    "owner sets who chases it, chase_after 'YYYY-MM-DD' snoozes, note adds a dated line. link = comma-separated "
                    "entity slugs that replace the ones it was matched to (relabel); title renames it. Stored as my_* keys in "
                    "the note's frontmatter, which every rebuild keeps. Only record what actually happened (cite it in note).",
     "inputSchema": {"type": "object", "properties": {k: {"type": "string"} for k in
                                                      ("id", "status", "owner", "chase_after", "note", "link", "title")},
                     "required": ["id"]}},
]

VAULT = Vault()


def call(name, args):
    if name == "brain":
        return VAULT.brain(str(args.get("entity", "")))
    if name == "brain_open":
        return VAULT.brain_open(owner=args.get("owner"), kind=args.get("kind"),
                                limit=max(1, min(int(args.get("limit") or 60), 300)))
    if name == "brain_mark":
        return VAULT.mark(str(args.get("id", "")), **{k: args.get(k) for k in ("status", "owner", "chase_after", "note", "link", "title")})
    raise KeyError(name)


def mcp():
    """MCP over stdio: newline-delimited JSON-RPC 2.0."""
    def send(msg):
        sys.stdout.write(json.dumps(msg) + "\n")
        sys.stdout.flush()

    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            req = json.loads(line)
        except ValueError:
            send({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}})
            continue
        mid, method, params = req.get("id"), req.get("method", ""), req.get("params") or {}
        if mid is None:
            continue  # a notification (notifications/initialized etc.): no reply
        if method == "initialize":
            res = {"protocolVersion": params.get("protocolVersion") or "2025-06-18",
                   "capabilities": {"tools": {}}, "serverInfo": {"name": "brain-loop", "version": VERSION}}
        elif method == "ping":
            res = {}
        elif method == "tools/list":
            res = {"tools": TOOLS}
        elif method == "tools/call":
            try:
                out = call(params.get("name", ""), params.get("arguments") or {})
                res = {"content": [{"type": "text", "text": json.dumps(out, ensure_ascii=False)}],
                       "isError": isinstance(out, dict) and out.get("ok") is False}
            except KeyError:
                send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": f"unknown tool {params.get('name')}"}})
                continue
            except Exception as e:  # a tool error is a result, not a protocol error
                res = {"content": [{"type": "text", "text": f"error: {e}"}], "isError": True}
        else:
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"method not found: {method}"}})
            continue
        send({"jsonrpc": "2.0", "id": mid, "result": res})


class Page(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj, ensure_ascii=False), "application/json")

    def do_GET(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        path = u.path.rstrip("/")
        if path in ("", "/brain"):
            if u.path == "/" or (path == "/brain" and not u.path.endswith("/")):
                self.send_response(302)
                self.send_header("Location", "/brain/")
                self.end_headers()
                return
            return self._send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
        if not path.startswith("/brain/"):
            return self._send(404, "not found", "text/plain")
        part = path[len("/brain/"):]
        VAULT.load()
        if part == "graph.json":
            return self._json(VAULT.g)
        if part == "note":
            nid = q.get("id", "")
            if nid not in VAULT.nodes and nid != "index":
                return self._json({"error": "no such note"}, 404)
            fm, body = C.parse_fm(VAULT.read(nid))
            return self._json({"id": nid, "frontmatter": fm, "markdown": body,
                               "backlinks": VAULT.inn.get(nid, []), "links": VAULT.out.get(nid, [])})
        if part == "open":
            return self._json(VAULT.brain_open(owner=q.get("owner"), kind=q.get("kind"), limit=int(q.get("limit", 60))))
        if part == "open.txt":
            return self._send(200, VAULT.open_text(int(q.get("n", 15))), "text/plain; charset=utf-8")
        if part == "entity":
            return self._json(VAULT.brain(q.get("q", "")))
        return self._send(404, "not found", "text/plain")


def page(port=8790, host="127.0.0.1"):
    srv = ThreadingHTTPServer((host, port), Page)
    print(f"brain page: http://{host}:{port}/brain/  (vault {C.VAULT}; Ctrl-C stops)", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
