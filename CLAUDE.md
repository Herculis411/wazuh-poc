# Wazuh PoC — Claude Code Project Guide

## What This Project Is

This is a **Proof of Concept (PoC)** that demonstrates automated malware detection and removal
using **Wazuh SIEM** integrated with the **VirusTotal API**, deployed on **AWS** via **Terraform**.

When a malicious file appears on a monitored Linux endpoint, Wazuh detects it, queries
VirusTotal, and automatically deletes it — all without human intervention.

### The Detection Pipeline

```
1. FIM detects new file in /root on the agent (real-time monitoring)
       ↓
2. Wazuh sends the file hash to VirusTotal API automatically
       ↓
3. VirusTotal checks 60+ antivirus engines for malicious signatures
       ↓
4. Rule 87105 fires — VirusTotal flagged the file as malicious
       ↓
5. Active Response triggers remove-threat.sh on the agent
       ↓
6. File is deleted automatically from the endpoint
       ↓
7. Alert chain visible in Wazuh dashboard
```

---

## Project Structure

```
wazuh-poc/
├── CLAUDE.md                          ← You are here
├── README.md                          ← Full deployment guide
├── .gitignore                         ← Excludes tfvars, tfstate, .pem
├── terraform/
│   ├── providers.tf                   ← AWS provider, Terraform >= 1.5
│   ├── variables.tf                   ← All input variables
│   ├── main.tf                        ← VPC, SGs, EC2 instances
│   ├── outputs.tf                     ← IPs, URLs, SSH commands
│   ├── terraform.tfvars               ← YOUR SECRETS (never commit this)
│   └── terraform.tfvars.example       ← Safe template
└── scripts/
    ├── install-wazuh-server.sh        ← Server bootstrap: Wazuh all-in-one + VirusTotal config
    └── install-wazuh-agent.sh         ← Agent bootstrap: FIM + active response script
```

---

## Infrastructure

| Resource | Type | Purpose |
|---|---|---|
| wazuh-server | t3.medium (4GB RAM) | Wazuh Manager + Indexer + Dashboard |
| wazuh-agent | t3.micro | Monitored endpoint — FIM on /root |
| VPC | 10.0.0.0/16 | Isolated network |
| Security Groups | Server + Agent | Ports 22, 443, 1514, 1515, 55000 |

**Region:** us-east-1
**OS:** Ubuntu 22.04 LTS on both instances
**Wazuh version:** 4.7.5 — pinned on both server and agent (must match)
**Cost:** ~$0.24 for a 4-hour demo session

---

## Critical Facts

```
FACT 1: App listens on — Agent version MUST be 4.7.5 to match server
        Version mismatch causes: "Agent version must be lower or equal to manager version"

FACT 2: After install, MANAGER_IP placeholder in ossec.conf must be replaced
        with the real server private IP before the agent service starts

FACT 3: jq MUST be installed on the agent
        remove-threat.sh uses jq to parse JSON — fails silently without it

FACT 4: remove-threat.sh MUST have permissions 750 owned root:wazuh
        Wrong permissions = active response never fires

FACT 5: wazuh-passwords.txt is owned by ubuntu:ubuntu (not root)
        Read with: cat ~/wazuh-passwords.txt (no sudo needed)

FACT 6: integrations.log must exist with root:wazuh permissions
        If missing, VirusTotal API errors are completely silent
```

---

## Pre-Deployment Checklist

Before deploying, verify all of these:

```bash
# 1. AWS credentials working
aws sts get-caller-identity

# 2. Terraform installed
terraform --version   # needs >= 1.5.0

# 3. SSH key exists with correct permissions
ls -la ~/.ssh/wazuh-poc-key.pem   # must be -r--------

# 4. terraform.tfvars has real values (not placeholders)
cat terraform/terraform.tfvars

# 5. Your current public IP (update if changed)
curl ifconfig.me
```

---

## Deploying the PoC

### Step 1 — Deploy Infrastructure

```bash
cd terraform/
terraform init
terraform plan    # Expected: 9 resources to add
terraform apply   # Type: yes
```

