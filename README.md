# Wazuh PoC — Detect and Remove Malware Using VirusTotal on AWS

Deploys a full Wazuh PoC on AWS with two Ubuntu EC2 instances:
- **wazuh-server** — Wazuh all-in-one (Manager + Indexer + Dashboard)
- **wazuh-agent** — Monitored Ubuntu endpoint with FIM + Active Response

Based on the official guide:
https://documentation.wazuh.com/current/proof-of-concept-guide/detect-remove-malware-virustotal.html

---

## How the PoC Works

```
1. FIM detects new file in /root on the agent
       ↓
2. Wazuh sends file hash to VirusTotal API
       ↓
3. VirusTotal checks 70+ antivirus engines
       ↓
4. If malicious → Wazuh fires active-response
       ↓
5. remove-threat.sh deletes the file automatically
       ↓
6. Alert appears in Wazuh dashboard
```

---

## Project Structure

```
wazuh-poc/
├── terraform/
│   ├── providers.tf              # AWS provider config
│   ├── variables.tf              # All variables with descriptions
│   ├── main.tf                   # VPC, SGs, EC2 instances
│   ├── outputs.tf                # IPs, URLs, SSH commands
│   └── terraform.tfvars.example  # Copy to terraform.tfvars
├── scripts/
│   ├── install-wazuh-server.sh   # Server bootstrap — all-in-one install
│   └── install-wazuh-agent.sh    # Agent bootstrap — FIM + AR script
└── README.md
```

---

## Prerequisites

Before starting you need:

1. **AWS CLI configured** with your IAM credentials
   ```bash
   aws configure
   aws sts get-caller-identity   # confirm access
   ```

2. **Terraform installed** (>= 1.5.0)
   ```bash
   terraform --version
   ```

3. **An AWS Key Pair** — create one in EC2 > Key Pairs if you do not have one
   ```bash
   aws ec2 describe-key-pairs --output table
   ```

4. **A VirusTotal API key** — free from https://virustotal.com
   - Sign up → go to your profile → copy the API key
   - Free tier: 4 requests per minute (sufficient for PoC)

5. **Your public IP**
   ```bash
   curl ifconfig.me
   ```

---

## Step-by-Step Deployment

### Step 1 — Clone or navigate to the project

```bash
cd ~/projects/wazuh-poc
```

### Step 2 — Create your terraform.tfvars

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your real values:

```hcl
aws_region         = "us-east-1"
key_name           = "your-key-pair-name"
private_key_path   = "~/.ssh/your-key.pem"
virustotal_api_key = "YOUR_VIRUSTOTAL_API_KEY"
your_ip_cidr       = "YOUR_PUBLIC_IP/32"
```

### Step 3 — Initialise Terraform

```bash
terraform init
```

### Step 4 — Preview the deployment

```bash
terraform plan
# Expected: Plan: 8 to add, 0 to change, 0 to destroy
```

Resources created:
- 1 VPC
- 1 Internet Gateway
- 1 Public Subnet
- 1 Route Table + Association
- 2 Security Groups (server + agent)
- 2 EC2 instances (wazuh-server t3.medium + wazuh-agent t3.micro)

### Step 5 — Deploy

```bash
terraform apply
# Type: yes
```

Terraform will output the IPs and URLs when provisioning completes.
The bootstrap scripts run automatically — Wazuh install takes 10-15 minutes.

### Step 6 — Watch the Server Bootstrap Progress

Open a second terminal and watch the install log:

```bash
# Get the command from terraform output
terraform output bootstrap_log_server

# Run the printed command — example:
ssh -i ~/.ssh/your-key.pem ubuntu@<server_ip> 'tail -f /var/log/wazuh-server-install.log'
```

Wait until you see:
```
=== Wazuh Server Bootstrap COMPLETE ===
```

### Step 7 — Get the Dashboard Password

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<server_ip>
cat ~/wazuh-passwords.txt
```

Note the `admin` password.

### Step 8 — Access the Wazuh Dashboard

Open in browser:
```
https://<server_public_ip>
```

- **Username:** `admin`
- **Password:** from Step 7

Accept the self-signed certificate warning.

### Step 9 — Verify the Agent is Connected

In the Wazuh dashboard:
- Go to **Agents** tab
- You should see `wazuh-agent` listed as **Active**

Allow 5-10 minutes after server boot for the agent to register.

---

## Running the PoC Test

### Drop the EICAR Test File

SSH into the **wazuh-agent** instance:

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<agent_public_ip>
```

Download the EICAR test file to the monitored /root directory:

```bash
sudo curl -Lo /root/eicar.com https://secure.eicar.org/eicar.com && ls -lah /root/eicar.com
```

### What Should Happen (within 1-2 minutes)

1. FIM detects the new file in `/root`
2. Wazuh sends the file hash to VirusTotal
3. VirusTotal flags it as malicious
4. Active response fires — `remove-threat.sh` deletes the file
5. File disappears from `/root`
6. Alert appears in Wazuh dashboard

### Verify the File Was Deleted

```bash
ls /root/eicar.com   # Should return: No such file or directory
```

### Check the Active Response Log

```bash
sudo cat /var/ossec/logs/active-responses.log
# Expected: Successfully removed threat
```

### View Alerts in Dashboard

Go to **Threat Hunting** in the Wazuh dashboard and filter by:
```
rule.id: is one of 553,100092,87105,100201
```

You should see:
- Rule 100201 — File added to /root directory
- Rule 87105 — VirusTotal malicious file detected
- Rule 100092 — remove-threat.sh removed the file

---

## Cost Estimate

| Resource | Type | Hourly |
|---|---|---|
| wazuh-server | t3.medium | ~$0.042 |
| wazuh-agent | t3.micro | ~$0.013 |
| Storage | 70GB gp3 total | ~$0.006 |
| **4 hour demo** | | **~$0.24** |

---

## Tear Down (Stop All Charges)

```bash
cd terraform/
terraform destroy
# Type: yes
```

All 8 resources will be destroyed.

---

## Troubleshooting

**Agent not showing in dashboard after 15 minutes:**
```bash
# SSH to agent and check status
ssh -i ~/.ssh/your-key.pem ubuntu@<agent_ip>
sudo systemctl status wazuh-agent
sudo cat /var/ossec/logs/ossec.log | tail -30
```

**VirusTotal not triggering:**
- Free API has 4 requests/minute limit — wait a minute and retry
- Check integratord log on server: `sudo cat /var/ossec/logs/integrations.log`

**Dashboard not loading:**
- Server install takes 10-15 minutes — wait and retry
- Check install log: `sudo cat /var/log/wazuh-server-install.log`

**EICAR file not being deleted:**
- Check active response log: `sudo cat /var/ossec/logs/active-responses.log`
- Verify jq is installed on agent: `which jq`
- Verify script permissions: `ls -la /var/ossec/active-response/bin/remove-threat.sh`
  - Should show: `-rwxr-x--- root wazuh`

---

## Reference

- [Wazuh PoC Guide](https://documentation.wazuh.com/current/proof-of-concept-guide/detect-remove-malware-virustotal.html)
- [VirusTotal API](https://developers.virustotal.com/reference)
- [Wazuh FIM Documentation](https://documentation.wazuh.com/current/user-manual/capabilities/file-integrity/index.html)
- [Wazuh Active Response](https://documentation.wazuh.com/current/user-manual/capabilities/active-response/index.html)
