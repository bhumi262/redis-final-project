
# Public IP of Flask dashboard and bastion EC2
output "app_server_public_ip" {
  description = "Public IP of the application and bastion EC2"
  value       = aws_instance.app_server.public_ip
}

# Private IP of Redis node 1
output "redis_node_1_private_ip" {
  description = "Private IP of Redis node 1"
  value       = aws_instance.redis_node_1.private_ip
}

# Private IP of Redis node 2
output "redis_node_2_private_ip" {
  description = "Private IP of Redis node 2"
  value       = aws_instance.redis_node_2.private_ip
}

# Private IP of Redis node 3
output "redis_node_3_private_ip" {
  description = "Private IP of Redis node 3"
  value       = aws_instance.redis_node_3.private_ip
}

# All Redis private IPs together
output "redis_private_ips" {
  description = "Private IP addresses of all three Redis nodes"
  value = [
    aws_instance.redis_node_1.private_ip,
    aws_instance.redis_node_2.private_ip,
    aws_instance.redis_node_3.private_ip
  ]
}
