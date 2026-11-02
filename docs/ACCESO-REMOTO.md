# Acceso remoto cifrado (desde fuera de casa)

## Principio
Dos cosas **no se pueden hacer directamente desde internet**, y no hay que intentarlo:
- **El paquete WoL es difusión de LAN:** el NAT de casa no deja mandarlo desde fuera.
- **La administración del router es solo-LAN:** NUNCA se abre a internet (ni port-forwarding del HGU).

Solución: un **agente dentro de casa** (el Mac, siempre encendido) recibe la orden por una
**pasarela cifrada** y la ejecuta en la LAN. La clave del router vive solo en el agente y **no viaja**.

```
[Operador / sesión remota, fuera]  --orden firmada-->  (pasarela cifrada)  -->  [Agente en el Mac]  -->  LAN
     shania_router.remote                      Tailscale/WireGuard          shania_router.agent     · WoL
                                                                                                    · router HGU
```

## La pasarela cifrada (elige una; recomendada: Tailscale)
1. **Tailscale (WireGuard gestionado) — recomendada.** Red privada cifrada entre tus dispositivos,
   sin abrir puertos. Instala Tailscale en el Mac y en el móvil/portátil del operador; el Mac queda con
   una IP `100.x.y.z` o nombre `mi-equipo.mi-tailnet.ts.net`. El agente escucha en esa interfaz.
   - Identidad por cuenta, cifrado extremo a extremo, cero puertos públicos. Ideal y gratis para uso personal.
2. **WireGuard "a pelo".** Igual de seguro, pero configuras tú las claves y un endpoint. Más manual.
3. **Cloudflare Tunnel + Access.** El Mac abre un túnel saliente a Cloudflare; publicas el agente en
   `https://autorecovery.tudominio` protegido con Cloudflare Access (login). Útil si quieres URL web.

En todos los casos: el agente **no** se expone en IP pública directa, y además va firmado (HMAC).

## Doble cerradura
- **Transporte:** lo cifra la pasarela (WireGuard/TLS).
- **Autorización:** cada petición va firmada con HMAC-SHA256 y un secreto compartido
  (`SHANIA_AGENT_TOKEN`), con ventana de 120 s contra repetición. Sin firma válida → 401.

## Puesta en marcha
**En el Mac (agente), una vez:**
```
export SHANIA_AGENT_TOKEN="<secreto largo, genéralo con `openssl rand -hex 32`>"
export SHANIA_ROUTER_PW="<clave de la pegatina del router>"   # opcional, solo si se quiere /devices y /reboot
python3 -m shania_router.agent --host 100.100.100.100 --port 8787   # la IP de Tailscale del Mac
```
Para que arranque solo: envolverlo en un `launchd` (plist) con `KeepAlive` y `caffeinate`.
Los secretos NO se escriben en el repo: van en el entorno o en el Llavero.

**Desde fuera (el operador o una sesión remota):**
```
export SHANIA_AGENT_URL="https://mi-equipo.mi-tailnet.ts.net:8787"
export SHANIA_AGENT_TOKEN="<el mismo secreto>"
python3 -m shania_router.remote wake pc
python3 -m shania_router.remote devices
```

## Reglas de seguridad (no negociables)
- El HGU no se publica en internet. Si algún día se pone en bridge (ver `ANALISIS-GITHUB.md`),
  el router neutro tampoco expone su admin.
- Secretos solo por entorno/Llavero; nunca en git ni en el chat. Rotarlos si se sospecha fuga.
- `reboot` exige confirmación explícita; cortar la red de casa es acción sensible → requiere aprobación explícita del titular.
- El agente registra lo mínimo y no guarda datos de clientes.
