"""A stand-in for the Claude Messages API (run 2026-10-19 d) so the online bot chat (src/core/llm_chat.gd) can be
tested without a key or the internet. It answers POST /v1/messages with one short chat line and a usage block, and
writes every request it got (headers and body) to the --log file. POST /slow/v1/messages waits 8 s first (the game
must fall back to the bot's own line); POST /fail/v1/messages answers 500.

    python tools/llm_mock.py --port=8765 --log=work/llm_requests.json
"""
import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = []
LOCK = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("content-length", "0"))
        raw = self.rfile.read(n)
        try:
            body = json.loads(raw.decode("utf-8"))
        except Exception:
            body = {"_bad_json": raw.decode("utf-8", "replace")}
        with LOCK:
            LOG.append({"path": self.path, "headers": {k.lower(): (v if k.lower() != "x-api-key" else "set") for k, v in self.headers.items()},
                        "body": body, "t": time.time()})
            with open(ARGS.log, "w", encoding="utf-8") as f:
                json.dump(LOG, f, ensure_ascii=False, indent=1)
        if self.path.startswith("/slow"):
            time.sleep(8)
        if self.path.startswith("/fail"):
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b'{"type":"error","error":{"type":"api_error","message":"mock failure"}}')
            return
        user = ""
        for m in body.get("messages", []):
            if m.get("role") == "user":
                user = m.get("content", "") if isinstance(m.get("content"), str) else ""
        draft = ""
        if 'A line this player might type: "' in user:
            draft = user.split('A line this player might type: "', 1)[1].split('"', 1)[0]
        elif 'The player just wrote in ' in user:
            # an answer to the player (run 2026-10-20): echo what they wrote, so the probe can see it was answered
            said = user.split('The player just wrote in ', 1)[1].split('"', 2)[1]
            draft = "answer to " + said
        text = "mock " + (draft or "gg")
        if self.path.endswith("/chat/completions"):
            # OpenRouter (OpenAI style), with the cost it reports when usage.include is asked
            out = {"id": "gen-mock", "object": "chat.completion", "model": body.get("model", ""),
                   "choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": text}}],
                   "usage": {"prompt_tokens": 1480, "completion_tokens": 9, "prompt_tokens_details": {"cached_tokens": 1300},
                             "cost": 0.0000358}}
        else:
            out = {"id": "msg_mock", "type": "message", "role": "assistant", "model": body.get("model", ""),
                   "content": [{"type": "text", "text": text}], "stop_reason": "end_turn",
                   "usage": {"input_tokens": 180, "output_tokens": 9, "cache_read_input_tokens": 1300,
                             "cache_creation_input_tokens": 0}}
        data = json.dumps(out).encode("utf-8")
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--log", default="work/llm_requests.json")
    ARGS = ap.parse_args()
    ThreadingHTTPServer(("127.0.0.1", ARGS.port), Handler).serve_forever()
