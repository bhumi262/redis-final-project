variable "ssh_allowed_cidr" {
  description = "Public IP allowed to access SSH"
  type        = string
  default     = "103.203.255.5/32"

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