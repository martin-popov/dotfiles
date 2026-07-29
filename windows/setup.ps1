#Requires -RunAsAdministrator
# ============================================================
# Windows key remaps -- Martin Popov
# Usage (elevated PowerShell, from a Windows checkout of this repo):
#   .\windows\setup.ps1
# Idempotent: safe to re-run.
# ============================================================
$ErrorActionPreference = 'Stop'

function Log  { param($m) Write-Host "==> $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "!!  $m" -ForegroundColor Yellow }

$NeedsReboot = $false
$AhkScript = Join-Path $PSScriptRoot 'keys.ahk'
if (-not (Test-Path $AhkScript)) { throw "keys.ahk not found next to this script ($PSScriptRoot)" }

# --- AutoHotkey v2 ------------------------------------------
$Ahk = Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'
if (-not (Test-Path $Ahk)) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found -- install AutoHotkey v2 manually and re-run'
  }
  Log 'installing AutoHotkey v2 (winget)'
  winget install --exact --id AutoHotkey.AutoHotkey --silent `
    --accept-package-agreements --accept-source-agreements
}
if (-not (Test-Path $Ahk)) { throw "AutoHotkey v2 not at $Ahk -- install it and re-run" }

& $Ahk /ErrorStdOut /validate $AhkScript
if ($LASTEXITCODE -ne 0) { throw "keys.ahk failed AutoHotkey validation (exit $LASTEXITCODE)" }

# --- Caps Lock -> Esc, at the driver level ------------------
# HKLM Scancode Map: 8B header, 4B count (incl. null terminator),
# 4B per mapping (target scancode LE, source scancode LE), 4B null.
# 0x01 = Esc, 0x3A = Caps Lock.
$KbLayout = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
$Expected = [byte[]](0,0,0,0, 0,0,0,0, 2,0,0,0, 0x01,0x00,0x3A,0x00, 0,0,0,0)
$Current  = (Get-ItemProperty -Path $KbLayout -Name 'Scancode Map' -ErrorAction SilentlyContinue).'Scancode Map'
if (($Current -join ',') -ne ($Expected -join ',')) {
  Log 'writing Scancode Map (Caps Lock -> Esc) -- takes effect after a reboot'
  Set-ItemProperty -Path $KbLayout -Name 'Scancode Map' -Value $Expected -Type Binary
  $NeedsReboot = $true
} else {
  Log 'Scancode Map already set (Caps Lock -> Esc)'
}

# --- logon task, elevated -----------------------------------
# Highest privileges so the hook still fires when an admin window has focus.
$TaskName = 'dotfiles-keys'
Log "registering scheduled task '$TaskName' -> $AhkScript"
Register-ScheduledTask -TaskName $TaskName -Force `
  -Action    (New-ScheduledTaskAction -Execute $Ahk -Argument "`"$AhkScript`"") `
  -Trigger   (New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME") `
  -Principal (New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                -LogonType Interactive -RunLevel Highest) `
  -Settings  (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -MultipleInstances IgnoreNew `
                -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)) | Out-Null

Stop-ScheduledTask  -TaskName $TaskName -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $TaskName

# --- verify -------------------------------------------------
$Written = (Get-ItemProperty -Path $KbLayout -Name 'Scancode Map').'Scancode Map'
if (($Written -join ',') -ne ($Expected -join ',')) { throw 'Scancode Map readback mismatch' }
if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) { throw "task '$TaskName' not registered" }
Start-Sleep -Seconds 2
if (-not (Get-Process AutoHotkey64 -ErrorAction SilentlyContinue)) {
  Warn "AutoHotkey isn't running -- check Task Scheduler > $TaskName for the last result code"
}
Log 'verified: registry value + task registered'

Warn 'turn OFF PowerToys Keyboard Manager, or both will remap and fight each other'
if ($NeedsReboot) { Warn 'reboot for Caps Lock -> Esc (the other five are live now)' }
