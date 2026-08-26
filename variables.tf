variable "linode_token" {
  description = "Linode API token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Linode region"
  type        = string
  default     = "in-bom-2"
}

variable "node_count" {
  description = "Number of MongoDB nodes (3 for test, 5 for production)"
  type        = number
  default     = 3

  validation {
    condition     = contains([3, 5], var.node_count)
    error_message = "node_count must be either 3 (test) or 5 (production)."
  }
}

variable "instance_type" {
  description = "Linode instance type for MongoDB nodes"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key used to access the MongoDB nodes"
  type        = string
}

variable "vpc_subnet_id" {
  description = "Existing Linode VPC subnet ID"
  type        = number
}

variable "operator_allowed_cidrs" {
  description = "Public CIDRs that can access MongoDB and SSH"
  type        = list(string)

  validation {
    condition     = length(var.operator_allowed_cidrs) > 0
    error_message = "operator_allowed_cidrs must include at least one CIDR (for example, your public IP/32)."
  }
}

variable "vpc_allowed_cidrs" {
  description = "VPC CIDRs allowed for internal MongoDB replica set traffic"
  type        = list(string)
  default     = []
}

variable "ssh_port" {
  description = "SSH port"
  type        = number
  default     = 22
}

variable "mongodb_port" {
  description = "MongoDB port"
  type        = number
  default     = 27017
}

variable "image" {
  description = "OS image"
  type        = string
  default     = "linode/ubuntu24.04"
}