#!/usr/bin/env python3
"""Encendido por red (Wake-on-LAN) de equipos de la red local.
Uso: despertar.py pc|portatil|omen|AA:BB:CC:DD:EE:FF
Las MAC se guardan en ~/.config/autorecovery/macs.txt (nombre MAC por línea)."""
import socket, sys, os, re
TABLA = os.path.expanduser('~/.config/autorecovery/macs.txt')
def mac_de(nombre):
    if re.fullmatch(r'([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}', nombre): return nombre
    for l in open(TABLA):
        p = l.split()
        if len(p) >= 2 and p[0].lower() == nombre.lower(): return p[1]
    sys.exit(f'No tengo la MAC de «{nombre}» en {TABLA}')
mac = mac_de(sys.argv[1]).replace('-', ':')
paquete = b'\xff' * 6 + bytes.fromhex(mac.replace(':', '')) * 16
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
for destino in ('192.168.1.255', '255.255.255.255'):
    for puerto in (9, 7): s.sendto(paquete, (destino, puerto))
print(f'Paquete mágico enviado a {mac} (broadcast 192.168.1.255 y 255.255.255.255, puertos 9 y 7)')
