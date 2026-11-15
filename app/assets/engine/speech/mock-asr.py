#!/usr/bin/env python3
"""Mock 的 OpenAI 兼容 /v1/audio/transcriptions：验证云端 provider 的请求与失败分类。
python3 mock-asr.py [port] [token]"""
import json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8791
TOKEN = sys.argv[2] if len(sys.argv) > 2 else "sk-remote"

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        if self.path.rstrip("/") != "/v1/audio/transcriptions":
            return self._json(404, {"error": "not found"})
        if self.headers.get("Authorization", "") != f"Bearer {TOKEN}":
            return self._json(401, {"error": {"message": "bad key"}})
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        if b'name="file"' not in raw or b'name="model"' not in raw:
            return self._json(400, {"error": "missing file or model"})
        return self._json(200, {"text": "云端识别结果"})

if __name__ == "__main__":
    print(f"mock asr on 127.0.0.1:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
