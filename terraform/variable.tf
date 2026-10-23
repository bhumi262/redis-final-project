variable "ssh_allowed_cidr" {
  description = "Trusted public IP allowed to SSH"
  type        = string
  default     = "103.203.255.2/32"

  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr))
    error_message = "Provide a valid CIDR."
  }
}

variable "app_allowed_cidr" {
  description = "Trusted client CIDR for the application"
  type        = string
  default     = "103.203.255.2/32"

  validation {
    condition     = can(cidrnetmask(var.app_allowed_cidr))
    error_message = "Provide a valid CIDR."
  }
}