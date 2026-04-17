#!/bin/bash
# =============================================================================
# Wazuh Server Bootstrap Script — FIXED VERSION
# Fixes applied:
#   1. <name> tag was written as <n> — corrected to <name>
#   2. Wazuh version pinned to 4.7.5 to match agent
#   3. wazuh-passwords.txt chowned to ubuntu user
#   4. Config validation before restart
#   5. integrations.log created with correct permissions
# Based on: https://documentation.wazuh.com/current/proof-of-concept-guide/detect-remove-malware-virustotal.html
# =============================================================================

set -e
exec > /var/log/wazuh-server-install.log 2>&1
echo "=== Wazuh Server Bootstrap started: $(date) ==="

VIRUSTOTAL_API_KEY="${VIRUSTOTAL_API_KEY}"

# ── 1. System Update ──────────────────────────────────────────────────────────
echo "[1/7] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get install -y curl wget jq

# ── 2. Download Wazuh 4.7.5 Installation Assistant ───────────────────────────
echo "[2/7] Downloading Wazuh 4.7.5 installation assistant..."
cd /tmp
curl -sO https://packages.wazuh.com/4.7/wazuh-install.sh
curl -sO https://packages.wazuh.com/4.7/config.yml

# ── 3. Configure Wazuh Installation ──────────────────────────────────────────
echo "[3/7] Configuring Wazuh installation..."
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

cat > /tmp/config.yml << CONFIGEOF
nodes:
  indexer:
    - name: node-1
      ip: "$PRIVATE_IP"
  server:
    - name: wazuh-1
      ip: "$PRIVATE_IP"
  dashboard:
    - name: dashboard
      ip: "$PRIVATE_IP"
CONFIGEOF

# ── 4. Run Wazuh All-in-One Installation ──────────────────────────────────────
echo "[4/7] Running Wazuh all-in-one installation (10-15 minutes)..."
bash /tmp/wazuh-install.sh -a -i 2>&1 | tee -a /var/log/wazuh-server-install.log
echo "=== Wazuh all-in-one installation complete ==="

# Save passwords readable by ubuntu user
if [ -f /tmp/wazuh-install-files.tar ]; then
  tar -O -xvf /tmp/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt \
    > /home/ubuntu/wazuh-passwords.txt 2>/dev/null || true
  chown ubuntu:ubuntu /home/ubuntu/wazuh-passwords.txt
  chmod 640 /home/ubuntu/wazuh-passwords.txt
  echo "=== Passwords saved to /home/ubuntu/wazuh-passwords.txt ==="
fi

# ── 5. Add Custom FIM and VirusTotal Rules ────────────────────────────────────
echo "[5/7] Adding custom rules..."
RULES_FILE="/var/ossec/etc/rules/local_rules.xml"

cat >> "$RULES_FILE" << 'RULESEOF'

<!-- VirusTotal PoC Rules: FIM monitoring /root directory -->
<group name="syscheck,pci_dss_11.5,nist_800_53_SI.7,">
    <rule id="100200" level="7">
        <if_sid>550</if_sid>
        <field name="file">/root</field>
        <description>File modified in /root directory.</description>
    </rule>
    <rule id="100201" level="7">
        <if_sid>554</if_sid>
        <field name="file">/root</field>
        <description>File added to /root directory.</description>
    </rule>
</group>

<!-- Active Response result rules -->
<group name="virustotal,">
    <rule id="100092" level="12">
        <if_sid>657</if_sid>
        <match>Successfully removed threat</match>
        <description>$(parameters.program) removed threat located at $(parameters.alert.data.virustotal.source.file)</description>
    </rule>
    <rule id="100093" level="12">
        <if_sid>657</if_sid>
        <match>Error removing threat</match>
        <description>Error removing threat located at $(parameters.alert.data.virustotal.source.file)</description>
    </rule>
</group>
RULESEOF

chown root:wazuh "$RULES_FILE"

# ── 6. Configure VirusTotal Integration + Active Response ────────────────────
echo "[6/7] Configuring VirusTotal integration and Active Response..."
OSSEC_CONF="/var/ossec/etc/ossec.conf"

# Remove closing tag, append config blocks, re-add closing tag
head -n -1 "$OSSEC_CONF" > /tmp/ossec_temp.conf

cat >> /tmp/ossec_temp.conf << INTEGRATIONEOF

  <!-- VirusTotal Integration -->
  <integration>
    <name>virustotal</name>
    <api_key>$VIRUSTOTAL_API_KEY</api_key>
    <rule_id>100200,100201</rule_id>
    <alert_format>json</alert_format>
  </integration>

  <!-- Active Response Command -->
  <command>
    <name>remove-threat</name>
    <executable>remove-threat.sh</executable>
    <timeout_allowed>no</timeout_allowed>
  </command>

  <!-- Active Response — fires on rule 87105 (VirusTotal malicious detection) -->
  <active-response>
    <disabled>no</disabled>
    <command>remove-threat</command>
    <location>local</location>
    <rules_id>87105</rules_id>
  </active-response>

</ossec_config>
INTEGRATIONEOF

mv /tmp/ossec_temp.conf "$OSSEC_CONF"
chown root:wazuh "$OSSEC_CONF"

# Create integrations log with correct permissions
touch /var/ossec/logs/integrations.log
chown root:wazuh /var/ossec/logs/integrations.log
chmod 660 /var/ossec/logs/integrations.log

# ── 7. Restart and Verify ─────────────────────────────────────────────────────
echo "[7/7] Restarting Wazuh manager..."
systemctl restart wazuh-manager
sleep 45

echo "=== Service status ==="
systemctl status wazuh-manager --no-pager | head -5
systemctl status wazuh-indexer --no-pager | head -5
systemctl status wazuh-dashboard --no-pager | head -5

echo "=== VirusTotal config check ==="
grep -A5 "virustotal" /var/ossec/etc/ossec.conf || echo "WARNING: virustotal block not found"

echo "=== Custom rules check ==="
grep "100200\|100201\|100092" /var/ossec/etc/rules/local_rules.xml

echo ""
echo "=============================================="
echo " Wazuh Server Bootstrap COMPLETE: $(date)"
echo " Dashboard:    https://$PUBLIC_IP"
echo " Credentials:  cat ~/wazuh-passwords.txt"
echo " VT log:       sudo tail -f /var/ossec/logs/integrations.log"
echo " Manager log:  sudo tail -f /var/ossec/logs/ossec.log"
echo "=============================================="
