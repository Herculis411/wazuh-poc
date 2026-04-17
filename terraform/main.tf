# ── VPC ─────────────────────────────────────────────────────────────────────
resource "aws_vpc" "wazuh_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "wazuh-poc-vpc"
    Project = "wazuh-poc"
  }
}

# ── INTERNET GATEWAY ─────────────────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wazuh_vpc.id

  tags = {
    Name    = "wazuh-poc-igw"
    Project = "wazuh-poc"
  }
}

# ── PUBLIC SUBNET ────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.wazuh_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name    = "wazuh-poc-public-subnet"
    Project = "wazuh-poc"
  }
}

# ── ROUTE TABLE ──────────────────────────────────────────────────────────────
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wazuh_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name    = "wazuh-poc-public-rt"
    Project = "wazuh-poc"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# ── SECURITY GROUP: WAZUH SERVER ─────────────────────────────────────────────
# Ports:
#   22    SSH from your IP only
#   443   Wazuh dashboard (HTTPS)
#   1514  Agent communication (TCP/UDP)
#   1515  Agent enrollment
#   55000 Wazuh API
resource "aws_security_group" "wazuh_server_sg" {
  name        = "wazuh-server-sg"
  description = "Security group for Wazuh server"
  vpc_id      = aws_vpc.wazuh_vpc.id

  ingress {
    description = "SSH from your IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  ingress {
    description = "Wazuh dashboard HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  ingress {
    description = "Wazuh agent comms TCP"
    from_port   = 1514
    to_port     = 1514
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Wazuh agent comms UDP"
    from_port   = 1514
    to_port     = 1514
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Wazuh agent enrollment"
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Wazuh API"
    from_port   = 55000
    to_port     = 55000
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "wazuh-server-sg"
    Project = "wazuh-poc"
  }
}

# ── SECURITY GROUP: WAZUH AGENT ──────────────────────────────────────────────
resource "aws_security_group" "wazuh_agent_sg" {
  name        = "wazuh-agent-sg"
  description = "Security group for Wazuh agent"
  vpc_id      = aws_vpc.wazuh_vpc.id

  ingress {
    description = "SSH from your IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "wazuh-agent-sg"
    Project = "wazuh-poc"
  }
}

# ── WAZUH SERVER EC2 ─────────────────────────────────────────────────────────
resource "aws_instance" "wazuh_server" {
  ami                    = var.ubuntu_ami
  instance_type          = var.wazuh_server_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.wazuh_server_sg.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = <<-USERDATA
    #!/bin/bash
    export VIRUSTOTAL_API_KEY="${var.virustotal_api_key}"
    ${file("${path.module}/../scripts/install-wazuh-server.sh")}
  USERDATA

  tags = {
    Name    = "wazuh-server"
    Role    = "wazuh-server"
    Project = "wazuh-poc"
  }
}

# ── WAZUH AGENT EC2 ──────────────────────────────────────────────────────────
resource "aws_instance" "wazuh_agent" {
  ami                    = var.ubuntu_ami
  instance_type          = var.wazuh_agent_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.wazuh_agent_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-USERDATA
    #!/bin/bash
    export WAZUH_SERVER_IP="${aws_instance.wazuh_server.private_ip}"
    ${file("${path.module}/../scripts/install-wazuh-agent.sh")}
  USERDATA

  # Agent must wait for server to be ready
  depends_on = [aws_instance.wazuh_server]

  tags = {
    Name    = "wazuh-agent"
    Role    = "wazuh-agent"
    Project = "wazuh-poc"
  }
}
