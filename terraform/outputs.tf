output "wazuh_server_public_ip" {
  description = "Public IP of the Wazuh server"
  value       = aws_instance.wazuh_server.public_ip
}

output "wazuh_agent_public_ip" {
  description = "Public IP of the Wazuh agent"
  value       = aws_instance.wazuh_agent.public_ip
}

output "wazuh_dashboard_url" {
  description = "Wazuh dashboard URL"
  value       = "https://${aws_instance.wazuh_server.public_ip}"
}

output "wazuh_dashboard_credentials" {
  description = "Default Wazuh dashboard login credentials"
  value       = "Username: admin  |  Password: See /var/ossec/logs/ossec.log after install or run: sudo tar -O -xvf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt"
}

output "ssh_server_command" {
  description = "SSH command for Wazuh server"
  value       = "ssh -i ${var.private_key_path} ubuntu@${aws_instance.wazuh_server.public_ip}"
}

output "ssh_agent_command" {
  description = "SSH command for Wazuh agent"
  value       = "ssh -i ${var.private_key_path} ubuntu@${aws_instance.wazuh_agent.public_ip}"
}

output "wazuh_server_private_ip" {
  description = "Private IP of Wazuh server (used by agent for registration)"
  value       = aws_instance.wazuh_server.private_ip
}

output "bootstrap_log_server" {
  description = "Command to watch server bootstrap progress"
  value       = "ssh -i ${var.private_key_path} ubuntu@${aws_instance.wazuh_server.public_ip} 'tail -f /var/log/wazuh-server-install.log'"
}

output "bootstrap_log_agent" {
  description = "Command to watch agent bootstrap progress"
  value       = "ssh -i ${var.private_key_path} ubuntu@${aws_instance.wazuh_agent.public_ip} 'tail -f /var/log/wazuh-agent-install.log'"
}
