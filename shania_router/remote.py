"""Cliente remoto de Shania Autorecovery (desde FUERA de casa).

Firma cada petición con el secreto compartido y llama al agente a través de la pasarela
cifrada. Usamos UNA sola vía: `tailscale serve` publica el agente (que escucha en
127.0.0.1) como https://<equipo>.<tailnet>.ts.net, sin abrir nada en el router. La
contraseña del router NO se usa aquí: la tiene el agente en casa.

Variables de entorno:
  SHANIA_AGENT_URL    la URL de Tailscale, p. ej. https://mac-casa.tu-tailnet.ts.net
  SHANIA_AGENT_TOKEN  el mismo secreto que el agente

Ejemplos:
  python3 -m shania_router.remote wake pc
  python3 -m shania_router.remote devices
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request


def _cfg():
    url = os.environ.get("SHANIA_AGENT_URL")
    tok = os.environ.get("SHANIA_AGENT_TOKEN")
    if not url or not tok:
        raise SystemExit("Faltan SHANIA_AGENT_URL y/o SHANIA_AGENT_TOKEN.")
    return url.rstrip("/"), tok.encode()


def _llamar(path: str, payload: dict):
    url, tok = _cfg()
    body = json.dumps(payload, ensure_ascii=False).encode()
    ts = f"{time.time():.3f}"
    nonce = secrets.token_hex(16)   # único por petición: el agente lo cachea y no acepta repeticiones
    msg = b"POST\n" + path.encode() + b"\n" + ts.encode() + b"\n" + nonce.encode() + b"\n" + body
    sig = hmac.new(tok, msg, hashlib.sha256).hexdigest()
    req = urllib.request.Request(url + path, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Timestamp", ts)
    req.add_header("X-Nonce", nonce)
    req.add_header("X-Signature", sig)
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "{}")
        except (ValueError, OSError):
            return e.code, {"error": f"HTTP {e.code}"}
    except urllib.error.URLError as e:
        raise SystemExit(f"No se pudo contactar con el agente ({url}): {e.reason}. "
                         f"¿Está levantado y publicado con tailscale serve?")


def main(argv=None):
    argv = argv or sys.argv[1:]
    if not argv:
        print(__doc__)
        return 1
    cmd, *rest = argv
    if cmd == "wake" and rest:
        code, resp = _llamar("/wake", {"target": rest[0]})
    elif cmd == "devices":
        code, resp = _llamar("/devices", {})
    elif cmd == "reboot":
        code, resp = _llamar("/reboot", {"confirm": "--si" in rest})
    else:
        print(__doc__)
        return 1
    print(json.dumps(resp, ensure_ascii=False, indent=2))
    return 0 if code == 200 else 2


if __name__ == "__main__":
    raise SystemExit(main())
