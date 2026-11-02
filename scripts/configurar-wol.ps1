<#
  configurar-wol.ps1 · Shania Autorecovery
  Deja un Windows listo para el encendido por red (WoL) y el arranque automático.
  Idempotente: guarda el estado anterior en una carpeta de copia antes de cambiar nada.

  Ejecutar como ADMINISTRADOR en cada equipo (PC, portátil, Omen):
      powershell -ExecutionPolicy Bypass -File .\configurar-wol.ps1
  Solo comprobar, sin cambiar nada:
      powershell -ExecutionPolicy Bypass -File .\configurar-wol.ps1 -Verificar

  Lo que hace:
   1) Desactiva el inicio rápido de Windows (imprescindible para WoL desde apagado).
   2) Activa "Wake on Magic Packet" en la tarjeta de red y permite que despierte el equipo.
   3) Plan de energía: no suspender con corriente.
   4) Apunta MAC e IP para la tabla del Mac.
   5) (Opcional) crea la tarea de arranque que relanza la sesión -> parámetro -LanzadorRetomar.
  La BIOS se configura aparte (ver bios-checklist.md).
#>
param(
  [switch]$Verificar,
  [string]$LanzadorRetomar = ""   # ruta a un RETOMAR-<sesion>.cmd; si se da, crea la tarea de arranque
)

$ErrorActionPreference = "Stop"
$backup = Join-Path $env:ProgramData "ShaniaAutorecovery\backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
function Log($m){ Write-Host "[autorecovery] $m" }

if (-not $Verificar) { New-Item -ItemType Directory -Force -Path $backup | Out-Null }

# --- 0) adaptador activo ---
$nic = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Sort-Object LinkSpeed -Descending | Select-Object -First 1
if (-not $nic) { throw "No encuentro un adaptador de red activo." }
$mac = $nic.MacAddress -replace '-',':'
$ip  = (Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
Log "Adaptador: $($nic.Name) | MAC $mac | IP $ip | $($nic.LinkSpeed)"

# --- 1) inicio rapido ---
$hib = (powercfg /a) -join "`n"
if ($Verificar) {
  $fast = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
  Log "Inicio rapido (HiberbootEnabled): $fast  (0 = correcto)"
} else {
  reg export 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' (Join-Path $backup 'power.reg') /y | Out-Null
  powercfg /h off 2>$null
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -ErrorAction SilentlyContinue
  Log "Inicio rapido desactivado."
}

# --- 2) WoL en la tarjeta ---
# OJO: en algunos drivers (p. ej. Realtek PCIe GbE) Get-NetAdapterPowerManagement DA ERROR.
# Por eso la ruta por "propiedades avanzadas" se intenta SIEMPRE, aparte del cmdlet de energia.
function Set-AdvPropo($nic, $names, $value) {
  foreach ($dn in $names) {
    try { Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName $dn -DisplayValue $value -ErrorAction Stop; return $true } catch {}
  }
  return $false
}
# 2a) cmdlet de energia (si el driver lo soporta)
try {
  $pm = Get-NetAdapterPowerManagement -Name $nic.Name -ErrorAction Stop
  if ($Verificar) {
    Log "WakeOnMagicPacket: $($pm.WakeOnMagicPacket) | WakeOnPattern: $($pm.WakeOnPattern)"
  } else {
    $pm.WakeOnMagicPacket = 'Enabled'
    $pm.WakeOnPattern     = 'Disabled'   # solo el paquete magico, menos despertares espurios
    $pm | Set-NetAdapterPowerManagement
    Log "Energia del adaptador ajustada por cmdlet."
  }
} catch { Log "(Get-NetAdapterPowerManagement no disponible en este driver; uso propiedades avanzadas.)" }

# 2b) propiedades avanzadas (siempre; el nombre varia por driver e idioma)
if ($Verificar) {
  Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue |
    Where-Object DisplayName -match 'Wake|LAN|Energy|Green|EEE' |
    ForEach-Object { Log "  $($_.DisplayName) = $($_.DisplayValue)" }
} else {
  if (Set-AdvPropo $nic @('Wake on Magic Packet','Activar en LAN magica','Activación por LAN mágica','Reactivación por paquete mágico') 'Enabled') { Log "Wake on Magic Packet = Enabled." }
  Set-AdvPropo $nic @('Shutdown Wake-On-Lan','Shutdown Wake On Lan','Activar WOL tras apagado') 'Enabled' | Out-Null
  # desactivar ahorros que cortan el enlace en apagado:
  Set-AdvPropo $nic @('Energy Efficient Ethernet','Energy-Efficient Ethernet','Ethernet de ahorro de energía','EEE') 'Disabled' | Out-Null
  Set-AdvPropo $nic @('Green Ethernet','Ethernet ecológico') 'Disabled' | Out-Null
  Set-AdvPropo $nic @('WOL & Shutdown Link Speed','Velocidad de enlace tras apagado') '10 Mbps First' | Out-Null
  # permitir que el dispositivo despierte el equipo
  try { powercfg /deviceenablewake "$($nic.InterfaceDescription)" 2>$null } catch {}
  Log "Propiedades avanzadas de WoL aplicadas (EEE/Green off, Shutdown WoL on)."
}

# --- 3) plan de energia ---
if ($Verificar) {
  Log "Standby AC actual: $((powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE) -match 'Corriente' )"
} else {
  powercfg /change standby-timeout-ac 0
  powercfg /change hibernate-timeout-ac 0
  powercfg /change monitor-timeout-ac 15
  Log "Energia: no suspender con corriente."
}

# --- 4) apuntar MAC/IP ---
$ficha = [pscustomobject]@{ equipo=$env:COMPUTERNAME; adaptador=$nic.Name; mac=$mac; ip=$ip; fecha=(Get-Date) }
$ficha | Format-List | Out-String | Write-Host
if (-not $Verificar) { $ficha | ConvertTo-Json | Out-File (Join-Path $backup 'ficha-red.json') -Encoding utf8 }
Log "Apunta en el Mac: en macs.txt -> $($env:COMPUTERNAME.ToLower()) $mac ($ip)"

# --- 5) tarea de arranque (opcional) ---
if ($LanzadorRetomar) {
  if ($Verificar) {
    Log "Tarea de arranque: $([bool](Get-ScheduledTask -TaskName 'ShaniaRetomar' -ErrorAction SilentlyContinue))"
  } elseif (Test-Path $LanzadorRetomar) {
    $act = New-ScheduledTaskAction -Execute $LanzadorRetomar
    $trg = New-ScheduledTaskTrigger -AtStartup
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName 'ShaniaRetomar' -Action $act -Trigger $trg -Settings $set -RunLevel Highest -Force | Out-Null
    Log "Tarea 'ShaniaRetomar' creada (lanza $LanzadorRetomar al iniciar)."
  } else {
    Log "AVISO: no existe el lanzador $LanzadorRetomar; tarea no creada."
  }
}

Log ($Verificar ? "Verificacion terminada." : "Configuracion terminada. Copia de seguridad en $backup")
Log "Prueba desde el Mac: python3 scripts/despertar.py $($env:COMPUTERNAME.ToLower())  (tras apagar este equipo)"
