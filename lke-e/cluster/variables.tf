# ──────────────────────────────────────────────────────────────────────────────
# Authentication
# ──────────────────────────────────────────────────────────────────────────────

variable "linode_token" {
  description = <<-EOT
    Linode Personal Access Token with read/write scopes for:
    Linodes, Kubernetes, Firewalls, VPCs, NodeBalancers.
    Generate one at: https://cloud.linode.com/profile/tokens
  EOT
  type        = string
  sensitive   = true
}

# ──────────────────────────────────────────────────────────────────────────────
# Cluster identity
# ──────────────────────────────────────────────────────────────────────────────

variable "cluster_label" {
  description = "Unique label for the LKE Enterprise cluster."
  type        = string
}

variable "region" {
  description = <<-EOT
    Linode region slug where the cluster is provisioned.
    LKE Enterprise has limited regional availability. Confirmed regions (mid-2026):
      us-lax, us-east, eu-west, ap-southeast
    If the plan fails with "k8s_version is not valid" despite a correct version,
    the most likely cause is that the chosen region does not yet support LKE Enterprise.
  EOT
  type = string
}

variable "k8s_version" {
  description = <<-EOT
    Kubernetes version to use for the LKE Enterprise cluster.
    Leave null (the default) to automatically select the latest version
    offered by Linode — the available versions are fetched from the API
    at plan time so you never need to hard-code a value.

    Set explicitly only when you need to pin to a specific release, e.g.:
      k8s_version = "v1.32.3+lke1"

    Browse available versions:
      curl -s -H "Authorization: Bearer $LINODE_TOKEN" \
           "https://api.linode.com/v4beta/lke/versions?tier=enterprise" \
        | jq -r '.data[].id'
  EOT
  type    = string
  default = null
}

variable "tags" {
  description = "List of tags applied to the cluster resource."
  type        = list(string)
  default     = []
}

# ──────────────────────────────────────────────────────────────────────────────
# Node pools
# ──────────────────────────────────────────────────────────────────────────────

variable "node_pools" {
  description = <<-EOT
    List of node pool configurations. Each pool gets a cluster autoscaler with
    min/max bounds. Enterprise clusters require g7-premium-* instance types.

    Optional per-pool fields:
      labels          - k8s labels applied to all nodes (map of strings)
      disk_encryption - "enabled" (default) or "disabled". Changing forces pool replacement.
      taints          - list of {key, value, effect} objects. effect must be one of:
                        NoSchedule | PreferNoSchedule | NoExecute
  EOT
  type = list(object({
    type            = string
    min             = number
    max             = number
    labels          = optional(map(string), {})
    disk_encryption = optional(string, "enabled")
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))

  default = [
    {
      type = "g7-premium-2"
      min  = 3
      max  = 10
    }
  ]

  validation {
    condition     = length(var.node_pools) >= 1
    error_message = "At least one node pool must be defined."
  }

  validation {
    condition = alltrue([
      for p in var.node_pools : p.min >= 1
    ])
    error_message = "Each pool's autoscaler min must be at least 1."
  }

  validation {
    condition = alltrue([
      for p in var.node_pools : p.max >= p.min
    ])
    error_message = "Each pool's autoscaler max must be >= min."
  }

  validation {
    condition = alltrue([
      for p in var.node_pools :
      contains(["enabled", "disabled"], p.disk_encryption)
    ])
    error_message = "disk_encryption must be 'enabled' or 'disabled'."
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Control plane
# ──────────────────────────────────────────────────────────────────────────────

variable "enable_ha_control_plane" {
  description = <<-EOT
    Enable High Availability control plane (multiple etcd replicas across zones).
    WARNING: This is IRREVERSIBLE once enabled — the cluster cannot be downgraded
    to a non-HA control plane.
    Recommended: true for production Enterprise clusters.
  EOT
  type    = bool
  default = true
}

variable "enable_control_plane_acl" {
  description = <<-EOT
    Unused for LKE Enterprise — enterprise clusters always require ACL to be
    enabled. The API will reject any request that tries to disable it.
    This variable is retained for compatibility but has no effect; the ACL
    block is always emitted with enabled=true. Control access by setting
    control_plane_acl_ipv4 / control_plane_acl_ipv6 (default: allow all).
  EOT
  type    = bool
  default = true
}

variable "control_plane_acl_ipv4" {
  description = "IPv4 CIDRs allowed to reach the Kubernetes API server. Only used when enable_control_plane_acl = true."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "control_plane_acl_ipv6" {
  description = "IPv6 CIDRs allowed to reach the Kubernetes API server. Only used when enable_control_plane_acl = true."
  type        = list(string)
  default     = ["::/0"]
}

# ──────────────────────────────────────────────────────────────────────────────
# VPC attachment
# ──────────────────────────────────────────────────────────────────────────────

variable "vpc_mode" {
  description = <<-EOT
    VPC attachment mode for cluster nodes:
      "none"     - No VPC attachment (default public networking)
      "create"   - Provision a new VPC and subnet in this automation
      "existing" - Attach to a pre-existing VPC subnet (supply existing_vpc_id
                   and existing_subnet_id)
  EOT
  type    = string
  default = "none"

  validation {
    condition     = contains(["none", "create", "existing"], var.vpc_mode)
    error_message = "vpc_mode must be one of: none, create, existing."
  }
}

variable "vpc_label" {
  description = "Label for the new VPC. Required when vpc_mode = 'create'."
  type        = string
  default     = null
}

variable "subnet_label" {
  description = "Label for the new VPC subnet. Used when vpc_mode = 'create'."
  type        = string
  default     = "lke-subnet"
}

variable "subnet_cidr" {
  description = "IPv4 CIDR block for the new VPC subnet. Used when vpc_mode = 'create'."
  type        = string
  default     = "10.0.0.0/24"
}

variable "existing_vpc_id" {
  description = "Numeric ID of an existing Linode VPC. Required when vpc_mode = 'existing'."
  type        = number
  default     = null
}

variable "existing_subnet_id" {
  description = "Numeric ID of an existing VPC subnet. Required when vpc_mode = 'existing'."
  type        = number
  default     = null
}

# ──────────────────────────────────────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────────────────────────────────────

variable "kubeconfig_output_path" {
  description = <<-EOT
    Local filesystem path where the cluster kubeconfig is written after creation.
    The controller module reads this file. Relative paths are resolved from the
    cluster/ module directory.
    Default: ../.kubeconfig  (i.e. lke-e/.kubeconfig)
  EOT
  type    = string
  default = "../.kubeconfig"
}