After apply, note these outputs:
- `wazuh_server_public_ip` — needed for dashboard and SSH
- `wazuh_agent_public_ip` — needed for EICAR test
- `wazuh_dashboard_url` — open in browser after install

### Step 2 — Watch Server Bootstrap (10-15 minutes)

```bash
ssh -i ~/.ssh/wazuh-poc-key.pem ubuntu@<SERVER_PUBLIC_IP> \
  'tail -f /var/log/wazuh-server-install.log'
```

Wait for: `=== Wazuh Server Bootstrap COMPLETE ===`

### Step 3 — Get Dashboard Password

```bash
ssh -i ~/.ssh/wazuh-poc-key.pem ubuntu@<SERVER_PUBLIC_IP> \
  'cat ~/wazuh-passwords.txt'
```

Note the `admin` password.

### Step 4 — Watch Agent Bootstrap

```bash
ssh -i ~/.ssh/wazuh-poc-key.pem ubuntu@<AGENT_PUBLIC_IP> \
  'tail -f /var/log/wazuh-agent-install.log'
```

Wait for: `=== Wazuh Agent Bootstrap COMPLETE ===`

### Step 5 — Verify Agent Connected

```bash
ssh -i ~/.ssh/wazuh-poc-key.pem ubuntu@<AGENT_PUBLIC_IP>
sudo grep "Connected to the server\|Agent is now online" /var/ossec/logs/ossec.log
# Expected: Connected to the server ([10.x.x.x]:1514/tcp)
```

### Step 6 — Open Dashboard

```
URL:      https://<SERVER_PUBLIC_IP>
Username: admin
Password: from Step 3
```

Accept the self-signed certificate warning.
Go to **Agents** — confirm agent shows as **Active**.

### Step 7 — Run EICAR Test

SSH into the agent and drop the test file:

```bash
ssh -i ~/.ssh/wazuh-poc-key.pem ubuntu@<AGENT_PUBLIC_IP>
sudo curl -Lo /root/eicar.com https://secure.eicar.org/eicar.com
sudo tail -f /var/ossec/logs/active-responses.log
```

Within 1-2 minutes the file should be automatically deleted.

### Step 8 — Verify Results

```bash
# File should be gone
sudo ls /root/eicar.com
# Expected: No such file or directory

# Active response log should confirm
sudo cat /var/ossec/logs/active-responses.log
# Expected: Successfully removed threat
```

### Step 9 — View Alerts in Dashboard

Go to **Threat Hunting** and filter:
```
rule.id: is one of 553,100092,87105,100201
```

Expected alert chain:
- Rule 100201 — File added to /root
- Rule 87105 — VirusTotal: 60 engines detected malicious file
- Rule 100092 — remove-threat.sh removed the threat

---

## Agentic Deployment with Claude Code

Claude Code can deploy this entire PoC autonomously from a single instruction.

### Launch Claude Code

```bash
cd ~/projects/wazuh-poc
claude
```

### Give Claude Code This Prompt

```
Deploy the Wazuh PoC from this project.

1. Run terraform apply in terraform/ to provision the two EC2 instances
2. Watch the server bootstrap log until COMPLETE appears
3. Retrieve the dashboard admin password from ~/wazuh-passwords.txt on the server
4. Watch the agent bootstrap log until COMPLETE appears
5. Verify the agent connected to the server by checking ossec.log
6. Drop the EICAR test file in /root on the agent
7. Confirm the file was automatically deleted by the active response
8. Show me the active-responses.log output confirming the threat was removed
9. Give me the dashboard URL and credentials to view the alerts

Use the SSH key at ~/.ssh/wazuh-poc-key.pem for all SSH connections.
Read the terraform outputs for the public IPs after apply.
```

Claude Code will execute all 9 steps autonomously — running Terraform, SSHing into
both instances, monitoring logs, running the EICAR test, and reporting results.

### What Claude Code Does Autonomously

