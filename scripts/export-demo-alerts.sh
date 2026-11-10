#!/bin/bash
# =============================================================================
# Script: export-demo-alerts.sh
# Description: Export Wazuh alerts of a demo window as labeled, redacted JSONL
#              (+ summary.md, packed as .tar.gz) for AI alert-triage agents
# Run on VM 3 (Wazuh Manager):
#   sudo bash scripts/export-demo-alerts.sh [START] [END]
#   START/END: local time "YYYY-MM-DDTHH:MM:SS" (default: last 3 hours -> now)
# Optional env overrides:
#   AGENTS="vm4-win-client,vm2-web-target"  MIN_LEVEL=3  ATTACKER_IP=192.168.1.10
#   ALERTS_DIR=/var/ossec/logs/alerts       OUT_DIR=<home of sudo user>
# =============================================================================

set -euo pipefail

START="${1:-$(date -d '-3 hours' +%Y-%m-%dT%H:%M:%S)}"
END="${2:-$(date +%Y-%m-%dT%H:%M:%S)}"
AGENTS="${AGENTS:-vm4-win-client,vm2-web-target}"
MIN_LEVEL="${MIN_LEVEL:-3}"
ATTACKER_IP="${ATTACKER_IP:-192.168.1.10}"
ALERTS_DIR="${ALERTS_DIR:-/var/ossec/logs/alerts}"
OUT_DIR="${OUT_DIR:-$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}[-] jq not found. Install it: sudo apt install -y jq${NC}"
    exit 1
fi
if [ ! -r "${ALERTS_DIR}/alerts.json" ]; then
    echo -e "${RED}[-] Cannot read ${ALERTS_DIR}/alerts.json - run with sudo on the Wazuh Manager (VM 3).${NC}"
    exit 1
