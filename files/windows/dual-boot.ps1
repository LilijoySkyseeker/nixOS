# Windows settings for a PC that dual-boots with NixOS, matching the
# NixOS side (modules/nixos/hibernate-only.nix):
#   - the hardware clock is UTC, as Linux keeps it
#   - hibernate in place of sleep: lid closed, sleep button, critical
#     battery and idle all hibernate; Sleep is hidden from the power menu
#   - nothing happens on idle (no screen off, no sleep) until the hibernate
#   - PowerToys Awake, a tray toggle that pauses the idle hibernate
#
# Run once per Windows install, from an administrator PowerShell:
#   powershell -ExecutionPolicy Bypass -File dual-boot.ps1 [-IdleMinutes 60]
param([int]$IdleMinutes = 60)

$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an administrator PowerShell.'
}

# hardware clock in UTC
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
    -Name RealTimeIsUniversal -PropertyType QWord -Value 1 -Force | Out-Null

# hibernation on (it also backs the power menu's Hibernate entry)
powercfg /hibernate on

# action values: 0 nothing, 1 sleep, 2 hibernate, 3 shut down
foreach ($mode in '/setacvalueindex', '/setdcvalueindex') {
    powercfg $mode SCHEME_CURRENT SUB_BUTTONS LIDACTION 2
    powercfg $mode SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 2
    powercfg $mode SCHEME_CURRENT SUB_BATTERY BATACTIONCRIT 2
}

# idle: no screen off and no sleep, then hibernate
foreach ($power in 'ac', 'dc') {
    powercfg /change "monitor-timeout-$power" 0
    powercfg /change "standby-timeout-$power" 0
    powercfg /change "hibernate-timeout-$power" $IdleMinutes
}
powercfg /setactive SCHEME_CURRENT

# power menu: Hibernate shown, Sleep hidden
$flyout = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings'
New-Item -Path $flyout -Force | Out-Null
New-ItemProperty -Path $flyout -Name ShowHibernateOption -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $flyout -Name ShowSleepOption -PropertyType DWord -Value 0 -Force | Out-Null

# PowerToys Awake pauses the idle timer from the tray (needs the internet)
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warning 'winget not found: install PowerToys (Microsoft.PowerToys) by hand.'
} else {
    winget install --id Microsoft.PowerToys --exact --silent --accept-package-agreements --accept-source-agreements
}

Write-Host "Done. Idle hibernate after $IdleMinutes minutes; the clock change applies from the next boot."
