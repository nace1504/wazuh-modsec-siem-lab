#!/bin/bash
# =============================================================================
# Script: test-windows-attacks.sh
# Description: SMB brute-force simulator (VM 1 Kali -> VM 4 Windows 10) for
#              testing Wazuh rules 100200/100201 and Active Response win-firewall-drop
# Usage: bash scripts/test-windows-attacks.sh [WINDOWS_IP] [ATTEMPTS]
# =============================================================================

TARGET_IP="${1:-192.168.1.40}"
ATTEMPTS="${2:-15}"
FAKE_USER="lab-bruteforce"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}==========================================================${NC}"
echo -e "${CYAN} Windows Endpoint Brute-force & Active Response Suite      ${NC}"
echo -e "${CYAN} Target Host: ${TARGET_IP} (SMB 445)                       ${NC}"
echo -e "${CYAN}==========================================================${NC}"

if ! command -v smbclient >/dev/null 2>&1; then
    echo -e "${RED}[-] smbclient not found. Install it: sudo apt install -y smbclient${NC}"
    exit 1
fi

port_open() {
    timeout 3 bash -c "</dev/tcp/${TARGET_IP}/445" 2>/dev/null
}

echo -e "\n--- [Phase 1: Reachability Baseline] ---"
echo -ne "[*] Checking SMB port 445 on ${TARGET_IP} ... "
if port_open; then
    echo -e "${GREEN}[PASS] Port 445 open${NC}"
else
    echo -e "${RED}[FAIL] Port 445 unreachable. Check Lab-Allow-SMB-445 firewall rule / existing block on VM 4.${NC}"
    exit 1
fi

echo -e "\n--- [Phase 2: SMB Password Brute-force (Event 4625 -> Rule 100200)] ---"
echo -ne "[*] Sending ${ATTEMPTS} failed logons as '${FAKE_USER}' (Rule 100201 threshold >= 8 in 60s) "
BLOCKED_AT=0
for i in $(seq 1 "$ATTEMPTS"); do
    timeout 5 smbclient -L "//${TARGET_IP}" -U "${FAKE_USER}%WrongPass${i}!" -m SMB3 >/dev/null 2>&1
    if [ $? -eq 124 ]; then
        BLOCKED_AT=$i
        break
    fi
    echo -n "."
    sleep 0.3
done
echo ""
if [ "$BLOCKED_AT" -gt 0 ]; then
    echo -e "${GREEN}[✓] Connection stalled at attempt #${BLOCKED_AT} -> Active Response already kicked in${NC}"
fi

echo -e "\n--- [Phase 3: Automated Verification of IP Blocking] ---"
echo -ne "[*] Waiting for Wazuh Manager -> Agent Active Response propagation ... "
sleep 5
echo "done"
echo -ne "[*] Re-checking SMB port 445 from Attacker host ... "
if port_open; then
    echo -e "${YELLOW}[NOTE] Port 445 still reachable. Check 'netsh advfirewall firewall show rule name=all | findstr WazuhAR' on VM 4.${NC}"
else
    echo -e "${GREEN}[PASS] Attacker IP is successfully BLOCKED by Windows Firewall! (Connection timed out)${NC}"
    echo -e "${BOLD}${GREEN}[✓] Windows Endpoint Detection & Response Test PASSED${NC}"
fi

echo -e "\n----------------------------------------------------------"
echo -e "👉 To unblock IP immediately on VM 4 (PowerShell as Administrator), run:"
echo -e "   ${CYAN}& 'C:\\Program Files (x86)\\ossec-agent\\active-response\\bin\\win-firewall-drop.cmd' delete 192.168.1.10${NC}"
echo -e "----------------------------------------------------------"
