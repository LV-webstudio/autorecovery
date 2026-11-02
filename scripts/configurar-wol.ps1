<#
  configurar-wol.ps1 · Autorecovery
  Deja un Windows listo para el encendido por red (WoL) y el arranque automático.
  Compatible con Windows PowerShell 5.1 (el que trae Windows) y con PowerShell 7.
  Idempotente: guarda el estado anterior en una carpeta de copia antes de cambiar nada.

  Solo informar (no cambia nada, no necesita admin):
      powershell -ExecutionPolicy Bypass -File .\configurar-wol.ps1 -Verificar
  Aplicar (pide elevación con UAC si hace falta):
      powershell -ExecutionPolicy Bypass -File .\configurar-wol.ps1
  Guárdalo en UTF-8 con BOM (PowerShell 5.1 estropea las tildes sin BOM).

  Qué hace al aplicar:
   1) Desactiva el inicio rápido de Windows (HiberbootEnabled=0) sin tocar la hibernación.
   2) WoL en la tarjeta por método robusto (RegistryKeyword + WMI), EEE/Green off.
   3) Plan de energía: no suspender con corriente.
   4) Apunta MAC e IP.
   5) (Opcional) tarea de arranque que relanza la sesión -> -LanzadorRetomar.
  La BIOS se configura aparte (ver bios-checklist.md).
#>
param(
  [switch]$Verificar,
  [string]$Adaptador = "",         # nombre del adaptador; si se omite, se elige el de cable activo
  [string]$LanzadorRetomar = ""    # ruta a un lanzador .cmd; si se da, crea la tarea de arranque
)

$ErrorActionPreference = "Continue"   # llamamos a muchas herramientas nativas: no abortar por stderr
function Log($m){ Write-Host "[autorecovery] $m" }

