# =============================================================================
# Custom Wazuh Active Response for Windows endpoints (Windows Defender Firewall)
# Target: C:\Program Files (x86)\ossec-agent\active-response\bin\win-firewall-drop.ps1
#
# Called by win-firewall-drop.cmd. Two modes:
#   1. Wazuh agent: no arguments, alert JSON on stdin (command = add / delete)
#   2. Manual:      win-firewall-drop.ps1 <add|delete> <IP>
# =============================================================================
param(
    [string]$Action,
    [string]$Ip
)

$LogFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'active-responses.log'
$Netsh   = Join-Path $env:SystemRoot 'System32\netsh.exe'

function Write-ArLog([string]$Message) {
    $line = '{0} win-firewall-drop: {1}' -f (Get-Date -Format 'yyyy/MM/dd HH:mm:ss'), $Message
    Add-Content -Path $LogFile -Value $line -Encoding ASCII
}

# Read JSON payload from the Wazuh agent if positional arguments are empty
if (-not $Ip) {
    try {
        $alert  = [Console]::In.ReadLine() | ConvertFrom-Json
        $Action = $alert.command
        $Ip     = $alert.parameters.alert.data.win.eventdata.ipAddress
        if (-not $Ip) { $Ip = $alert.parameters.alert.data.srcip }
    } catch {
        Write-ArLog 'Error: Cannot parse input JSON from Wazuh agent'
        exit 1
    }
}

# Validate IP address (reject empty, "-", loopback)
$parsed = $null
if (-not $Ip -or -not [System.Net.IPAddress]::TryParse($Ip, [ref]$parsed) -or [System.Net.IPAddress]::IsLoopback($parsed)) {
    Write-ArLog "Error: Missing or invalid IP '$Ip' (Action: $Action)"
    exit 1
}

$RuleName = "WazuhAR-Block-$Ip"

switch ($Action) {
    'add' {
        # Check if already present to prevent duplicates
        & $Netsh advfirewall firewall show rule name="$RuleName" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & $Netsh advfirewall firewall add rule name="$RuleName" dir=in action=block remoteip=$Ip | Out-Null
            Write-ArLog "Successfully BLOCKED attack IP: $Ip (Windows Firewall rule '$RuleName')"
        }
    }
    'delete' {
        & $Netsh advfirewall firewall delete rule name="$RuleName" | Out-Null
        Write-ArLog "Successfully UNBLOCKED IP: $Ip (Windows Firewall rule '$RuleName')"
    }
    default {
        Write-ArLog "Error: Unknown action '$Action' for IP $Ip"
        exit 1
    }
}
exit 0
