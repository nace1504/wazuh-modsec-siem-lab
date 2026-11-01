#!/bin/bash
# =============================================================================
# Script: setup-vm2-agent.sh
# Description: Automate clean Wazuh Agent installation and configuration on VM 2
# =============================================================================

set -e

# Load environment variables from .env if present
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
elif [ -f ../.env ]; then
  export $(grep -v '^#' ../.env | xargs)
fi

WAZUH_MANAGER_IP="${1:-${WAZUH_MANAGER_IP:-192.168.1.30}}"
WAZUH_AGENT_NAME="${2:-${WAZUH_AGENT_NAME:-vm2-web-target}}"
WAZUH_VERSION="${3:-${WAZUH_VERSION:-4.8.2-1}}"

echo "=========================================================="
echo " Starting Wazuh Agent Setup on VM 2 (Web Target / WAF Host)"
echo " Wazuh Manager IP : ${WAZUH_MANAGER_IP}"
echo " Wazuh Agent Name : ${WAZUH_AGENT_NAME}"
echo " Wazuh Version    : ${WAZUH_VERSION}"
echo "=========================================================="

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root: sudo bash scripts/setup-vm2-agent.sh"
  exit 1
fi

# 1. Ensure log directory exists on VM 2 Host for Docker bind-mount
echo "[+] Ensuring ModSecurity log directory on host: /var/log/modsec"
mkdir -p /var/log/modsec
touch /var/log/modsec/modsec_audit.log
chmod 755 /var/log/modsec
chmod 666 /var/log/modsec/modsec_audit.log

# 2. Configure Wazuh repository cleanly (eliminate duplicate source warnings)
echo "[+] Configuring Wazuh repository..."
apt-get update -y && apt-get install -y curl apt-transport-https lsb-release gnupg2
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import --yes
chmod 644 /usr/share/keyrings/wazuh.gpg

# Overwrite cleanly to avoid duplicate apt warnings
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list > /dev/null
apt-get update -y

# 3. Preserve existing client.keys if already enrolled
PRESERVED_KEY=0
if [ -s /var/ossec/etc/client.keys ]; then
  echo "[+] Found existing valid agent credentials, backing up..."
  cp /var/ossec/etc/client.keys /tmp/client.keys.bak
  PRESERVED_KEY=1
fi

# 4. Clean purge old/incompatible version config files if upgrading or downgrading
echo "[+] Ensuring clean package environment for version ${WAZUH_VERSION}..."
systemctl stop wazuh-agent 2>/dev/null || true
apt-get purge -y wazuh-agent 2>/dev/null || true
rm -rf /var/ossec

# 5. Install fresh, authentic Wazuh Agent package for target version
echo "[+] Installing clean Wazuh Agent (${WAZUH_VERSION})..."
WAZUH_MANAGER="${WAZUH_MANAGER_IP}" WAZUH_AGENT_NAME="${WAZUH_AGENT_NAME}" apt-get install -y wazuh-agent="${WAZUH_VERSION}"

# 6. Restore or request agent enrollment key
if [ "$PRESERVED_KEY" -eq 1 ] && [ -s /tmp/client.keys.bak ]; then
  echo "[+] Restoring preserved agent credentials..."
  cp /tmp/client.keys.bak /var/ossec/etc/client.keys
  chown root:wazuh /var/ossec/etc/client.keys
  chmod 640 /var/ossec/etc/client.keys
  rm -f /tmp/client.keys.bak
else
  echo "[+] Requesting enrollment key from Wazuh Manager (${WAZUH_MANAGER_IP}:1515)..."
  /var/ossec/bin/agent-auth -m "${WAZUH_MANAGER_IP}" -A "${WAZUH_AGENT_NAME}" || {
    echo "[*] Warning from agent-auth. If agent name already exists on Manager, verify via agent_control on VM 3."
  }
fi

# 7. Configure Manager address in ossec.conf
echo "[+] Configuring Manager IP (${WAZUH_MANAGER_IP}) in /var/ossec/etc/ossec.conf..."
sed -i "s/<address>.*<\/address>/<address>${WAZUH_MANAGER_IP}<\/address>/" /var/ossec/etc/ossec.conf

# 8. Inject ModSecurity JSON log ingestion block
echo "[+] Injecting ModSecurity JSON log configuration..."
if ! grep -q "/var/log/modsec/modsec_audit.log" /var/ossec/etc/ossec.conf; then
  sed -i '/<\/ossec_config>/i \
  <localfile>\
    <log_format>json<\/log_format>\
    <location>\/var\/log\/modsec\/modsec_audit.log<\/location>\
  <\/localfile>' /var/ossec/etc/ossec.conf
  echo "[+] Injected ModSecurity JSON localfile block successfully."
fi

# 9. Enable and start Wazuh Agent
echo "[+] Starting wazuh-agent service..."
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl restart wazuh-agent

echo "=========================================================="
echo "[✓] Wazuh Agent successfully configured and running!"
echo "    Verify status: sudo systemctl status wazuh-agent"
echo "=========================================================="
