#!/bin/bash
# =============================================================================
# Wazuh Agent Bootstrap Script — FIXED VERSION
# Fixes applied:
#   1. Version pinned to 4.7.5 to match server exactly
#   2. MANAGER_IP placeholder replaced before service start
#   3. Wait time increased to 8 minutes for server readiness
#   4. jq installed before active response script deployment
#   5. FIM syscheck disabled tag fix — sed targets correct pattern
# Based on: https://documentation.wazuh.com/current/proof-of-concept-guide/detect-remove-malware-virustotal.html
# =============================================================================

set -e
exec > /var/log/wazuh-agent-install.log 2>&1
echo "=== Wazuh Agent Bootstrap started: $(date) ==="

WAZUH_SERVER_IP="${WAZUH_SERVER_IP}"

# ── 1. System Update ──────────────────────────────────────────────────────────
echo "[1/6] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get install -y curl wget jq

# ── 2. Add Wazuh Repository ───────────────────────────────────────────────────
echo "[2/6] Adding Wazuh 4.7.5 repository..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | \
  gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg \
  --import && chmod 644 /usr/share/keyrings/wazuh.gpg

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  > /etc/apt/sources.list.d/wazuh.list

apt-get update -y

# ── 3. Wait for Server to be Ready ───────────────────────────────────────────
# FIX: Increased wait from 5 to 8 minutes — server all-in-one install takes longer
echo "[3/6] Waiting 8 minutes for Wazuh server to be fully ready..."
sleep 480

# ── 4. Install Wazuh Agent — pinned to 4.7.5 ─────────────────────────────────
# FIX: Version must match server exactly to avoid:
# ERROR: Agent version must be lower or equal to manager version
echo "[4/6] Installing Wazuh agent 4.7.5 (pinned to match server)..."
apt-get install -y wazuh-agent=4.7.5-1

# FIX: Replace MANAGER_IP placeholder immediately after install
# The default install sets MANAGER_IP as a placeholder — must replace before start
echo "Setting Wazuh manager IP to: $WAZUH_SERVER_IP"
sed -i "s|MANAGER_IP|$WAZUH_SERVER_IP|g" /var/ossec/etc/ossec.conf

# Verify the replacement worked
grep "address" /var/ossec/etc/ossec.conf | head -3

# ── 5. Configure FIM for /root Directory ──────────────────────────────────────
echo "[5/6] Configuring FIM to monitor /root directory in realtime..."

AGENT_CONF="/var/ossec/etc/ossec.conf"

# FIX: Target the syscheck disabled tag correctly
# Replace disabled yes with disabled no inside syscheck block
sed -i '/<syscheck>/,/<\/syscheck>/s|<disabled>yes</disabled>|<disabled>no</disabled>|' "$AGENT_CONF"

# Add realtime /root monitoring after <syscheck> opening tag
sed -i 's|<syscheck>|<syscheck>\n    <directories realtime="yes">/root</directories>|' "$AGENT_CONF"

# Verify FIM config
echo "=== FIM configuration ==="
grep -A3 "syscheck" "$AGENT_CONF" | head -10

# ── 5b. Deploy Active Response Script ────────────────────────────────────────
echo "Deploying active response script..."

cat > /var/ossec/active-response/bin/remove-threat.sh << 'SCRIPTEOF'
#!/bin/bash
# Active Response Script: remove-threat.sh
# Removes files flagged as malicious by VirusTotal
# Source: https://documentation.wazuh.com/current/proof-of-concept-guide/detect-remove-malware-virustotal.html

LOCAL=`dirname $0`;
cd $LOCAL
cd ../

PWD=`pwd`

read INPUT_JSON
FILENAME=$(echo $INPUT_JSON | jq -r .parameters.alert.data.virustotal.source.file)
COMMAND=$(echo $INPUT_JSON | jq -r .command)
LOG_FILE="${PWD}/../logs/active-responses.log"

#------------------------ Analyze command -------------------------#
if [ ${COMMAND} = "add" ]
then
  # Send control message to execd
  printf '{"version":1,"origin":{"name":"remove-threat","module":"active-response"},"command":"check_keys", "parameters":{"keys":[]}}\n'

  read RESPONSE
  COMMAND2=$(echo $RESPONSE | jq -r .command)
  if [ ${COMMAND2} != "continue" ]
  then
    echo "`date '+%Y/%m/%d %H:%M:%S'` $0: $INPUT_JSON Remove threat active response aborted" >> ${LOG_FILE}
    exit 0;
  fi
fi

# Removing file
rm -f $FILENAME
if [ $? -eq 0 ]; then
  echo "`date '+%Y/%m/%d %H:%M:%S'` $0: $INPUT_JSON Successfully removed threat" >> ${LOG_FILE}
else
  echo "`date '+%Y/%m/%d %H:%M:%S'` $0: $INPUT_JSON Error removing threat" >> ${LOG_FILE}
fi

exit 0;
SCRIPTEOF

# Set correct permissions as per official Wazuh documentation
chmod 750 /var/ossec/active-response/bin/remove-threat.sh
chown root:wazuh /var/ossec/active-response/bin/remove-threat.sh

echo "=== Active response script permissions ==="
ls -la /var/ossec/active-response/bin/remove-threat.sh

# ── 6. Start Wazuh Agent ──────────────────────────────────────────────────────
echo "[6/6] Starting Wazuh agent..."
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

# Wait for agent to connect
sleep 20

# Verify connection
echo "=== Agent status ==="
systemctl status wazuh-agent --no-pager | head -10

echo "=== Last 10 log lines ==="
tail -10 /var/ossec/logs/ossec.log

echo ""
echo "=============================================="
echo " Wazuh Agent Bootstrap COMPLETE: $(date)"
echo " Manager IP:  $WAZUH_SERVER_IP"
echo " Agent log:   sudo tail -f /var/ossec/logs/ossec.log"
echo " AR log:      sudo cat /var/ossec/logs/active-responses.log"
echo ""
echo " To run the PoC test:"
echo " sudo curl -Lo /root/eicar.com https://secure.eicar.org/eicar.com"
echo " sudo tail -f /var/ossec/logs/active-responses.log"
echo "=============================================="
