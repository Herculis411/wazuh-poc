variable "aws_region" {
  description = "AWS region to deploy the Wazuh PoC"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Name of existing AWS key pair for SSH access"
  type        = string
}

variable "private_key_path" {
  description = "Local path to the private key .pem file"
  type        = string
  default     = "~/.ssh/wazuh-poc.pem"
}

variable "virustotal_api_key" {
  description = "Your VirusTotal API key (free or premium)"
  type        = string
  sensitive   = true
}

variable "your_ip_cidr" {
  description = "Your public IP in CIDR format for SSH access e.g. 1.2.3.4/32"
  type        = string
}

variable "wazuh_server_instance_type" {
  description = "EC2 instance type for Wazuh server (needs min 4GB RAM)"
  type        = string
  default     = "t3.medium"
}

variable "wazuh_agent_instance_type" {
  description = "EC2 instance type for Wazuh agent"
  type        = string
  default     = "t3.micro"
}

variable "ubuntu_ami" {
  description = "Ubuntu 22.04 LTS AMI ID for us-east-1"
  type        = string
  default     = "ami-0261755bbcb8c4a84"  # Ubuntu 22.04 LTS us-east-1
}