fi
for t in "$START" "$END"; do
    if ! [[ "$t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || ! date -d "$t" >/dev/null 2>&1; then
        echo -e "${RED}[-] Invalid time '$t'. Use format YYYY-MM-DDTHH:MM:SS${NC}"
        exit 1
    fi
done

STAMP="$(date +%Y%m%d-%H%M%S)"
NAME="demo-alerts-${STAMP}"
WORK="${OUT_DIR}/${NAME}"
mkdir -p "$WORK"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo -e "${CYAN}==========================================================${NC}"
echo -e "${CYAN} Wazuh Demo Alerts Export (for AI triage agents)          ${NC}"
echo -e "${CYAN} Window     : ${START} -> ${END}${NC}"
echo -e "${CYAN} Agents     : ${AGENTS}${NC}"
echo -e "${CYAN} Min level  : ${MIN_LEVEL}   Attacker IP: ${ATTACKER_IP}${NC}"
echo -e "${CYAN}==========================================================${NC}"

# 1. Collect raw alerts: alerts.json for today, rotated ossec-alerts-DD.json.gz for past days
echo "[+] Collecting alert files ..."
RAW="${TMP}/raw.jsonl"
: > "$RAW"
day="$(date -d "${START%T*}" +%Y-%m-%d)"
last="$(date -d "${END%T*}" +%Y-%m-%d)"
today="$(date +%Y-%m-%d)"
while [[ "$day" < "$last" || "$day" == "$last" ]]; do
    if [ "$day" == "$today" ]; then
        cat "${ALERTS_DIR}/alerts.json" >> "$RAW"
        echo "    - ${ALERTS_DIR}/alerts.json"
    else
        gz="${ALERTS_DIR}/$(LC_ALL=C date -d "$day" +%Y/%b)/ossec-alerts-$(date -d "$day" +%d).json.gz"
        if [ -f "$gz" ]; then
            zcat "$gz" >> "$RAW"
            echo "    - $gz"
        else
            echo -e "    ${YELLOW}- missing $gz (skipped)${NC}"
        fi
    fi
    day="$(date -d "$day +1 day" +%Y-%m-%d)"
done

# 2. Filter, label (ground_truth), redact passwords, dedupe and sort by time
echo "[+] Filtering, labeling and redacting ..."
jq -c -R --arg s "$START" --arg e "$END" --arg agents "$AGENTS" \
   --arg min "$MIN_LEVEL" --arg atk "$ATTACKER_IP" '
  fromjson?
  | select(.timestamp >= $s and .timestamp <= $e)
  | select(.agent.name as $n | ($agents | split(",")) | index($n))
  | select((.rule.level // 0) >= ($min | tonumber))
  | (.rule.id | tonumber) as $rid
  | ([.data.win.eventdata.ipAddress, .data.srcip, .data.transaction.client_ip] | map(select(. != null))) as $ips
  | (($ips | index($atk)) != null) as $from_attacker
  | (tostring | test("lab-backdoor|WAZUH-LAB-TEST|sekurlsa::"; "i")) as $simulated
  | .ground_truth = (
      if $from_attacker and $rid >= 100100 and $rid <= 100110 then
        {label: "true_positive", scenario: "web_attack_waf",
         reason: "Web attack (SQLi/XSS/LFI/RCE) from attacker \($atk) blocked by ModSecurity CRS v4"}
      elif $from_attacker and ($rid == 100200 or $rid == 100201) then
        {label: "true_positive", scenario: "smb_bruteforce",
         reason: "SMB password brute-force from attacker \($atk) (test-windows-attacks.sh)"}
      elif $simulated or ($rid >= 100202 and $rid <= 100213) then
        {label: "true_positive", scenario: "post_exploitation_simulation",
         reason: "Simulated post-exploitation on VM 4 (simulate-windows-events.ps1)"}
      elif $from_attacker then
        {label: "true_positive", scenario: "attacker_ip_activity",
         reason: "Built-in Wazuh rule triggered by traffic from attacker \($atk)"}
      else
        {label: "benign", scenario: "background",
         reason: "Normal system activity during the demo window (not part of the attack)"}
      end)
  | walk(if type == "string"
         then gsub("(?<a>\\buser\\s+[^\\s/]+\\s+)[^\\s/]+(?<b>\\s+/add)"; "\(.a)***REDACTED***\(.b)"; "i")
         else . end)
' "$RAW" > "${TMP}/filtered.jsonl"

jq -c -s 'unique_by(.id) | sort_by(.timestamp) | .[]' "${TMP}/filtered.jsonl" > "${WORK}/alerts.jsonl"
TOTAL="$(wc -l < "${WORK}/alerts.jsonl")"
if [ "$TOTAL" -eq 0 ]; then
    echo -e "${YELLOW}[!] No alerts matched. Check the time window (alert timestamps are local time of VM 3).${NC}"
    rm -rf "$WORK"
    exit 1
fi

# 3. Human/AI-readable summary
echo "[+] Writing summary.md ..."
WAZUH_VER="$(/var/ossec/bin/wazuh-control info -v 2>/dev/null || true)"
WAZUH_VER="${WAZUH_VER:-unknown}"
{
cat << EOF
# Wazuh Demo Alerts Export

| Field | Value |
| :--- | :--- |
| Exported at | $(date '+%Y-%m-%d %H:%M:%S %z') |
| Time window (VM 3 local time) | \`${START}\` -> \`${END}\` |
| Agents | \`${AGENTS}\` |
| Minimum rule level | ${MIN_LEVEL} |
| Wazuh version | ${WAZUH_VER} |
| Total alerts | ${TOTAL} |

## Lab environment

| Host | IP | Role |
| :--- | :--- | :--- |
| VM 1 Kali Linux | \`${ATTACKER_IP}\` | **Attacker** |
| VM 2 Ubuntu (\`vm2-web-target\`) | \`192.168.1.20\` | ModSecurity CRS v4 WAF + DVWA, Wazuh agent |
| VM 3 Ubuntu (\`vm3-wazuh-server\`) | \`192.168.1.30\` | Wazuh manager / indexer / dashboard |
| VM 4 Windows 10 (\`vm4-win-client\`) | \`192.168.1.40\` | Endpoint: Wazuh agent + Sysmon |

## Labels (\`ground_truth\` field added to every alert)

| Label | Scenario | Meaning |
| :--- | :--- | :--- |
| \`true_positive\` | \`web_attack_waf\` | Rules 100100-100110: web attacks from the attacker, blocked by the WAF |
| \`true_positive\` | \`smb_bruteforce\` | Rules 100200/100201: SMB brute-force from the attacker; 100201 triggered Active Response (Windows Firewall block) |
| \`true_positive\` | \`post_exploitation_simulation\` | Rules 100202-100213 or events of the simulated account \`lab-backdoor\`: user creation, admin group add, encoded PowerShell, discovery, mimikatz-like command line |
| \`true_positive\` | \`attacker_ip_activity\` | Built-in Wazuh rules matching traffic from \`${ATTACKER_IP}\` |
| \`benign\` | \`background\` | Everything else: normal OS/agent activity during the window |

> Labels are assigned automatically by rule ID / source IP / test markers. Review borderline alerts manually before using them as an evaluation set.

### Count by label

| Label | Scenario | Alerts |
| :--- | :--- | ---: |
EOF
jq -s -r 'group_by(.ground_truth.label + "/" + .ground_truth.scenario)[]
          | "| `\(.[0].ground_truth.label)` | `\(.[0].ground_truth.scenario)` | \(length) |"' "${WORK}/alerts.jsonl"

cat << 'EOF'

### Count by rule

| Rule ID | Level | Count | Label | Description (first occurrence) |
| :---: | :---: | ---: | :--- | :--- |
EOF
jq -s -r 'group_by(.rule.id) | sort_by(.[0].rule.id | tonumber)[]
          | "| \(.[0].rule.id) | \(.[0].rule.level) | \(length) | `\(.[0].ground_truth.label)` | \(.[0].rule.description | gsub("\\|"; "\\|")) |"' "${WORK}/alerts.jsonl"

cat << 'EOF'

## Key fields (each line of `alerts.jsonl` is one native Wazuh alert)

| Field | Description |
| :--- | :--- |
| `timestamp` | Alert time (VM 3 local time with offset) |
| `rule.id`, `rule.level`, `rule.description` | Wazuh rule that fired (level 0-15) |
| `rule.mitre.id`, `rule.mitre.tactic`, `rule.mitre.technique` | MITRE ATT&CK mapping |
| `rule.groups` | Rule groups (e.g. `custom_windows`, `modsecurity`, `active_response`) |
| `agent.name`, `agent.ip` | Endpoint that produced the event |
| `data.win.system.eventID`, `data.win.eventdata.*` | Windows / Sysmon event fields (`ipAddress`, `targetUserName`, `commandLine`, `image`, `parentImage`, ...) |
| `data.transaction.*` | ModSecurity audit log fields (`client_ip`, `request.uri`, `response.http_code`, `messages`) |
| `full_log` | Original raw event |
| `ground_truth.label`, `ground_truth.scenario`, `ground_truth.reason` | **Added by this export** - expected triage verdict |

Passwords passed on command lines (`net user <name> <password> /add`) are replaced by `***REDACTED***`.
EOF
} > "${WORK}/summary.md"

# 4. Pack and hand ownership back to the sudo user
tar -czf "${OUT_DIR}/${NAME}.tar.gz" -C "$OUT_DIR" "$NAME"
if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER": "$WORK" "${OUT_DIR}/${NAME}.tar.gz"
fi

echo -e "\n--- [Export Result] ---"
jq -s -r 'group_by(.ground_truth.label)[] | "    \(.[0].ground_truth.label): \(length)"' "${WORK}/alerts.jsonl"
echo -e "${GREEN}[✓] ${TOTAL} alerts exported${NC}"
echo "    Folder : ${WORK}/ (alerts.jsonl, summary.md)"
echo "    Archive: ${OUT_DIR}/${NAME}.tar.gz"
echo -e "\n----------------------------------------------------------"
echo -e "👉 Copy to your Windows host (PowerShell):"
echo -e "   ${CYAN}scp ${SUDO_USER:-$(id -un)}@192.168.1.30:${OUT_DIR}/${NAME}.tar.gz .${NC}"
echo -e "----------------------------------------------------------"
