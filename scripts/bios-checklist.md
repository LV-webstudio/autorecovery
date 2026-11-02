# Preparar cada equipo para el despertar (una vez por máquina)

El orden importa. En Windows, **ejecuta antes `configurar-wol.ps1`** (desactiva el inicio rápido y
arma la tarjeta); si no, la prueba de "apagar del todo" fallará por el inicio rápido de Windows y
parecerá culpa de la BIOS.

## 1) BIOS/UEFI (todos los equipos)
Entrar al arrancar (normalmente **Supr**, **F2** o **F10**; en HP/OMEN a veces **Esc** y luego **F10**).

| Opción (nombres que puede tener) | Valor | Para qué |
|---|---|---|
| **Wake on LAN / Power On By PCI-E / Resume by PCIe Device / WOL** | **Enabled** | Que la tarjeta de red encienda el equipo desde apagado |
| **Restore on AC Power Loss / After Power Failure** | **Power On** | Que tras un corte de luz arranque solo |
| **ErP Ready / EuP** | **Disabled** | Si está activo, corta la energía a la red en apagado y el WoL no funciona |
| **Deep Sleep / Deep S5** | **Disabled** | Mismo motivo: no cortar la red en S5 |
| **S5 Maximum Power Savings** (HP/OMEN) | **Disable** | Igual: en HP este es el que corta la red en apagado |
| **Fast Boot (BIOS)** | indiferente | (El "inicio rápido" problemático es el de Windows; eso lo hace `configurar-wol.ps1`) |

> **Cable, no Wi-Fi:** el WoL desde apagado (S5) va casi siempre por **cable**; por Wi-Fi rara vez
> funciona desde apagado. Y muchos **portátiles** solo despiertan **enchufados a la corriente**.

## 2) Sistema operativo
- **Windows:** `powershell -ExecutionPolicy Bypass -File .\configurar-wol.ps1` (como administrador).
  Deja HiberbootEnabled=0, arma la tarjeta (RegistryKeyword + WMI) y apaga EEE/Green.
- **Linux (Ubuntu, p. ej. el OMEN):** activar WoL en la tarjeta y dejarlo fijo:
  ```bash
  sudo ethtool -s <interfaz> wol g                 # <interfaz>: la de 'ip link' (p. ej. enp3s0)
  # persistente con NetworkManager:
  nmcli connection modify "<conexión>" 802-3-ethernet.wake-on-lan magic
  ```
  Comprobar con `sudo ethtool <interfaz> | grep Wake-on` (debe poner `g`).
- **macOS:** Ajustes del sistema → Batería/Energía → **"Despertar para acceder a la red"** (Wake for
  network access) activado. (En Mac de sobremesa/con corriente.)

## 3) Probar
Apagar del todo y despertar desde otro equipo de la red:
```bash
python3 scripts/despertar.py <equipo>
```
Ver la MAC de la tarjeta por si hay que apuntarla:
- Windows: `getmac /v`
- Linux: `ip link`
- macOS: `ifconfig en0` (o la interfaz de cable)

Si no despierta: casi siempre es ErP / Deep Sleep / S5 Max Power Savings activos, el cable en una
tarjeta distinta de la MAC apuntada, o (portátil) que no está enchufado a la corriente.
