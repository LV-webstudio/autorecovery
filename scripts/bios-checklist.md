# BIOS: lo que hay que activar en cada equipo (una vez)

Entrar en la BIOS/UEFI al arrancar (normalmente **Supr**, **F2** o **F10**). Buscar y dejar así:

| Opción (nombres que puede tener) | Valor | Para qué |
|---|---|---|
| **Wake on LAN / Power On By PCI-E / Resume by PCIe Device / WOL** | **Enabled** | Que la tarjeta de red pueda encender el equipo desde apagado |
| **Restore on AC Power Loss / Restore AC Power / After Power Failure** | **Power On** | Que tras un corte de luz arranque solo |
| **ErP Ready / EuP** | **Disabled** | Si está activo, corta la energía a la red en apagado y el WoL no funciona |
| **Deep Sleep / Deep S5** | **Disabled** | Mismo motivo: no cortar la red en S5 |
| **Fast Boot (BIOS)** | indiferente | (El "inicio rápido" problemático es el de Windows; eso lo hace configurar-wol.ps1) |

Tras guardar (**F10**), apagar del todo y probar desde el Mac:
`python3 ~/bin/despertar.py <equipo>`

Si aun así no despierta: casi siempre es ErP/Deep Sleep activos, o que el cable va a una tarjeta
distinta de la MAC apuntada. Revisar la MAC con `getmac /v` en Windows.
