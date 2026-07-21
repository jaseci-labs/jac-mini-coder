"""byllm http_client -> ollama adapter (port 11438).

byllm's Model(config={"http_client": True, "api_base": "http://localhost:11438"})
POSTs OpenAI-style params here as one JSON body and expects one OpenAI-style
completion JSON back. We translate to ollama /api/chat with think:false and
stream:false — bypassing byllm's broken litellm dispatch entirely.
"""
import http.server
import json
import urllib.request

OLLAMA = "http://localhost:11434/api/chat"
LOG = "/home/ubuntu/jacsmith/adapter.jsonl"


class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            self._handle()
        except Exception as e:
            import traceback
            with open(LOG, "a") as f:
                f.write(json.dumps({"ERROR": repr(e), "tb": traceback.format_exc()[-600:]}) + "\n")
            resp = json.dumps({"error": str(e)}).encode()
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(resp)))
            self.end_headers()
            self.wfile.write(resp)

    def _handle(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n)
        with open(LOG, "a") as f:
            f.write(json.dumps({"RAWREQ": raw.decode("utf-8", "replace")[:1500]}) + "\n")
        p = json.loads(raw)
        model = p.get("model", "gemma4:e4b").split("/")[-1]
        def flat(c):
            if isinstance(c, list):
                return "\n".join(x.get("text", "") for x in c
                                  if isinstance(x, dict) and x.get("type") == "text")
            return c or ""
        msgs = [{"role": m.get("role", "user"), "content": flat(m.get("content"))}
                for m in p.get("messages", [])]
        body = {"model": model, "messages": msgs, "stream": False, "think": False,
                "options": {"temperature": p.get("temperature", 0.2)}}
        if p.get("max_tokens"):
            body["options"]["num_predict"] = p["max_tokens"]
        fmt = p.get("format")
        rf = p.get("response_format") or {}
        if not fmt and isinstance(rf, dict) and rf.get("type") == "json_schema":
            fmt = (rf.get("json_schema") or {}).get("schema")
        if fmt:
            body["format"] = fmt
        req = urllib.request.Request(OLLAMA, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as r:
            o = json.loads(r.read())
        with open(LOG, "a") as f:
            f.write(json.dumps({"OLLAMA_BODY": json.dumps(body)[:800],
                                "OLLAMA_RESP": json.dumps(o)[:600]}) + "\n")
        msg = o.get("message", {})
        out = {"id": "adapter", "object": "chat.completion", "model": model,
               "choices": [{"index": 0, "finish_reason": o.get("done_reason", "stop"),
                            "message": {"role": "assistant",
                                        "content": msg.get("content", "")}}],
               "usage": {"prompt_tokens": o.get("prompt_eval_count", 0),
                         "completion_tokens": o.get("eval_count", 0),
                         "total_tokens": o.get("prompt_eval_count", 0) + o.get("eval_count", 0)}}
        try:
            with open(LOG, "a") as f:
                f.write(json.dumps({"in_keys": sorted(p.keys()), "model": model,
                                    "content": msg.get("content", "")[:200]}) + "\n")
        except Exception:
            pass
        resp = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)

    def log_message(self, *a):
        pass


http.server.HTTPServer(("127.0.0.1", 11438), H).serve_forever()
