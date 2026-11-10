# =============================================================================
# Script: simulate-windows-events.ps1
# Description: Generate SAFE post-exploitation-like events on VM 4 to verify
#              Wazuh custom rules 100202-100213 (no real malware is executed).
# Usage (PowerShell as Administrator on VM 4):
#   powershell -ExecutionPolicy Bypass -File .\scripts\simulate-windows-events.ps1 [-ClearSecurityLog]
# NOTE: keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI).
# =============================================================================
param(
    [string]$TestUser = 'lab-backdoor',
    [switch]$ClearSecurityLog   # Event 1102 (rule 100204) - wipes the local Security log!
)

$ErrorActionPreference = 'Stop'

function Test-Case([string]$Rule, [string]$Name, [scriptblock]$Action) {
    Write-Host "[*] $Rule : $Name ... " -NoNewline -ForegroundColor Yellow
    try {
        & $Action | Out-Null
        Write-Host 'DONE' -ForegroundColor Green
    } catch {
        Write-Host "FAILED ($($_.Exception.Message))" -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[-] Please run PowerShell as Administrator.' -ForegroundColor Red
    exit 1
}

Write-Host '==========================================================' -ForegroundColor Cyan
Write-Host ' Windows Endpoint Detection Verification Suite (VM 4)'      -ForegroundColor Cyan
Write-Host '==========================================================' -ForegroundColor Cyan

# Persistence: create local account via net.exe (Event 4720 + Sysmon "net user ... /add")
$password = 'Lab#' + (Get-Random -Minimum 100000 -Maximum 999999) + 'xY'
Test-Case '100202/100211' "Create local user '$TestUser'" {
    if (Get-LocalUser -Name $TestUser -ErrorAction SilentlyContinue) { Remove-LocalUser -Name $TestUser }
    & net.exe user $TestUser $password /add
}

# Privilege escalation: add to Administrators by well-known SID (Event 4732)
Test-Case '100203' "Add '$TestUser' to Administrators" {
    Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $TestUser
}

# Discovery (Sysmon Event 1)
Test-Case '100211' 'Discovery: whoami /priv' { & whoami.exe /priv }
Test-Case '100211' 'Discovery: net localgroup' { & net.exe localgroup }

# Execution: encoded PowerShell launched from cmd.exe (Sysmon Event 1 + Script Block 4104)
$payload = "Write-Output 'WAZUH-LAB-TEST'; Invoke-Expression 'Get-Date'"
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
Test-Case '100210/100213' 'PowerShell -EncodedCommand' {
    & cmd.exe /c "powershell.exe -NoProfile -EncodedCommand $b64"
}

# Credential access indicator: harmless echo of a mimikatz command string (Sysmon Event 1)
Test-Case '100212' 'Credential dumping indicator (echo sekurlsa::)' {
    & cmd.exe /c 'echo sekurlsa::logonpasswords > nul'
}

# Optional anti-forensics: clear Security log (Event 1102)
if ($ClearSecurityLog) {
    Test-Case '100204' 'Clear Security event log' { & wevtutil.exe cl Security }
}

# Cleanup test account
Test-Case 'cleanup' "Remove local user '$TestUser'" { Remove-LocalUser -Name $TestUser }

Write-Host '----------------------------------------------------------'
Write-Host 'Check alerts on VM 3:'
Write-Host "  sudo tail -f /var/ossec/logs/alerts/alerts.json | jq -c 'select(.agent.name==""vm4-win-client"") | {id: .rule.id, level: .rule.level, desc: .rule.description}'"
Write-Host '----------------------------------------------------------'