# --- admin: si vamos a aplicar y no somos admin, relanzar elevado ---
function Es-Admin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
if (-not $Verificar -and -not (Es-Admin)) {
  Log "Hacen falta permisos de administrador: relanzo con UAC (acepta el aviso)."
  # -NoExit: la ventana elevada queda abierta para ver el resultado.
  $a = "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  if ($Adaptador) { $a += " -Adaptador `"$Adaptador`"" }
  if ($LanzadorRetomar) { $a += " -LanzadorRetomar `"$LanzadorRetomar`"" }
  Start-Process powershell -Verb RunAs -ArgumentList $a
  return
}

$backup = Join-Path $env:ProgramData "Autorecovery\backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
if (-not $Verificar) {
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  try { Start-Transcript -Path (Join-Path $backup 'configurar-wol.log') -Append | Out-Null } catch {}
}

# --- 0) adaptador: preferir el de CABLE (802.3) activo; si no, cualquiera activo ---
if ($Adaptador) {
  $nic = Get-NetAdapter -Name $Adaptador -ErrorAction SilentlyContinue
} else {
  $up = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
  $nic = $up | Where-Object { $_.PhysicalMediaType -eq '802.3' -or $_.MediaType -eq '802.3' } | Sort-Object Speed -Descending | Select-Object -First 1
  if (-not $nic) { $nic = $up | Sort-Object Speed -Descending | Select-Object -First 1 }
}
if (-not $nic) { Log "No encuentro un adaptador de red activo."; return }
$mac = $nic.MacAddress -replace '-',':'
$ip  = (Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
Log "Adaptador: $($nic.Name) [$($nic.PhysicalMediaType)] | MAC $mac | IP $ip | Speed $($nic.Speed)"

# --- 1) inicio rápido (sin tocar la hibernación: solo HiberbootEnabled=0) ---
$pk = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
if ($Verificar) {
  $fast = (Get-ItemProperty $pk -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
  Log "Inicio rapido (HiberbootEnabled): $fast  (0 = correcto)"
} else {
  reg export 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' (Join-Path $backup 'power.reg') /y 2>&1 | Out-Null
  Set-ItemProperty $pk -Name HiberbootEnabled -Value 0 -Type DWord -ErrorAction SilentlyContinue
  $now = (Get-ItemProperty $pk -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
  if ($now -eq 0) { Log "Inicio rapido desactivado (HiberbootEnabled=0). La hibernacion se mantiene." }
  else { Log "AVISO: no pude desactivar el inicio rapido (HiberbootEnabled=$now). Hacen falta permisos de administrador." }
}

# --- 2) WoL en la tarjeta: RegistryKeyword (independiente del idioma) + WMI root\wmi ---
$inst = $nic.PnPDeviceID
if ($Verificar) {
  Get-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword '*WakeOnMagicPacket','S5WakeOnLan','*EEE','EnableGreenEthernet','PowerSavingMode' -ErrorAction SilentlyContinue |
    ForEach-Object { Log ("  {0,-28} = {1}" -f $_.DisplayName, $_.DisplayValue) }
  Log "Pueden despertar el equipo (wake_armed):"; powercfg /devicequery wake_armed | ForEach-Object { Log "  $_" }
} else {
  $kw = @{ '*WakeOnMagicPacket'='1'; 'S5WakeOnLan'='1'; '*EEE'='0'; 'EnableGreenEthernet'='0' }
  foreach ($k in $kw.Keys) {
    if (Get-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword $k -ErrorAction SilentlyContinue) {
      try { Set-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword $k -RegistryValue $kw[$k] -NoRestart -ErrorAction Stop; Log "  $k -> $($kw[$k])" } catch {}
    }
  }
  powercfg /deviceenablewake "$($nic.InterfaceDescription)" 2>&1 | Out-Null
  Log "powercfg /deviceenablewake aplicado."
  foreach ($c in 'MSPower_DeviceWakeEnable','MSNdis_DeviceWakeOnMagicPacketOnly','MSPower_DeviceEnable') {
    $o = Get-CimInstance -Namespace root\wmi -ClassName $c -ErrorAction SilentlyContinue | Where-Object { $_.InstanceName -like "$inst*" }
    if ($o) {
      $v = if ($c -eq 'MSPower_DeviceEnable') { $false } else { $true }   # DeviceEnable=false => Windows no apaga el NIC
      try { $o | Set-CimInstance -Property @{ Enable = $v } -ErrorAction Stop; Log "  $c -> $v" } catch {}
    }
  }
  Restart-NetAdapter -Name $nic.Name -ErrorAction SilentlyContinue
  Start-Sleep 6
  Log "WoL aplicado por RegistryKeyword + WMI (EEE/Green off; solo paquete magico)."
}

# --- 3) plan de energía: no suspender con corriente ---
if (-not $Verificar) {
  powercfg /change standby-timeout-ac 0 2>&1 | Out-Null
  powercfg /change monitor-timeout-ac 15 2>&1 | Out-Null
  Log "Energia: no suspender con corriente."
}

# --- 4) apuntar MAC/IP ---
$ficha = [pscustomobject]@{ equipo=$env:COMPUTERNAME; adaptador=$nic.Name; mac=$mac; ip=$ip; fecha=(Get-Date) }
$ficha | Format-List | Out-String | Write-Host
if (-not $Verificar) { $ficha | ConvertTo-Json | Out-File (Join-Path $backup 'ficha-red.json') -Encoding utf8 }
Log "Apunta en tu macs.txt -> $($env:COMPUTERNAME.ToLower()) $mac ($ip)"

# --- 5) tarea de arranque (opcional) ---
if ($LanzadorRetomar) {
  if ($Verificar) {
    Log "Tarea de arranque 'AutorecoveryRetomar': $([bool](Get-ScheduledTask -TaskName 'AutorecoveryRetomar' -ErrorAction SilentlyContinue))"
  } elseif (Test-Path $LanzadorRetomar) {
    $act = New-ScheduledTaskAction -Execute $LanzadorRetomar
    $trg = New-ScheduledTaskTrigger -AtStartup
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName 'AutorecoveryRetomar' -Action $act -Trigger $trg -Settings $set -RunLevel Highest -Force | Out-Null
    Log "Tarea 'AutorecoveryRetomar' creada (lanza $LanzadorRetomar al iniciar)."
  } else {
    Log "AVISO: no existe el lanzador $LanzadorRetomar; tarea no creada."
  }
}

if ($Verificar) { Log "Verificacion terminada." } else { Log "Configuracion terminada. Copia y log en $backup" }
Log "Prueba (tras apagar este equipo): despertarlo desde otro con enviar-wol / despertar.py usando la MAC $mac"
if (-not $Verificar) { try { Stop-Transcript | Out-Null } catch {} }
