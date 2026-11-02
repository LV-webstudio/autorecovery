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
# Método robusto e independiente del idioma: se usan RegistryKeyword (no DisplayName) y, para los
# ajustes de energía del dispositivo, las clases WMI de root\wmi filtradas por el PnPDeviceID del NIC.
# (Get-NetAdapterPowerManagement falla en algunos drivers Realtek; por eso NO dependemos de él.)
$inst = $nic.PnPDeviceID
if ($Verificar) {
  Get-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword '*WakeOnMagicPacket','S5WakeOnLan','*EEE','EnableGreenEthernet','PowerSavingMode' -ErrorAction SilentlyContinue |
    ForEach-Object { Log ("  {0,-28} = {1}" -f $_.DisplayName, $_.DisplayValue) }
  Log "Pueden despertar el equipo (wake_armed):"; powercfg /devicequery wake_armed | ForEach-Object { Log "  $_" }
} else {
  # 2a) palabras clave del registro (robustas): 1=activar, 0=desactivar
  $kw = @{ '*WakeOnMagicPacket'='1'; 'S5WakeOnLan'='1'; '*EEE'='0'; 'EnableGreenEthernet'='0' }
  foreach ($k in $kw.Keys) {
    if (Get-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword $k -ErrorAction SilentlyContinue) {
      try { Set-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword $k -RegistryValue $kw[$k] -NoRestart -ErrorAction Stop; Log "  $k -> $($kw[$k])" } catch {}
    }
  }
  # 2b) permitir que el dispositivo despierte el equipo
  try { powercfg /deviceenablewake "$($nic.InterfaceDescription)" 2>$null; Log "powercfg /deviceenablewake aplicado." } catch {}
  # 2c) WMI root\wmi: despertar solo con paquete mágico y NO apagar el NIC para ahorrar energía
  foreach ($c in 'MSPower_DeviceWakeEnable','MSNdis_DeviceWakeOnMagicPacketOnly','MSPower_DeviceEnable') {
    $o = Get-CimInstance -Namespace root\wmi -ClassName $c -ErrorAction SilentlyContinue | Where-Object { $_.InstanceName -like "$inst*" }
    if ($o) {
      $v = if ($c -eq 'MSPower_DeviceEnable') { $false } else { $true }   # DeviceEnable=false => Windows no lo apaga
      try { $o | Set-CimInstance -Property @{ Enable = $v } -ErrorAction Stop; Log "  $c -> $v" } catch {}
    }
  }
  try { Restart-NetAdapter -Name $nic.Name -ErrorAction SilentlyContinue } catch {}
  Log "WoL aplicado por RegistryKeyword + WMI."
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
