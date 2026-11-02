---
name: autorecovery
description: >-
  Despertar y recuperar a distancia equipos (Mac, PC Windows, portátiles) cuando una máquina amanece
  apagada, suspendida o con la sesión caída, sin nadie delante. Cubre el encendido por red (Wake-on-LAN),
  la gestión del router HGU de O2/Movistar para obtener la MAC/IP de un equipo y reiniciarlo, el acceso
  remoto cifrado y firmado, y la configuración idempotente de Windows y BIOS para que el despertar
  funcione. Úsala con «enciende el PC», «el equipo no responde», «despiértalo por LAN», «configura el WoL»,
  «gestión del router», «autorecovery» o «plan de emergencia de encendido».
---

# Autorecovery

Sistema para **encender, reiniciar y recuperar** los equipos de casa a distancia, y para **dejarlos
configurados** de modo que una caída (corte de luz, suspensión, cuelgue, sesión de Claude muerta) se
resuelva sola o con un solo comando.

> Normas que no se saltan: las contraseñas las introduce el administrador y **no se guardan** en
> chat ni en ficheros; nada irreversible sin confirmación explícita; cada equipo se configura desde
> su propia sesión, sin saltarse permisos.

## Cuándo usarla
- Un equipo **no responde** (ping falla) y hay que encenderlo o reiniciarlo sin nadie delante.
- Hay que **sacar la MAC o la IP** de un equipo desde el router.
- Toca **dejar blindado** un equipo nuevo (o uno que falló): WoL, BIOS, arranque automático.
- Revisión periódica de que todos siguen configurados.

## Capas del sistema (de la más barata a la más segura)
| Capa | Qué hace | Cubre | Coste |
|---|---|---|---|
| A. WoL (`despertar.py`) | El Mac manda el paquete mágico y el equipo arranca desde apagado | Suspensión / apagado | 0 € |
| B. BIOS «Restore on AC Power Loss = Power On» | Al volver la luz, arranca solo | Corte de luz | 0 € |
| C. Arranque automático | Inicio de sesión + tarea que relanza la sesión | Sesión vuelve sola | 0 € |
| D. Reinicio remoto | `shutdown /r /t 60` desde la propia sesión | Cuelgue de la sesión | 0 € |
| E. Enchufe inteligente | Cortar/dar luz desde el móvil; con B, arranca | Cuelgue total | ~15-25 € |
| F. SAI | Aguanta cortes cortos | Cortes breves | ~60-120 € |

Un **Mac** (o cualquier equipo siempre encendido) es el «despertador» de la red (siempre encendido, con `caffeinate`). Si cae, otro equipo hace de despertador con el mismo paquete mágico.

## 1 · Despertar por red (Wake-on-LAN)
Desde el Mac (o el portátil):
```
python3 scripts/despertar.py <pc|portatil|omen|MAC>
```
- Las MAC/IP están en `~/.config/autorecovery/macs.txt`. Acepta también una MAC literal.
- Manda el paquete a `192.168.1.255` y `255.255.255.255`, puertos 9 y 7.
- Enviar a una MAC equivocada es **inofensivo** (no despierta nada): ante la duda, dispara a las candidatas.
- **El WoL solo funciona si el equipo está preparado** (capa A de la sección 4): WoL activado en la
  tarjeta de red **y** en la BIOS, e **inicio rápido de Windows desactivado**. Por cable es fiable;
  por Wi-Fi, no. Si no despierta, casi siempre es que falta esa configuración, no que el paquete falle.

Procedimiento ante un equipo caído: `scripts/procedimiento-emergencia.md`.

## 2 · Gestión del router (sacar MAC/IP, reiniciar)
Router HGU de O2/Movistar en `192.168.1.1` (micro_httpd, páginas `te_*.asp`, fabricante Askey o
MitraStar).Solo para routers propios o con autorización de su titular.

- La forma **limpia** de listar dispositivos con su IP/MAC es la librería de la comunidad
  `router-movistar` (Eitol) para Askey, o `mitra_router` (fernand0) para MitraStar. Ver
  `docs/ANALISIS-GITHUB.md`. Se intenta esto **antes** de pelearse con la interfaz web.
