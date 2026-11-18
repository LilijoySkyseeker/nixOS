"""Stands in for llama-server: appends the sampling and template fields of each request to argv[1]."""
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(s):
        b = json.loads(s.rfile.read(int(s.headers['content-length'])))
        keep = {k: b.get(k) for k in ("chat_template_kwargs","temperature","top_p","presence_penalty","reasoning_effort")}
        open(sys.argv[1],"a").write(json.dumps(keep)+"\n")
        s.send_response(500); s.end_headers()
    def log_message(s,*a): pass
http.server.HTTPServer(("127.0.0.1",18093),H).serve_forever()
