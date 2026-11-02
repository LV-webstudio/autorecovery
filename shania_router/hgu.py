"""Cliente del router HGU de O2/Movistar (firmware Telefónica, páginas te_*.asp).

Shania Webstudio · parte del sistema shania-autorecovery.

Hecho a partir de la ingeniería inversa del formulario de acceso y del
modelo de datos de la librería `router-movistar` (Eitol), adaptado a NUESTRO router,
que usa el CGI `te_acceso_router.cgi` con ofuscación XOR 0x1f, no la API de Eitol.

Reglas:
- La contraseña de administración NO se guarda aquí. Se pasa por argumento o por la
  variable de entorno SHANIA_ROUTER_PW (la introduce el administrador). Es la de la PEGATITA del
  router, distinta de la del Wi-Fi.
- El router tiene protección antifuerza-bruta: este cliente NO reintenta claves.
- Nada de reinicios sin confirmación explícita.

Uso rápido:
    from shania_router.hgu import HGUClient
    c = HGUClient()                       # host 192.168.1.1, clave de SHANIA_ROUTER_PW
    if c.login():
        for d in c.list_devices():
            print(d.ip, d.mac, d.name, d.interface, d.online)
        print(c.mac_for_ip("192.168.1.20"))
"""
from __future__ import annotations

import os
import re
import http.cookiejar
import urllib.parse
import urllib.request
from dataclasses import dataclass, asdict
from typing import Optional


def mess_userpass(s: str) -> str:
    """Ofuscación del router: XOR 0x1f carácter a carácter (función mess_userpass del te_util.js)."""
    return "".join(chr(ord(c) ^ 0x1F) for c in s)


@dataclass
class Device:
    ip: str
    mac: str
    name: str = ""
    interface: str = ""
    online: Optional[bool] = None

    def dict(self):
        return asdict(self)


class HGUClient:
    USERNAME = "1234"  # usuario fijo del HGU (va oculto en el formulario)
    LOGIN_PAGE = "/te_acceso_router.asp"
    LOGIN_CGI = "/cgi-bin/te_acceso_router.cgi"
    DEVICES_PAGE = "/te_red_local.asp"

    def __init__(self, host: str = "192.168.1.1", password: Optional[str] = None,
                 timeout: int = 8):
        self.base = f"http://{host}"
        self.password = password if password is not None else os.environ.get("SHANIA_ROUTER_PW")
        self.timeout = timeout
        self._cj = http.cookiejar.CookieJar()
        self._op = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self._cj),
            NoRedirect(),  # no seguir redirecciones: así detectamos el rebote al login
        )
        self.authenticated = False

    # ---- bajo nivel ----
    def _get(self, path: str):
        req = urllib.request.Request(self.base + path)
        try:
            return self._op.open(req, timeout=self.timeout)
        except urllib.error.HTTPError as e:
            return e  # un 302 llega como HTTPError con NoRedirect

    def _post(self, path: str, data: dict):
        body = urllib.parse.urlencode(data).encode()
        req = urllib.request.Request(self.base + path, data=body)
        try:
            return self._op.open(req, timeout=self.timeout)
        except urllib.error.HTTPError as e:
            return e

    def _is_login_redirect(self, resp) -> bool:
        loc = resp.headers.get("Location", "") if resp is not None else ""
        return "te_acceso_router" in loc

    # ---- API ----
    def login(self) -> bool:
        """Devuelve True solo si una página protegida carga de verdad (no rebota al login)."""
        if not self.password:
            raise RuntimeError(
                "Falta la contraseña de administración del router. Pásala por argumento "
                "o en la variable de entorno SHANIA_ROUTER_PW (es la de la pegatina, no la del Wi-Fi)."
            )
        # 1) tocar una página protegida para que el router fije la cookie de sesión
        self._get(self.DEVICES_PAGE)
        # 2) POST de login (replica exacta de lo que envía el navegador)
        self._post(self.LOGIN_CGI, {
            "Password": self.password,
            "curWebPage": self.DEVICES_PAGE,
            "loginUsername": mess_userpass(self.USERNAME),
            "loginPassword": mess_userpass(self.password),
        })
        # 3) verificar: ¿carga la página protegida o rebota al login?
        resp = self._get(self.DEVICES_PAGE)
        self.authenticated = not self._is_login_redirect(resp) and getattr(resp, "status", 200) == 200
        return self.authenticated

    def _fetch_devices_html(self) -> str:
        resp = self._get(self.DEVICES_PAGE)
        if self._is_login_redirect(resp):
            raise RuntimeError("Sesión no autenticada: llama a login() primero y comprueba la clave.")
        return resp.read().decode("latin1")

    def list_devices(self) -> list[Device]:
        """Lista los equipos de la red local con IP/MAC/nombre.

        NOTA: el HTML exacto de la tabla autenticada de te_red_local.asp se confirma en la
        primera ejecución con clave buena. De momento se extrae de forma defensiva por
        parejas IP+MAC en el documento; si el router expone un JSON interno, se añadirá aquí.
        """
        html = self._fetch_devices_html()
        return parse_devices(html)

    def mac_for_ip(self, ip: str) -> Optional[str]:
        for d in self.list_devices():
            if d.ip == ip:
                return d.mac
        return None

    def reboot(self, confirm: bool = False):
        """Reinicia el router. Requiere confirm=True. Endpoint por confirmar en la primera
        ejecución autenticada (típico: /cgi-bin/te_* de reinicio). No se llama a ciegas."""
        if not confirm:
            raise RuntimeError("reboot() necesita confirm=True (acción que corta la red). Pide confirmación al administrador.")
        raise NotImplementedError(
            "Endpoint de reinicio por confirmar con la interfaz autenticada. "
            "Alternativa validada: librería mitra_router/router-movistar según fabricante."
        )


MAC_RE = re.compile(r"(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}")
IP_RE = re.compile(r"\b(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3})\b")


def parse_devices(html: str) -> list[Device]:
    """Extrae dispositivos de la tabla de la página autenticada.

    SOLO empareja IP y MAC que viven en la MISMA fila (<tr>), que es la única correspondencia
    fiable. NO se hace emparejado posicional de IP/MAC sueltas: daría parejas falsas (una IP con
    la MAC de otro equipo) sin avisar. Si el HTML real no son filas <tr>, devuelve [] y se ajusta
    el parser al ver la página autenticada de verdad (mejor vacío que un dato inventado)."""
    devices: list[Device] = []
    for row in re.findall(r"<tr[\s>].*?</tr>", html, re.I | re.S):
        text = re.sub(r"<[^>]+>", " ", row)
        ip = IP_RE.search(text)
        mac = MAC_RE.search(text)
        if ip and mac:
            cells = [c.strip() for c in re.split(r"\s{2,}|\t", text) if c.strip()]
            name = ""
            for c in cells:
                if not IP_RE.search(c) and not MAC_RE.search(c) and len(c) < 40 and c.lower() not in ("on", "off"):
                    name = c
                    break
            devices.append(Device(ip=ip.group(), mac=_norm_mac(mac.group()), name=name))
    return devices


def _norm_mac(m: str) -> str:
    return m.lower().replace("-", ":")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # no seguir: queremos ver el 302 y su Location


if __name__ == "__main__":
    import sys, json
    cli = HGUClient(password=os.environ.get("SHANIA_ROUTER_PW"))
    if not cli.login():
        print("LOGIN FALLIDO: revisa la contraseña de administración (la de la pegatina).", file=sys.stderr)
        sys.exit(2)
    print(json.dumps([d.dict() for d in cli.list_devices()], indent=2, ensure_ascii=False))
