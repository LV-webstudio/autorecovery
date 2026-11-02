"""CLI de Shania Autorecovery: resolver MAC y despertar equipos por LAN.

Resuelve la MAC de un equipo en este orden (de más fiable a menos):
  1) tabla local  ~/.config/autorecovery/macs.txt
  2) caché ARP viva del propio equipo (arp -an)   (tolera el formato abreviado de macOS)
  3) el router HGU (requiere SHANIA_ROUTER_PW, la clave de la pegatina)

Si falla todo, scripts/buscar-mac-en-logs.sh rescata la MAC de tablas ARP ya registradas
(es un ayudante manual, no un paso automático). Luego manda el paquete mágico y comprueba con ping.

Ejemplos:
  python3 -m shania_router.cli wake pc
  python3 -m shania_router.cli mac 192.168.1.20
  python3 -m shania_router.cli devices        # necesita clave del router
"""
from __future__ import annotations

import os
import re
import socket
import subprocess
import sys
import time

MACS_TXT = os.path.expanduser("~/.config/autorecovery/macs.txt")
MAC_RE = re.compile(r"(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}")
# macOS imprime las MAC sin el cero inicial de cada octeto (aa:b:c en vez de aa:0b:0c);
# esta versión acepta 1 o 2 dígitos por octeto y luego se rellena con pad_mac().
MAC_RE_LOOSE = re.compile(r"(?:[0-9A-Fa-f]{1,2}:){5}[0-9A-Fa-f]{1,2}")


def norm_mac(m: str) -> str:
    return m.lower().replace("-", ":")


def pad_mac(m: str) -> str:
    """Normaliza una MAC posiblemente abreviada (aa:b:c:...) a octetos de 2 dígitos."""
    partes = m.replace("-", ":").split(":")
    if len(partes) != 6:
        return norm_mac(m)
    return ":".join(p.lower().zfill(2) for p in partes)


def mac_de_tabla(nombre: str):
    try:
        for ln in open(MACS_TXT):
            ln = ln.strip()
            if ln.startswith("#") or not ln:
                continue
            parts = ln.split()
            if parts and parts[0] == nombre:
                m = MAC_RE.search(ln)
                if m:
                    return norm_mac(m.group())
    except FileNotFoundError:
        pass
    return None


def mac_de_arp(ip: str):
    try:
        out = subprocess.run(["arp", "-an"], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return None
    for ln in out.splitlines():
        if f"({ip})" in ln and "incomplete" not in ln:
            # quitamos la IP de la línea para que la regex de MAC no la confunda
            resto = ln.replace(f"({ip})", " ")
            m = MAC_RE.search(resto) or MAC_RE_LOOSE.search(resto)
            if m:
                return pad_mac(m.group())
    return None


def enviar_wol(mac: str, broadcasts=("255.255.255.255", "192.168.1.255"), ports=(9, 7)):
    mac_bytes = bytes.fromhex(mac.replace(":", "").replace("-", ""))
    packet = b"\xff" * 6 + mac_bytes * 16
    for b in broadcasts:
        for p in ports:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            try:
                s.sendto(packet, (b, p))
            except OSError:
                pass
            finally:
                s.close()


def ping(ip: str, timeout=2) -> bool:
    flag = "-t" if sys.platform == "darwin" else "-W"
    try:
        r = subprocess.run(["ping", "-c", "1", flag, str(timeout), ip],
                           capture_output=True, timeout=timeout + 2)
        return r.returncode == 0
    except Exception:
        return False


# Asociaciones nombre -> IP opcionales (se pueden dejar vacías: también se acepta la IP directamente
# y la IP que figure entre paréntesis en macs.txt). Ejemplo:
# IPS_CONOCIDAS = {"pc": "192.168.1.20", "portatil": "192.168.1.21"}
IPS_CONOCIDAS: dict = {}

IP_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")


def ip_de_tabla(nombre: str):
    """Devuelve la primera IP que aparezca en la línea de `nombre` de macs.txt, si la hay."""
    try:
        for ln in open(MACS_TXT):
            parts = ln.split()
            if parts and not ln.lstrip().startswith("#") and parts[0] == nombre:
                m = IP_RE.search(ln)
                if m:
                    return m.group()
    except FileNotFoundError:
        pass
    return None


def resolver_mac(objetivo: str):
    """objetivo puede ser un nombre (pc), una IP o una MAC literal."""
    if MAC_RE.fullmatch(objetivo):
        return norm_mac(objetivo), None
    nombre = objetivo if not objetivo[0].isdigit() else None
    ip = objetivo if objetivo[0].isdigit() else (IPS_CONOCIDAS.get(objetivo) or ip_de_tabla(objetivo))
    # 1) tabla local por nombre
    if nombre:
        m = mac_de_tabla(nombre)
        if m:
            return m, ip
    # 2) ARP vivo por IP
    if ip:
        m = mac_de_arp(ip)
        if m:
            return m, ip
    # 3) router (si hay clave)
    if ip and os.environ.get("SHANIA_ROUTER_PW"):
        try:
            from .hgu import HGUClient
            c = HGUClient()
            if c.login():
                m = c.mac_for_ip(ip)
                if m:
                    return m, ip
        except Exception as e:
            print(f"(router no disponible: {e})", file=sys.stderr)
    return None, ip


def cmd_wake(objetivo: str):
    mac, ip = resolver_mac(objetivo)
    if not mac:
        print(f"No encuentro la MAC de «{objetivo}». Prueba scripts/buscar-mac-en-logs.sh "
              f"o dame la clave del router (SHANIA_ROUTER_PW).", file=sys.stderr)
        return 2
    print(f"Despertando {objetivo} -> MAC {mac}" + (f" (IP {ip})" if ip else ""))
    enviar_wol(mac)
    if not ip:
        print("Paquete enviado. No tengo IP para verificar con ping.")
        return 0
    print("Esperando respuesta (hasta ~2 min)...")
    for i in range(12):
        if ping(ip):
            print(f"✅ {objetivo} RESPONDE (IP {ip}).")
            return 0
        time.sleep(10)
    print(f"❌ {objetivo} sigue sin responder. Revisa WoL en BIOS/Windows (configurar-wol.ps1) "
          f"o que la MAC sea la de la tarjeta cableada.")
    return 1


def cmd_mac(ip: str):
    mac, _ = resolver_mac(ip)
    print(mac or "no encontrada")
    return 0 if mac else 2


def cmd_devices():
    if not os.environ.get("SHANIA_ROUTER_PW"):
        print("Necesito la clave del router en SHANIA_ROUTER_PW (la de la pegatina).", file=sys.stderr)
        return 2
    from .hgu import HGUClient
    import json
    c = HGUClient()
    if not c.login():
        print("Login fallido: revisa la contraseña de administración.", file=sys.stderr)
        return 2
    print(json.dumps([d.dict() for d in c.list_devices()], indent=2, ensure_ascii=False))
    return 0


def main(argv=None):
    argv = argv or sys.argv[1:]
    if not argv:
        print(__doc__)
        return 1
    cmd, *rest = argv
    if cmd == "wake" and rest:
        return cmd_wake(rest[0])
    if cmd == "mac" and rest:
        return cmd_mac(rest[0])
    if cmd == "devices":
        return cmd_devices()
    print(__doc__)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
