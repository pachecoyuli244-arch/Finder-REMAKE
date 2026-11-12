#!/usr/bin/env python3
"""PVFINDER Keys: private owner-only console, proxying existing PVFinder admin API."""
import os
import time
import json
import hmac
import secrets
import hashlib
import threading
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from pathlib import Path

ROOT = Path(__file__).resolve().parent
UPSTREAM = os.environ.get("PVFINDER_BASE_URL", "https://pvfinder.onrender.com").rstrip("/")
if not UPSTREAM.startswith("https://"):
    raise SystemExit("PVFINDER_BASE_URL debe utilizar HTTPS")
SESSIONS = {}
ATTEMPTS = {}
LOCK = threading.RLock()
SESSION_TTL = 8 * 3600

def timestamp():
    return int(time.time())

def sha(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

def limit_login(ip):
    with LOCK:
        now = timestamp()
        ATTEMPTS[ip] = [t for t in ATTEMPTS.get(ip, []) if now-t < 900]
        if len(ATTEMPTS) > 5000:
            for k in list(ATTEMPTS)[:2500]:
                if k != ip: ATTEMPTS.pop(k, None)
        if len(ATTEMPTS[ip]) >= 8:
            return False
        ATTEMPTS[ip].append(now)
        return True

def upstream(method, route, payload=None, cookie=None):
    data = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
    headers = {"Accept": "application/json"}
    if data is not None: headers["Content-Type"] = "application/json"
    if cookie: headers["Cookie"] = cookie
    req = Request(UPSTREAM + route, method=method, data=data, headers=headers)
    try:
        with urlopen(req, timeout=15) as response:
            return response.status, json.loads(response.read(500000)), response.headers.get("Set-Cookie", "")
    except HTTPError as exc:
        try: body = json.loads(exc.read(50000))
        except Exception: body = {"error": "Error de PVFinder"}
        return exc.code, body, ""
    except (URLError, TimeoutError, ValueError):
        return 502, {"error":"No se pudo conectar a PVFinder"}, ""

class Handler(BaseHTTPRequestHandler):
    server_version = "PVFINDER-KeyConsole"
    def log_message(self, format, *args):
        # Do not record passwords, tokens, keys, paths or request bodies.
        return
    def headers_safe(self, typ="application/json; charset=utf-8"):
        self.send_header("Content-Type", typ)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        self.send_header("Strict-Transport-Security", "max-age=31536000")
        self.send_header("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
    def send(self, status, body, cookie=None):
        content = json.dumps(body, ensure_ascii=False, separators=(",",":")).encode("utf-8")
        self.send_response(status)
        self.headers_safe()
        if cookie is not None: self.send_header("Set-Cookie", cookie)
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)
    def session_cookie(self, sid="", age=0):
        return "pvkeys_session=" + sid + "; Path=/; Max-Age=" + str(age) + "; HttpOnly; SameSite=Strict; Secure"
    def session(self):
        try:
            cookies = SimpleCookie()
            cookies.load(self.headers.get("Cookie", ""))
            sid = cookies.get("pvkeys_session")
            if not sid or len(sid.value) > 180: return None
            with LOCK:
                record = SESSIONS.get(sha(sid.value))
                if not record: return None
                if record["expires"] <= timestamp():
                    SESSIONS.pop(sha(sid.value), None)
                    return None
                return record["upstream"]
        except Exception:
            return None
    def body(self):
        try: size = int(self.headers.get("Content-Length", "0"))
        except ValueError: raise ValueError("Tamaño inválido")
        if size < 1 or size > 4096: raise ValueError("Solicitud demasiado grande")
        data = json.loads(self.rfile.read(size))
        if not isinstance(data, dict): raise ValueError("Formato inválido")
        return data
    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/health": return self.send(200, {"ok": True, "service":"PVFINDER KEYS"})
        if path == "/api/me":
            return self.send(200, {"authenticated":bool(self.session())})
        if path == "/api/keys":
            cookie = self.session()
            if not cookie: return self.send(401, {"error":"Inicia sesión como dueño"})
            status, data, _ = upstream("GET", "/api/editor/keys", cookie=cookie)
            if status == 401: return self.send(401, {"error":"Sesión de PVFinder expirada"})
            if status != 200: return self.send(status, {"error":data.get("error", "No se pudo consultar las llaves")})
            return self.send(200, data)
        static = {"/":("key_console.html","text/html; charset=utf-8"),
                  "/app.js":("key_console.js","application/javascript; charset=utf-8"),
                  "/app.css":("key_console.css","text/css; charset=utf-8")}
        if path not in static: return self.send(404, {"error":"Ruta no encontrada"})
        name,typ = static[path]
        try: content = (ROOT/name).read_bytes()
        except OSError: return self.send(500, {"error":"Archivo no disponible"})
        self.send_response(200)
        self.headers_safe(typ)
        self.send_header("Content-Length",str(len(content)))
        self.end_headers()
        self.wfile.write(content)
    def do_POST(self):
        path = urlsplit(self.path).path
        host = self.headers.get("Host","")
        origin = self.headers.get("Origin","")
        if (origin and origin not in ("https://"+host,"http://"+host)) or self.headers.get("X-PV-Request") != "1":
            return self.send(403, {"error":"Solicitud no autorizada"})
        if path not in ("/api/login","/api/keys","/api/logout"):
            return self.send(404, {"error":"Ruta no encontrada"})
        try: data = self.body()
        except (ValueError,json.JSONDecodeError):
            return self.send(400, {"error":"Datos inválidos"})
        if path == "/api/login":
            if not limit_login(self.client_address[0]):
                return self.send(429, {"error":"Demasiados intentos. Intenta más tarde"})
            password = data.get("password")
            if not isinstance(password,str) or not 12 <= len(password) <= 200:
                return self.send(401, {"error":"Credenciales inválidas"})
            status, result, set_cookie = upstream("POST","/api/admin/login",{"password":password})
            if status != 200 or result.get("role") != "admin":
                return self.send(401 if status == 401 else status, {"error":result.get("error","No se pudo iniciar sesión")})
            upstream_cookies = SimpleCookie()
            try: upstream_cookies.load(set_cookie)
            except Exception: pass
            upstream_session = upstream_cookies.get("pvf_session")
            if not upstream_session:
                return self.send(502, {"error":"No se recibió sesión administrativa"})
            token = secrets.token_urlsafe(36)
            with LOCK:
                if len(SESSIONS) > 5000:
                    for k,v in list(SESSIONS.items()):
                        if v["expires"] <= timestamp(): SESSIONS.pop(k,None)
                SESSIONS[sha(token)] = {"upstream":"pvf_session="+upstream_session.value,
                                        "expires":timestamp()+SESSION_TTL}
            return self.send(200, {"ok":True}, self.session_cookie(token,SESSION_TTL))
        cookie = self.session()
        if not cookie: return self.send(401, {"error":"Inicia sesión como dueño"})
        if path == "/api/logout":
            try:
                cookies = SimpleCookie(self.headers.get("Cookie",""))
                sid = cookies.get("pvkeys_session")
                if sid:
                    with LOCK: SESSIONS.pop(sha(sid.value), None)
            except Exception: pass
            return self.send(200, {"ok":True}, self.session_cookie("",0))
        if data.get("action") not in ("create","revoke","uid","username"):
            return self.send(400,{"error":"Acción no permitida"})
        status, result, _ = upstream("POST","/api/editor/keys",data,cookie)
        if status == 401: return self.send(401,{"error":"Tu sesión de PVFinder expiró"})
        return self.send(status,result)

if __name__ == "__main__":
    port = int(os.environ.get("PORT","10000"))
    print("PVFINDER Keys listening on",port,flush=True)
    ThreadingHTTPServer(("0.0.0.0",port),Handler).serve_forever()
