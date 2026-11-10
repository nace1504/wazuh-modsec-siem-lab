# =============================================================================
# Script: setup-vm4-windows-agent.ps1
# Description: Automate Wazuh Agent + Sysmon + audit policy setup on VM 4 (Windows 10)
# Usage (PowerShell as Administrator, from repo root):
#   powershell -ExecutionPolicy Bypass -File .\scripts\setup-vm4-windows-agent.ps1 `
#       -ManagerIP 192.168.1.30 -AgentName vm4-win-client
# NOTE: keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI).
# =============================================================================
param(
    [string]$ManagerIP    = '192.168.1.30',
    [string]$AgentName    = 'vm4-win-client',
    [string]$AgentGroup   = 'windows',
    [string]$WazuhVersion = '4.8.2-1',
    [string]$LabSubnet    = '192.168.1.0/24',
    [string]$SysmonConfigUrl = 'https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$OssecDir = 'C:\Program Files (x86)\ossec-agent'
$WorkDir  = Join-Path $env:TEMP 'wazuh-lab-setup'
$RepoRoot = Split-Path $PSScriptRoot -Parent

function Step([string]$Message) { Write-Host "[+] $Message" -ForegroundColor Cyan }
function Ok([string]$Message)   { Write-Host "[OK] $Message" -ForegroundColor Green }
function Warn([string]$Message) { Write-Host "[!] $Message" -ForegroundColor Yellow }

Write-Host '=========================================================='
Write-Host ' Starting Wazuh Agent Setup on VM 4 (Windows 10 Client)'
Write-Host " Wazuh Manager IP : $ManagerIP"
Write-Host " Wazuh Agent Name : $AgentName"
Write-Host " Wazuh Agent Group: $AgentGroup"
Write-Host " Wazuh Version    : $WazuhVersion"
Write-Host '=========================================================='

# 0. Ensure running as Administrator
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[-] Please run PowerShell as Administrator.' -ForegroundColor Red
    exit 1
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# 1. Install Wazuh Agent (MSI) - skip if already installed
if (Get-Service -Name WazuhSvc -ErrorAction SilentlyContinue) {
    Warn 'Wazuh Agent already installed (service WazuhSvc exists) - skipping MSI install.'
} else {
    $msi = Join-Path $WorkDir "wazuh-agent-$WazuhVersion.msi"
    Step "Downloading Wazuh Agent $WazuhVersion ..."
    Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WazuhVersion.msi" -OutFile $msi -UseBasicParsing
    Step 'Installing Wazuh Agent (silent) ...'
    $msiArgs = "/i `"$msi`" /q WAZUH_MANAGER=$ManagerIP WAZUH_REGISTRATION_SERVER=$ManagerIP WAZUH_AGENT_NAME=$AgentName WAZUH_AGENT_GROUP=$AgentGroup"
    $proc = Start-Process -FilePath msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "msiexec failed with exit code $($proc.ExitCode)" }
    Ok 'Wazuh Agent installed.'
}

# 2. Install or update Sysmon with SwiftOnSecurity config
Step 'Downloading Sysmon and configuration ...'
$sysmonZip = Join-Path $WorkDir 'Sysmon.zip'
$sysmonDir = Join-Path $WorkDir 'Sysmon'
$sysmonCfg = Join-Path $WorkDir 'sysmonconfig.xml'
Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/Sysmon.zip' -OutFile $sysmonZip -UseBasicParsing
Expand-Archive -Path $sysmonZip -DestinationPath $sysmonDir -Force
Invoke-WebRequest -Uri $SysmonConfigUrl -OutFile $sysmonCfg -UseBasicParsing
$sysmonExe = Join-Path $sysmonDir 'Sysmon64.exe'
if (Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue) {
    Step 'Sysmon already installed - updating configuration ...'
    & $sysmonExe -c $sysmonCfg | Out-Null
} else {
    Step 'Installing Sysmon64 ...'
    & $sysmonExe -accepteula -i $sysmonCfg | Out-Null
}
Ok 'Sysmon is running (channel Microsoft-Windows-Sysmon/Operational).'

# 3. Audit policy (GUIDs are language-independent)
Step 'Configuring advanced audit policy ...'
$auditSubcategories = @{
    'Logon'                     = '{0CCE9215-69AE-11D9-BED3-505054503030}'
    'Account Lockout'           = '{0CCE9217-69AE-11D9-BED3-505054503030}'
    'User Account Management'   = '{0CCE9235-69AE-11D9-BED3-505054503030}'
    'Security Group Management' = '{0CCE9237-69AE-11D9-BED3-505054503030}'
    'Process Creation'          = '{0CCE922B-69AE-11D9-BED3-505054503030}'
}
foreach ($name in $auditSubcategories.Keys) {
    & auditpol.exe /set "/subcategory:$($auditSubcategories[$name])" /success:enable /failure:enable | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "auditpol failed for subcategory '$name'" }
    Ok "Audit '$name': Success + Failure"
}

# 4. PowerShell Script Block Logging (Event 4104)
Step 'Enabling PowerShell Script Block Logging ...'
$sblKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
New-Item -Path $sblKey -Force | Out-Null
Set-ItemProperty -Path $sblKey -Name EnableScriptBlockLogging -Value 1 -Type DWord
Ok 'Script Block Logging enabled.'

# 5. Windows Firewall: allow ICMP, SMB (445) and RDP (3389) from the lab subnet only
Step "Opening ICMP / SMB / RDP from $LabSubnet for the attack lab ..."
$labRules = @(
    @{ Name = 'Lab-Allow-ICMPv4'; Protocol = 'ICMPv4'; Port = $null },
    @{ Name = 'Lab-Allow-SMB-445'; Protocol = 'TCP'; Port = 445 },
    @{ Name = 'Lab-Allow-RDP-3389'; Protocol = 'TCP'; Port = 3389 }
)
foreach ($r in $labRules) {
    Get-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    $fwArgs = @{ Name = $r.Name; DisplayName = $r.Name; Direction = 'Inbound'; Action = 'Allow'; Protocol = $r.Protocol; RemoteAddress = $LabSubnet; Profile = 'Any' }
    if ($r.Port) { $fwArgs.LocalPort = $r.Port }
    New-NetFirewallRule @fwArgs | Out-Null
    Ok "Firewall rule $($r.Name)"
}
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Ok 'Remote Desktop enabled.'

# 6. Deploy custom Active Response script (win-firewall-drop)
Step 'Deploying Active Response script win-firewall-drop ...'
$arSrc = Join-Path $RepoRoot 'vm4-windows-client\active-response'
$arDst = Join-Path $OssecDir 'active-response\bin'
foreach ($f in 'win-firewall-drop.cmd', 'win-firewall-drop.ps1') {
    $src = Join-Path $arSrc $f
    if (-not (Test-Path $src)) { throw "Missing $src - run this script from the cloned repository." }
    Copy-Item -Path $src -Destination $arDst -Force
    Unblock-File -Path (Join-Path $arDst $f)
}
Ok "Installed to $arDst"

# 7. Start Wazuh Agent and verify connection
Step 'Starting WazuhSvc ...'
Set-Service -Name WazuhSvc -StartupType Automatic
Restart-Service -Name WazuhSvc
Start-Sleep -Seconds 15
$svc = Get-Service -Name WazuhSvc
$ossecLog = Join-Path $OssecDir 'ossec.log'
$connected = Select-String -Path $ossecLog -Pattern 'Connected to the server' -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -Last 1

Write-Host '=========================================================='
if ($svc.Status -eq 'Running' -and $connected) {
    Ok "Wazuh Agent is running and connected to $ManagerIP"
} else {
    Warn "WazuhSvc status: $($svc.Status). Check: Get-Content '$ossecLog' -Tail 30"
}
Write-Host "    Verify on VM 3: sudo /var/ossec/bin/agent_control -l"
Write-Host '=========================================================='
