#!/bin/bash
# =============================================================================
# Script: test-attacks.sh
# Description: Automated HTTP attack simulator for testing ModSecurity + Wazuh
# =============================================================================

TARGET_HOST="${1:-http://192.168.1.20}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}==========================================================${NC}"
echo -e "${CYAN} WAF & SIEM Security Pipeline Verification Suite         ${NC}"
echo -e "${CYAN} Target Host: ${TARGET_HOST}                             ${NC}"
echo -e "${CYAN}==========================================================${NC}"

test_request() {
    local test_name="$1"
    local uri="$2"
    local expected_code="$3"

    echo -ne "[*] Testing: ${YELLOW}${test_name}${NC} ... "
    
    local http_code
    http_code=$(curl -s -L -o /dev/null -w "%{http_code}" "${TARGET_HOST}${uri}")

    if [ "$http_code" -eq "$expected_code" ]; then
        echo -e "${GREEN}[PASS] HTTP ${http_code} (As expected)${NC}"
    else
        echo -e "${RED}[ALERT] Expected ${expected_code} but got HTTP ${http_code}${NC}"
    fi
}

echo -e "\n--- [Phase 1: Normal Traffic Baseline] ---"
test_request "Normal Index Page" "/" 200

echo -e "\n--- [Phase 2: Web Attacks (CRS v4 Protection)] ---"
# 1. SQL Injection (CRS Rule 942xxx)
test_request "SQL Injection (OR 1=1)" "/?id=1%27%20OR%20%271%27=%271" 403
test_request "SQL Injection (UNION SELECT)" "/?id=1%20UNION%20SELECT%20null,version()--" 403

# 2. Cross-Site Scripting (CRS Rule 941xxx)
test_request "Cross-Site Scripting (Script Tag)" "/?search=%3Cscript%3Ealert(%27XSS%27)%3C/script%3E" 403
test_request "Cross-Site Scripting (Img Onerror)" "/?search=%3Cimg%20src=x%20onerror=alert(1)%3E" 403

# 3. Path Traversal / LFI (CRS Rule 930xxx)
test_request "Path Traversal (/etc/passwd)" "/?page=../../../../etc/passwd" 403

# 4. Remote Code Execution (CRS Rule 932xxx)
test_request "Command Injection (; cat /etc/passwd)" "/?cmd=127.0.0.1;cat%20/etc/passwd" 403

echo -e "\n--- [Phase 3: High-Frequency Trigger for Active Response] ---"
echo "[*] Sending 5 consecutive malicious requests to trigger Rule 100110..."
for i in {1..5}; do
    curl -s -o /dev/null "${TARGET_HOST}/?id=test_attack_${i}%27%20OR%201=1--"
    echo -n "."
    sleep 0.5
done
echo -e "\n${GREEN}[✓] Attack sequence completed. Check Wazuh Dashboard & alerts!${NC}"

