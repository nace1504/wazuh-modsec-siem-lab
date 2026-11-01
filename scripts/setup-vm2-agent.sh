#!/bin/bash
# =============================================================================
# Script: setup-vm2-agent.sh
# Description: Automate Wazuh Agent installation and configuration on VM 2
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
  echo "[-] Please run as root (sudo bash setup-vm2-agent.sh)"
  exit 1
fi

# 1. Ensure log directory exists on VM 2 Host for Docker bind-mount
echo "[+] Creating ModSecurity log directory on host: /var/log/modsec"
mkdir -p /var/log/modsec
touch /var/log/modsec/modsec_audit.log
chmod 755 /var/log/modsec
chmod 666 /var/log/modsec/modsec_audit.log

# 2. Install prerequisites and GPG key
echo "[+] Adding Wazuh repository..."
apt-get update -y && apt-get install -y curl apt-transport-https lsb-release gnupg2
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list
apt-get update -y

# 3. Install Wazuh Agent matching Manager version
echo "[+] Installing Wazuh Agent (${WAZUH_VERSION})..."
WAZUH_MANAGER="${WAZUH_MANAGER_IP}" WAZUH_AGENT_NAME="${WAZUH_AGENT_NAME}" apt-get install -y --allow-downgrades wazuh-agent="${WAZUH_VERSION}"

# Ensure Manager IP is correctly set in ossec.conf
sed -i "s/<address>.*<\/address>/<address>${WAZUH_MANAGER_IP}<\/address>/" /var/ossec/etc/ossec.conf

# 4. Explicit Agent Enrollment with Manager (Generate client.keys)
echo "[+] Registering Agent with Wazuh Manager (${WAZUH_MANAGER_IP}:1515)..."
/var/ossec/bin/agent-auth -m "${WAZUH_MANAGER_IP}" -A "${WAZUH_AGENT_NAME}" || {
  echo "[!] Warning: agent-auth connection failed. Agent will retry auto-enrollment on service start."
}

# 5. Inject JSON localfile configuration into /var/ossec/etc/ossec.conf
echo "[+] Configuring /var/ossec/etc/ossec.conf for ModSecurity JSON logs..."
if ! grep -q "/var/log/modsec/modsec_audit.log" /var/ossec/etc/ossec.conf; then
  sed -i '/<\/ossec_config>/i \
  <localfile>\
    <log_format>json<\/log_format>\
    <location>\/var\/log\/modsec\/modsec_audit.log<\/location>\
  <\/localfile>' /var/ossec/etc/ossec.conf
  echo "[+] Injected ModSecurity JSON localfile block successfully."
else
  echo "[*] Localfile block already present in ossec.conf."
fi

# 6. Enable and start Wazuh Agent
echo "[+] Starting wazuh-agent service..."
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl restart wazuh-agent

echo "=========================================================="
echo "[✓] Wazuh Agent successfully configured and started!"
echo "    Status check: systemctl status wazuh-agent"
echo "=========================================================="

