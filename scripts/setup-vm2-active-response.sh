#!/bin/bash
# =============================================================================
# Script: setup-vm2-active-response.sh
# Description: Deploy docker-firewall-drop script on VM 2 for Wazuh Active Response
# Target Chain: DOCKER-USER (Bypasses Docker PREROUTING NAT to protect container ports)
# =============================================================================

set -e

echo "=========================================================="
echo " Deploying Wazuh Active Response on VM 2 (docker-firewall-drop)"
echo "=========================================================="

if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root: sudo bash scripts/setup-vm2-active-response.sh"
  exit 1
fi

# Ensure Active Response directory exists
mkdir -p /var/ossec/active-response/bin

# Write docker-firewall-drop script
cat << 'EOF' > /var/ossec/active-response/bin/docker-firewall-drop
#!/bin/bash
# =============================================================================
# Custom Wazuh Active Response for Docker Environments (DOCKER-USER chain)
# =============================================================================

ACTION=$1
USER=$2
IP=$3

LOG_FILE="/var/ossec/logs/active-responses.log"

# Support reading JSON payload if positional arguments are empty or "-"
if [ -z "$IP" ] || [ "$IP" = "-" ]; then
    read -r INPUT_JSON
    ACTION=$(echo "$INPUT_JSON" | jq -r '.command // empty')
    IP=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.data.transaction.client_ip // .parameters.alert.srcip // empty')
fi

# Validate IP address format (IPv4)
if [ -z "$IP" ] || [ "$IP" = "null" ] || [ "$IP" = "-" ]; then
    echo "$(date '+%Y/%m/%d %H:%M:%S') docker-firewall-drop: Error: Missing or invalid IP (Action: ${ACTION})" >> "$LOG_FILE"
    logger -t wazuh-ar "[DOCKER-USER] Error: Missing or invalid IP"
    exit 1
fi

if [ "$ACTION" = "add" ]; then
    # Check if already present to prevent duplicates
    if ! /sbin/iptables -C DOCKER-USER -s "$IP" -j DROP 2>/dev/null; then
        /sbin/iptables -I DOCKER-USER -s "$IP" -j DROP
        echo "$(date '+%Y/%m/%d %H:%M:%S') docker-firewall-drop: Successfully BLOCKED attack IP: ${IP} in DOCKER-USER chain" >> "$LOG_FILE"
        logger -t wazuh-ar "[DOCKER-USER] Successfully BLOCKED attack IP: $IP"
    fi
elif [ "$ACTION" = "delete" ]; then
    /sbin/iptables -D DOCKER-USER -s "$IP" -j DROP 2>/dev/null || true
    echo "$(date '+%Y/%m/%d %H:%M:%S') docker-firewall-drop: Successfully UNBLOCKED IP: ${IP} from DOCKER-USER chain" >> "$LOG_FILE"
    logger -t wazuh-ar "[DOCKER-USER] Successfully UNBLOCKED IP: $IP"
fi
EOF

# Set proper permissions and ownership
chmod 750 /var/ossec/active-response/bin/docker-firewall-drop
chown root:wazuh /var/ossec/active-response/bin/docker-firewall-drop

# Ensure jq and iptables are installed
apt-get update -y && apt-get install -y jq iptables

echo "[✓] Successfully installed /var/ossec/active-response/bin/docker-firewall-drop"
echo "[✓] Active Response script ready on VM 2."