```
✓ Reads terraform.tfvars for configuration
✓ Runs terraform apply
✓ Reads terraform output for public IPs
✓ SSHs to server — monitors bootstrap log
✓ Waits for COMPLETE message
✓ Retrieves dashboard password
✓ SSHs to agent — monitors bootstrap log
✓ Verifies agent connected to server
✓ Drops EICAR test file on agent
✓ Confirms file was automatically deleted
✓ Reports active-responses.log output
✓ Provides dashboard URL and credentials
```

Human effort required: verify your IP has not changed (curl ifconfig.me), then type the prompt. API key and key pair are pre-configured in terraform.tfvars.

---

## Tearing Down

Always destroy after the demo to stop charges:

```bash
cd terraform/
terraform destroy   # Type: yes
# Expected: Destroy complete! Resources: 9 destroyed
```

Or tell Claude Code:
```
Destroy all AWS resources from this deployment and confirm all instances are terminated.
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| Agent version mismatch error | Agent installed newer version than server | Agent script pins wazuh-agent=4.7.5-1 |
| MANAGER_IP in ossec.conf | Placeholder not replaced | sed replaces it immediately after install |
| Permission denied on wazuh-passwords.txt | File owned by root | Script now chowns to ubuntu:ubuntu |
| 502 Bad Gateway on dashboard | Dashboard still starting | Wait 15 min, check: systemctl status wazuh-dashboard |
| EICAR file not deleted | VirusTotal API not firing | Check: sudo tail -f /var/ossec/logs/integrations.log |
| Agent shows Disconnected | Registration not complete | Wait 10 min, check ossec.log for Connected message |
| SSH connection refused | Your IP changed | Run curl ifconfig.me, update your_ip_cidr in tfvars |

---

## Key Files on the Remote Instances

### Wazuh Server

```bash
/var/ossec/etc/ossec.conf              # Main config — VirusTotal integration lives here
/var/ossec/etc/rules/local_rules.xml   # Custom FIM and active response rules
/var/ossec/logs/ossec.log              # Manager logs
/var/ossec/logs/integrations.log       # VirusTotal API call logs
/var/log/wazuh-server-install.log      # Bootstrap progress log
~/wazuh-passwords.txt                  # Dashboard admin password
```

### Wazuh Agent

```bash
/var/ossec/etc/ossec.conf                         # Agent config — FIM directory here
/var/ossec/active-response/bin/remove-threat.sh   # The deletion script
/var/ossec/logs/ossec.log                         # Agent logs — check for Connected
/var/ossec/logs/active-responses.log              # Active response results
/var/log/wazuh-agent-install.log                  # Bootstrap progress log
```

---

## Quick Reference Commands

```bash
# Deploy
cd terraform/ && terraform apply

# Server bootstrap log
ssh -i ~/.ssh/wazuh-poc-key.pem ubuntu@<SERVER_IP> \
  'tail -f /var/log/wazuh-server-install.log'

# Agent bootstrap log
ssh -i ~/.ssh/wazuh-poc-key.pem ubuntu@<AGENT_IP> \
  'tail -f /var/log/wazuh-agent-install.log'

# Dashboard password
ssh -i ~/.ssh/wazuh-poc-key.pem ubuntu@<SERVER_IP> 'cat ~/wazuh-passwords.txt'

# Check agent connected
ssh -i ~/.ssh/wazuh-poc-key.pem ubuntu@<AGENT_IP> \
  'sudo grep "Connected to the server" /var/ossec/logs/ossec.log'

# Drop EICAR test (run inside agent SSH session)
sudo curl -Lo /root/eicar.com https://secure.eicar.org/eicar.com

# Watch active response
sudo tail -f /var/ossec/logs/active-responses.log

# Verify file deleted
sudo ls /root/eicar.com

# Check VirusTotal log (on server)
sudo tail -f /var/ossec/logs/integrations.log

# Destroy
cd terraform/ && terraform destroy
```

---

## References

- [Wazuh PoC Guide](https://documentation.wazuh.com/current/proof-of-concept-guide/detect-remove-malware-virustotal.html)
- [VirusTotal API](https://developers.virustotal.com/reference)
- [Wazuh FIM Documentation](https://documentation.wazuh.com/current/user-manual/capabilities/file-integrity/index.html)
- [Claude Code Documentation](https://docs.claude.ai/code)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
