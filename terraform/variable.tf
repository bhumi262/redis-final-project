
# --------------------------------------------------
# SSH access to the public App/Bastion EC2
# Jenkins can override this value during deployment.
# --------------------------------------------------
variable "ssh_allowed_cidr" {
  description = "Trusted CIDR allowed to SSH into the app/bastion EC2"
  type        = string
  default     = "103.203.255.5/32"

  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr))
    error_message = "Provide a valid SSH CIDR."
  }
}

# --------------------------------------------------
# Flask dashboard access
# --------------------------------------------------
variable "app_allowed_cidr" {
  description = "Trusted CIDR allowed to access the Flask dashboard"
  type        = string
  default     = "103.203.255.2/32"

  validation {
    condition     = can(cidrnetmask(var.app_allowed_cidr))
    error_message = "Provide a valid application CIDR."
  }
}

# --------------------------------------------------
# AWS region
# --------------------------------------------------
variable "aws_region" {
  description = "AWS region for the Redis HA infrastructure"
  type        = string
  default     = "ap-south-1"
}

# --------------------------------------------------
# EC2 instance configuration
# --------------------------------------------------
variable "app_instance_type" {
  description = "EC2 instance type for the Flask app and bastion"
  type        = string
  default     = "t2.micro"
}

variable "redis_instance_type" {
  description = "EC2 instance type for each private Redis node"
  type        = string
  default     = "t2.micro"
}

# --------------------------------------------------
# Existing EC2 SSH key pair name
# --------------------------------------------------
variable "key_name" {
  description = "Existing AWS EC2 key pair name"
  type        = string
  default     = "redis-project-key"
}

# --------------------------------------------------
# Availability zones
# Verify availability in your AWS account before apply.
# --------------------------------------------------
variable "public_az" {
  description = "Availability zone for the public app subnet"
  type        = string
  default     = "ap-south-1b"
}

variable "private_az_a" {
  description = "Availability zone for private subnet A"
  type        = string
  default     = "ap-south-1b"
}

variable "private_az_b" {
  description = "Availability zone for private subnet B"
  type        = string
  default     = "ap-south-1c"
}
