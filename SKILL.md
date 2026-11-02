---
name: autorecovery
description: >-
  Despertar y recuperar a distancia equipos (Mac, PC Windows, portátiles) cuando una máquina amanece
  apagada o suspendida (no responde al ping), sin nadie delante. Cubre el encendido por red (Wake-on-LAN),
  la gestión del router HGU de O2/Movistar para obtener la MAC/IP de un equipo y reiniciarlo, el acceso
  remoto cifrado y firmado, y la configuración idempotente de Windows y BIOS para que el despertar
  funcione. Úsala con «enciende el PC», «el equipo está apagado / no responde al ping», «despiértalo por
  LAN», «configura el WoL», «gestión del router», «autorecovery» o «plan de emergencia de encendido».
---

# Autorecovery

Sistema para **encender, reiniciar y recuperar** los equipos de casa a distancia, y para **dejarlos
configurados** de modo que una caída (corte de luz, suspensión, cuelgue, sesión de Claude muerta) se
resuelva sola o con un solo comando.

> Normas que no se saltan: las contraseñas las introduce el administrador y **no se guardan** en
> chat ni en ficheros; **nada irreversible** (reinicio del router, `shutdown /r`) ocurre sin la
> **confirmación de quien manda, dada en la ventana de la sesión que actúa** (un permiso reenviado por
> otra sesión no basta); cada equipo se configura desde su propia sesión, sin saltarse permisos.

## Cuándo usarla
- Un equipo **no responde** (ping falla) y hay que encenderlo o reiniciarlo sin nadie delante.
- Hay que **sacar la MAC o la IP** de un equipo desde el router.
- Toca **dejar blindado** un equipo nuevo (o uno que falló): WoL, BIOS, arranque automático.
- Revisión periódica de que todos siguen configurados.

> Esto es para equipos **apagados o suspendidos** (no responden al ping). Si el equipo **responde al
> ping pero su sesión no**, no es un apagado: es un cuelgue de la sesión → se resuelve con tu
> procedimiento de relevo de sesión (en LV: `lv-relevo` / `wassup`), no con Wake-on-LAN.

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
MitraStar). Solo para routers propios o con autorización de su titular.

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
# en el Mac:   python3 -m shania_router.agent --host 127.0.0.1 --port 8787
#              tailscale serve --bg --https 8787 http://127.0.0.1:8787
# desde fuera: SHANIA_AGENT_URL=https://<equipo>.<tailnet>.ts.net python3 -m shania_router.remote wake pc
```
El agente escucha **solo en 127.0.0.1**; lo publica cifrado `tailscale serve` (no se abre nada en el
router). Doble cerradura: cifrado de transporte (pasarela) + firma HMAC-SHA256 con **nonce** y ventana
anti-repetición (una misma orden firmada no se acepta dos veces). `reboot` exige confirmación explícita.

## 3 · Implantar en TODOS los equipos (orquestación)
Cada equipo se configura desde su propia sesión. Una vez por máquina:
- **PC, portátil u otros equipos Windows:** ejecutar
  `scripts/configurar-wol.ps1` (idempotente, hace copia de lo anterior). Deja: inicio rápido off, WoL
  en la tarjeta, sin suspensión con corriente y apunta MAC/IP. La **tarea de arranque** solo se crea si
  le pasas `-LanzadorRetomar <ruta.cmd>`; y ese lanzador debe limitarse a reanudar la sesión por
  tu procedimiento de relevo de sesión (en LV: `lv-relevo`: avisar y esperar, respetando el silencio
  nocturno), sin hacer nada por iniciativa propia.
  > Descarga el `.ps1` por su SHA (el CDN de GitHub cachea `raw`); revísalo antes de ejecutarlo.
- **BIOS (una vez por equipo):** `scripts/bios-checklist.md` (Power On by LAN/PCIE,
  Restore on AC Power Loss = Power On, ErP off).
- **Router:** reservar por DHCP la IP de cada equipo para que el WoL
  y la carpeta compartida no fallen.
- **Mac/portátil:** quedan como despertadores; el Mac con `womp=1` y `caffeinate`.

Comprobación periódica: `scripts/configurar-wol.ps1 -Verificar` en cada Windows; `despertar.py` de prueba.

## 4 · Qué deja activado cada capa (resumen técnico)
- **A (WoL):** `HiberbootEnabled=0` (desactiva el **inicio rápido** de Windows; **la hibernación se
  mantiene** — no se usa `powercfg /h off`), «Wake on Magic Packet = Enabled» y **EEE/Green Ethernet
  off** en el adaptador (por `RegistryKeyword` + WMI `root\wmi`, independiente del idioma),
  `powercfg /deviceenablewake "<adaptador>"`, no suspender con corriente.
- **C (arranque):** la **tarea «al iniciar»** (opcional, solo con `-LanzadorRetomar`) lanza únicamente
  la reanudación de la sesión vía tu procedimiento de relevo (en LV: `lv-relevo`) y su aviso; nada por iniciativa propia.
  El **inicio de sesión automático** NO se activa por defecto: guardaría la contraseña de Windows en el
  registro (contra la norma de no guardar claves). Es una opción que **decide el administrador**, con
  ese aviso, si acepta el riesgo.
- **D (reinicio):** `shutdown /r /t 60` desde la propia sesión, con la confirmación de quien manda.

## Archivos
- `shania_router/hgu.py` — cliente del router HGU (login XOR, listar dispositivos, MAC por IP).
- `shania_router/cli.py` — `wake`/`mac`/`devices` en la LAN (resuelve MAC y despierta con ping).
- `shania_router/agent.py` — agente en casa (recibe órdenes firmadas y actúa en la LAN).
- `shania_router/remote.py` — cliente desde fuera (firma y llama al agente por la pasarela).
- `scripts/despertar.py` — emisor del paquete mágico de Wake-on-LAN (acepta nombre o MAC literal).
- `scripts/configurar-wol.ps1` — configuración idempotente de Windows (con `-Verificar`).
- `scripts/buscar-mac-en-logs.sh` — rescata MAC/IP de las tablas ARP ya registradas en los logs
  (tolera el formato abreviado de macOS y valida por tabla coherente).
- `scripts/bios-checklist.md` — pasos de BIOS.
- `scripts/procedimiento-emergencia.md` — qué hacer cuando un equipo no responde.
- `docs/ACCESO-REMOTO.md` · `docs/ANALISIS-GITHUB.md` — pasarela cifrada y análisis de la comunidad.

