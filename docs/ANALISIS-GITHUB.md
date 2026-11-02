# Análisis de los proyectos de GitHub y qué adaptamos

Router de referencia: **HGU de O2/Movistar**, firmware Telefónica (micro_httpd, páginas `te_*.asp`),
fabricante Askey o MitraStar. Login por `/cgi-bin/te_acceso_router.cgi` con ofuscación **XOR 0x1f**
y cookie `_httpdSessionId_`; protección antifuerza-bruta.

| Proyecto | Qué aporta | ¿Lo usamos? |
|---|---|---|
| **router-movistar** (Eitol, Python, Askey RFT3505VW) | `Client(password)` → `get_router_info().devices` con `ip_address`, `mac_address`, `device_name`, `interface`, `status`; `reboot()`. Pydantic. | **Modelo de datos adoptado** en `shania_router.Device`. Su login puede no coincidir con el firmware `te_`; queda como **backend alternativo** a probar. |
| **mitra_router** (fernand0, Python3, MitraStar) | Reinicio automático y listado de IPs en MitraStar clásico. | Referencia para `reboot()` si el router resulta ser MitraStar. |
| **ha-movistar-askey** (jardenberg, Home Assistant, Askey Smart WiFi 6/7) | Device tracker local de presencia. | Futuro: presencia/automación si montamos Home Assistant. |
| **MitraStar_GPT-2541GNAC_HA** (joseska, Home Assistant) | Device tracker para el MitraStar GPT-2541GNAC. | Futuro, mismo caso. |
| **askey_RTF3505VW_hacking** (daniel-dona) | UART, NAND, vulnerabilidades de placa. | Solo si hiciera falta recuperación de hardware; no ahora. |
| **guia-keenetic-ht801-o2** (gist) | Poner el HGU en **bridge** y mapear VLAN 6 (Internet) y VLAN 3 (teléfono) para router neutro propio. | Futuro: si se migra a router neutro avanzado sin perder el fijo. |

## Este repositorio (lo que aporta)
- `shania_router/hgu.py` — cliente propio del firmware `te_*.asp` (login XOR 0x1f, conocimiento público de la comunidad,
  manejo de cookie y verificación real de sesión), listado de dispositivos y hueco para reinicio.
- `shania_router/cli.py` — resolver MAC (tabla local → ARP vivo → logs → router) y despertar con ping.
- `shania_router/agent.py` + `remote.py` — **acceso remoto cifrado y firmado** (lo que no dan los
  proyectos de arriba): mandar WoL y gestionar el router desde fuera, con la clave siempre en casa.
- `scripts/` — configuración de WoL/BIOS en Windows y rescate de MAC desde los logs ARP.

## Decisiones abiertas
1. **Identificar el fabricante exacto** (Askey o MitraStar) para decidir si `router-movistar` sirve de
   backend o basta con el cliente propio.
2. **Pasarela**: Tailscale (recomendada), WireGuard o Cloudflare Tunnel.
