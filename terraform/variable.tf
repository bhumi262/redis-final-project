
variable "ssh_allowed_cidr" {
  description = "Trusted public IP CIDR allowed to SSH, preferably Jenkins egress IP"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr))
    error_message = "Provide a valid CIDR, for example 203.0.113.10/32."
  }
}

variable "app_allowed_cidr" {
  description = "Trusted client or reverse proxy CIDR allowed to access Flask"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.app_allowed_cidr))
    error_message = "Provide a valid CIDR, for example 203.0.113.10/32."
  }
}
