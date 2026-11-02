# Procedimiento de emergencia: un equipo no responde

> Sustituye `<equipo>` por el nombre de tu tabla (`~/.config/autorecovery/macs.txt`) y las IP de
> ejemplo (`192.168.1.20`, `.21`, …) por las tuyas. Ten la tabla a mano antes de la emergencia.

## 0. ¿Está la red en pie? (empieza aquí)
Si el router o internet han caído, nada remoto funcionará. Comprueba primero el router:
```bash
ping -c 2 192.168.1.1          # macOS/Linux   ·   Windows: ping -n 2 192.168.1.1
```
- No responde el router → es un problema de red/luz, no del equipo. Si estás fuera, no hay WoL
  posible hasta que vuelva el router; pasa al punto 4 (enchufe) o avisa a alguien en casa.
- Responde el router → sigue.

## 1. ¿El equipo está colgado o apagado?
```bash
ping -c 2 192.168.1.20         # la IP del equipo   ·   Windows: ping -n 2 ...
```
- **Responde al ping pero la sesión de Claude no** → NO es un apagado; es un cuelgue de la sesión.
  Eso se resuelve con el relevo (ver `lv-relevo`/`wassup`), no con WoL. Si hace falta reiniciar el
  equipo entero, desde una sesión EN ese equipo y con el visto bueno de quien manda:
  - Windows: `shutdown /r /t 60`
  - Linux (Omen/Ubuntu): `sudo shutdown -r +1`
  - macOS: `sudo shutdown -r +1`
- **No responde al ping** → está apagado o suspendido; pásalo al punto 2.

## 2. Despertar por LAN (Wake-on-LAN)
Desde **otro equipo encendido de la misma red** (no hace falta que sea el Mac):
```bash
python3 scripts/despertar.py <equipo>
# o:
python3 -m shania_router.cli wake <equipo>
```
Espera ~3 min y vuelve a hacer ping. ¿No sabes la MAC?
```bash
scripts/buscar-mac-en-logs.sh 192.168.1.20      # rescata la MAC de tablas ARP ya registradas
python3 -m shania_router.cli mac 192.168.1.20   # o pregúntasela al router (necesita su clave)
```
> **Si el que ha caído es el propio emisor** (el equipo desde el que sueles lanzar el WoL): lánzalo
> desde cualquier otro de la LAN (p. ej. otro PC o portátil encendido). Cualquier equipo con Python
> sirve de emisor.

## 3. Desde fuera de casa (pasarela cifrada)
Con el agente de casa levantado y publicado por Tailscale (ver `docs/ACCESO-REMOTO.md`):
```bash
export SHANIA_AGENT_URL=https://<equipo>.<tailnet>.ts.net SHANIA_AGENT_TOKEN=...
python3 -m shania_router.remote wake <equipo>
```
El agente emite el paquete mágico dentro de la LAN; la contraseña del router nunca sale de casa.
> **Solo con el móvil:** instala la app de Tailscale en el teléfono para entrar en la tailnet; desde
> ahí puedes llamar al agente (con un cliente de línea de comandos o la petición HTTP firmada).

## 4. Sigue sin responder (corte de luz o cuelgue total)
- Con BIOS en **"Restore on AC Power Loss = Power On"** (ver `bios-checklist.md`), al volver la luz
  el equipo arranca solo. Si esa opción NO está puesta, el enchufe inteligente no bastará.
- Enchufe inteligente: apaga y vuelve a dar corriente; con la BIOS anterior, arrancará.
- **Confirma que ha vuelto:** ping OK **y** la sesión responde (no basta con que encienda).

## 5. Nada funciona
Avisa a la persona responsable (deja aquí su contacto: `__________`) y decidid si alguien va al lugar.

## 6. Anotar
Registra el incidente (qué equipo, hora, qué lo resolvió) en el registro de red que uséis
(p. ej. la carpeta compartida del equipo o el parte del día).
