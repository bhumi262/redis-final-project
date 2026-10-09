output "redis_server_public_ip" {
  description = "Public IP of the Redis EC2 instance"
  value       = aws_instance.redis_server.public_ip
}
