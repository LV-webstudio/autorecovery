"""Agente local de Shania Autorecovery (corre DENTRO de casa, en el Mac siempre encendido).

Recibe órdenes firmadas (despertar un equipo, listar dispositivos del router, reiniciar el
router) y las ejecuta en la LAN. Pensado para llegar a él SOLO por una pasarela cifrada
(Tailscale/WireGuard/Cloudflare Tunnel) — ver docs/ACCESO-REMOTO.md. NO se expone a internet
abierto, y la contraseña del router NO viaja: vive solo aquí, en SHANIA_ROUTER_PW.

Transporte (una sola vía, para no contradecirnos):
- El agente escucha SIEMPRE en 127.0.0.1 (nunca en una IP pública ni 0.0.0.0).
- Se publica cifrado con `tailscale serve`, que expone este 127.0.0.1:PUERTO como
  https://<equipo>.<tailnet>.ts.net sin abrir nada en el router. El cliente remoto usa esa URL.
  Ver docs/ACCESO-REMOTO.md.

Seguridad:
- Autenticación HMAC-SHA256 con secreto compartido (SHANIA_AGENT_TOKEN).
- La firma cubre método + ruta + timestamp + nonce + cuerpo.
- Anti-repetición REAL: ventana de 120 s por timestamp + caché de nonce (una misma petición
  firmada NO se acepta dos veces). Se rechaza un timestamp no finito (nan/inf).
- Cuerpo acotado (MAX_BODY) antes de leerlo, para no tragar peticiones enormes sin firmar.
- `reboot` exige el campo {"confirm": true}.

Arranque:
    SHANIA_AGENT_TOKEN=... SHANIA_ROUTER_PW=... python3 -m shania_router.agent --host 127.0.0.1 --port 8787
    tailscale serve --bg --https 8787 http://127.0.0.1:8787
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import math
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .cli import resolver_mac, enviar_wol, ping

WINDOW = 120            # segundos de tolerancia del timestamp
MAX_BODY = 64 * 1024    # tope del cuerpo (64 KiB): nuestras peticiones son diminutas

# caché de nonce vistos -> instante de expiración; protegido por lock (servidor multihilo)
_seen_nonces: dict[str, float] = {}
_nonces_lock = threading.Lock()


def _nonce_nuevo(nonce: str, ahora: float) -> bool:
    """True si el nonce no se había visto dentro de la ventana; lo registra. Purga los caducados."""
    if not nonce:
        return False
    with _nonces_lock:
        for n, exp in list(_seen_nonces.items()):
            if exp <= ahora:
                del _seen_nonces[n]
        if nonce in _seen_nonces:
            return False
        _seen_nonces[nonce] = ahora + WINDOW
        return True


def _token() -> bytes:
    t = os.environ.get("SHANIA_AGENT_TOKEN")
    if not t:
        raise SystemExit("Falta SHANIA_AGENT_TOKEN (secreto compartido del agente).")
    return t.encode()


def firma(token: bytes, method: str, path: str, ts: str, nonce: str, body: bytes) -> str:
    msg = (method.encode() + b"\n" + path.encode() + b"\n" + ts.encode() + b"\n"
           + nonce.encode() + b"\n" + body)
    return hmac.new(token, msg, hashlib.sha256).hexdigest()


class Handler(BaseHTTPRequestHandler):
    server_version = "ShaniaAutorecovery/0.1"

    def _responder(self, code: int, obj: dict):
        data = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _autorizar(self, body: bytes) -> bool:
        ts = self.headers.get("X-Timestamp", "")
        sig = self.headers.get("X-Signature", "")
        nonce = self.headers.get("X-Nonce", "")
        if not ts or not sig or not nonce:
            return False
        ahora = time.time()
        try:
            tsf = float(ts)
        except ValueError:
            return False
        if not math.isfinite(tsf) or abs(ahora - tsf) > WINDOW:   # rechaza nan/inf y fuera de ventana
            return False
        esperada = firma(_token(), self.command, self.path, ts, nonce, body)
        if not hmac.compare_digest(esperada, sig):
            return False
        # solo tras validar la firma consumimos el nonce (evita llenar la caché sin autenticar)
        return _nonce_nuevo(nonce, ahora)

    def do_GET(self):
        if self.path == "/health":
            return self._responder(200, {"ok": True, "service": "shania-autorecovery-agent"})
        return self._responder(404, {"error": "ruta desconocida"})

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", 0) or 0)
        except ValueError:
            return self._responder(400, {"error": "Content-Length invalido"})
        if length < 0 or length > MAX_BODY:
            return self._responder(413, {"error": "cuerpo demasiado grande"})
        body = self.rfile.read(length) if length else b""
        if not self._autorizar(body):
            return self._responder(401, {"error": "firma invalida, caducada o repetida"})
        try:
            payload = json.loads(body or b"{}")
        except json.JSONDecodeError:
            return self._responder(400, {"error": "json invalido"})
        if not isinstance(payload, dict):
            return self._responder(400, {"error": "el cuerpo debe ser un objeto JSON"})

        if self.path == "/wake":
            objetivo = str(payload.get("target", "")).strip()
            if not objetivo:
                return self._responder(400, {"error": "falta 'target'"})
            mac, ip = resolver_mac(objetivo)
            if not mac:
                return self._responder(404, {"error": f"sin MAC para {objetivo}"})
            enviar_wol(mac)
            arriba = ping(ip) if ip else None
            return self._responder(200, {"ok": True, "target": objetivo, "mac": mac, "ip": ip,
                                         "respondia_ya": arriba})

        if self.path == "/devices":
            if not os.environ.get("SHANIA_ROUTER_PW"):
                return self._responder(503, {"error": "router sin clave en el agente"})
            try:
                from .hgu import HGUClient
                c = HGUClient()
                if not c.login():
                    return self._responder(502, {"error": "login del router fallido"})
                return self._responder(200, {"ok": True, "devices": [d.dict() for d in c.list_devices()]})
            except Exception as e:
                return self._responder(502, {"error": str(e)})

        if self.path == "/reboot":
            if not payload.get("confirm"):
                return self._responder(400, {"error": "reboot requiere confirm=true"})
            return self._responder(501, {"error": "reinicio pendiente de confirmar endpoint del router"})

        return self._responder(404, {"error": "ruta desconocida"})

    def log_message(self, fmt, *args):
        pass  # silencioso; ya se orquesta por otros medios


def main(argv=None):
    ap = argparse.ArgumentParser(description="Agente local de Shania Autorecovery")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8787)
    args = ap.parse_args(argv)
    _token()  # falla pronto si no hay secreto
    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Agente escuchando en http://{args.host}:{args.port} (publícalo por el túnel cifrado).")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
