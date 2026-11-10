@echo off
rem =============================================================================
rem Wazuh Active Response wrapper (Windows): win-firewall-drop
rem Target: C:\Program Files (x86)\ossec-agent\active-response\bin\win-firewall-drop.cmd
rem The 32-bit Wazuh agent pipes the alert JSON to stdin; forward it to 64-bit PowerShell.
rem =============================================================================
setlocal
set "PS_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS_EXE%" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0win-firewall-drop.ps1" %*
exit /b %ERRORLEVEL%