- Acceso web: login en `/cgi-bin/te_acceso_router.cgi`, usuario fijo `1234`, campos `loginUsername`
  y `loginPassword` **ofuscados con XOR 0x1f** (`mess_userpass` en `/js/te_util.js`), cookie
  `_httpdSessionId_` (se obtiene tocando una página protegida, que redirige al login). La señal de
  éxito **no** es el `location.href` del CGI, sino que una página protegida (p. ej. `te_red_local.asp`)
  **cargue** en vez de rebotar al login.
- Tiene **protección antifuerza-bruta** (`bruteTime`, bloqueo ~280 s): **no probar claves a ciegas**.
  La contraseña de administración es la de la **pegatina** (distinta de la del Wi-Fi) y la aporta el administrador.
- Alternativa de respaldo para la MAC sin router: **rebuscar en los propios logs** las tablas ARP
  del Mac (`arp -an`) ya registradas. Ver `scripts/buscar-mac-en-logs.sh`.

## 2b · Acceso remoto cifrado (desde fuera de casa)
El WoL es difusión de LAN y la admin del router es solo-LAN: **nada de esto se expone a internet**.
Un **agente en el Mac** (siempre encendido) recibe órdenes **firmadas** por una **pasarela cifrada**
(Tailscale recomendada; WireGuard o Cloudflare Tunnel) y las ejecuta en la LAN. La clave del router
**no viaja**: vive solo en el agente. Detalle y puesta en marcha: `docs/ACCESO-REMOTO.md`.
```
# en el Mac:   python3 -m shania_router.agent --host <IP-tailscale> --port 8787
# desde fuera: python3 -m shania_router.remote wake pc
```
Doble cerradura: cifrado de transporte (pasarela) + firma HMAC-SHA256 con ventana anti-repetición.
`reboot` exige confirmación explícita.

## 3 · Implantar en TODOS los equipos (orquestación)
Cada equipo se configura desde su propia sesión. Una vez por máquina:
- **PC, portátil u otros equipos Windows:** ejecutar
  `scripts/configurar-wol.ps1` (idempotente, hace copia de lo anterior). Deja: inicio rápido off, WoL
  en la tarjeta, sin suspensión con corriente, tarea de arranque que relanza el RETOMAR, y apunta MAC/IP.
- **BIOS (una vez por equipo):** `scripts/bios-checklist.md` (Power On by LAN/PCIE,
  Restore on AC Power Loss = Power On, ErP off).
- **Router:** reservar por DHCP la IP de cada equipo para que el WoL
  y la carpeta compartida no fallen.
- **Mac/portátil:** quedan como despertadores; el Mac con `womp=1` y `caffeinate`.

Comprobación periódica: `scripts/configurar-wol.ps1 -Verificar` en cada Windows; `despertar.py` de prueba.

## 4 · Qué deja activado cada capa (resumen técnico)
- **A (WoL):** `powercfg /h off` (inicio rápido), «Wake on Magic Packet = Enabled» en el adaptador,
  `powercfg /deviceenablewake "<adaptador>"`, no suspender con corriente.
- **C (arranque):** inicio de sesión automático (valorar el riesgo de seguridad) + tarea «al iniciar
  el sistema» que lanza el script de reanudación de la sesión.
- **D (reinicio):** `shutdown /r /t 60` desde la propia sesión.

## Archivos
- `shania_router/hgu.py` — cliente del router HGU (login XOR, listar dispositivos, MAC por IP).
- `shania_router/cli.py` — `wake`/`mac`/`devices` en la LAN (resuelve MAC y despierta con ping).
- `shania_router/agent.py` — agente en casa (recibe órdenes firmadas y actúa en la LAN).
- `shania_router/remote.py` — cliente desde fuera (firma y llama al agente por la pasarela).
- `scripts/despertar.py` — emisor del paquete mágico (copia de `scripts/despertar.py`).
- `scripts/configurar-wol.ps1` — configuración idempotente de Windows (con `-Verificar`).
- `scripts/buscar-mac-en-logs.sh` — rescata MAC/IP de las tablas ARP ya registradas en los logs
  (tolera el formato abreviado de macOS y valida por tabla coherente).
- `scripts/bios-checklist.md` — pasos de BIOS.
- `scripts/procedimiento-emergencia.md` — qué hacer cuando un equipo no responde.
- `docs/ACCESO-REMOTO.md` · `docs/ANALISIS-GITHUB.md` — pasarela cifrada y análisis de la comunidad.

