# ──────────────────────────────────────────────────────────────────────────────
# Auto-discover the latest LKE Enterprise Kubernetes version
# ──────────────────────────────────────────────────────────────────────────────
# Called at plan time. Override by setting var.k8s_version in your tfvars.

data "http" "lke_enterprise_versions" {
  # This is the tier-specific endpoint (used by linodego's ListLKETierVersions).
  # It returns versions only valid for the enterprise tier — distinct from the
  # generic /v4beta/lke/versions?tier=enterprise which ignores the filter and
  # returns the same standard version list regardless.
  url = "https://api.linode.com/v4beta/lke/tiers/enterprise/versions"
  request_headers = {
    Authorization = "Bearer ${var.linode_token}"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Linode API returned HTTP ${self.status_code} querying LKE Enterprise tier versions. Verify your linode_token is valid and has Kubernetes read scope."
    }
  }
}

locals {
  # Resolve the effective VPC and subnet IDs based on vpc_mode.
  # "none"     → null (no VPC attachment on the cluster)
  # "create"   → IDs of the resources created below
  # "existing" → caller-supplied IDs
  effective_vpc_id = (
    var.vpc_mode == "create" ? linode_vpc.this[0].id :
    var.vpc_mode == "existing" ? var.existing_vpc_id :
    null
  )

  effective_subnet_id = (
    var.vpc_mode == "create" ? linode_vpc_subnet.this[0].id :
    var.vpc_mode == "existing" ? var.existing_subnet_id :
    null
  )

  _versions_raw = jsondecode(data.http.lke_enterprise_versions.response_body)

  # Enterprise version IDs use the full format including v-prefix: vX.Y.Z+lkeN
  # (e.g. "v1.34.6+lke2"). Preserve them exactly as the API returns them.
  _enterprise_versions = [for v in local._versions_raw.data : v.id]

  # Sort alphabetically and pick the last entry to approximate "highest k8s version".
  # For vMAJOR.MINOR.PATCH+lkeN strings, alphabetical sort reliably selects the
  # highest minor/patch for typical version ranges.
  # var.k8s_version is accepted as-is (no prefix stripping — enterprise IDs include "v").
  # try() prevents coalesce() from throwing when both args are null — the null
  # result is then caught by the cluster precondition with a clear error message.
  _sorted_versions = sort(local._enterprise_versions)
  effective_k8s_version = try(
    coalesce(
      var.k8s_version,
      length(local._sorted_versions) > 0 ? local._sorted_versions[length(local._sorted_versions) - 1] : null
    ),
    null
  )
}

# ──────────────────────────────────────────────────────────────────────────────
# VPC + Subnet (only when vpc_mode = "create")
# ──────────────────────────────────────────────────────────────────────────────

resource "linode_vpc" "this" {
  count = var.vpc_mode == "create" ? 1 : 0

  label       = var.vpc_label
  region      = var.region
  description = "VPC for LKE Enterprise cluster: ${var.cluster_label}"
}

resource "linode_vpc_subnet" "this" {
  count = var.vpc_mode == "create" ? 1 : 0

  vpc_id = linode_vpc.this[0].id
  label  = var.subnet_label
  ipv4   = var.subnet_cidr
}

# ──────────────────────────────────────────────────────────────────────────────
# LKE Enterprise cluster
# ──────────────────────────────────────────────────────────────────────────────

resource "linode_lke_cluster" "this" {
  label       = var.cluster_label
  region      = var.region
  k8s_version = local.effective_k8s_version

  lifecycle {
    precondition {
      condition     = local.effective_k8s_version != null
      error_message = <<-EOT
        No LKE Enterprise k8s versions were found. The versions API returned an empty list.
        Raw response: ${data.http.lke_enterprise_versions.response_body}
        Set k8s_version explicitly in terraform.tfvars to bypass auto-discovery.
      EOT
    }

    precondition {
      condition = alltrue([
        for p in var.node_pools : startswith(p.type, "g7-premium")
      ])
      error_message = <<-EOT
        LKE Enterprise clusters require g7-premium-* node types.
        One or more pools are using a non-premium type:
          ${jsonencode([for p in var.node_pools : p.type if !startswith(p.type, "g7-premium")])}
        Change these to a g7-premium-* type (e.g. g7-premium-2, g7-premium-4, g7-premium-8).
        Note: the Linode API may report this as "k8s_version is not valid" — that error
        is misleading; the actual cause is an invalid node type for the enterprise tier.
      EOT
    }
  }
  tags        = var.tags
  tier        = "enterprise"

  # VPC attachment — null values are silently ignored by the provider when the
  # field is optional, so this is safe for all three vpc_mode values.
  vpc_id    = local.effective_vpc_id
  subnet_id = local.effective_subnet_id

  # ── Control plane ──────────────────────────────────────────────────────────

  control_plane {
    high_availability = var.enable_ha_control_plane

    # LKE Enterprise requires ACL to always be enabled — the API rejects any
    # request that omits or disables it. We always emit the block with enabled=true.
    # When control_plane_acl_ipv4/ipv6 use the defaults ("0.0.0.0/0" / "::/0")
    # the API server is reachable from anywhere. Restrict those lists to lock
    # down access to specific CIDR ranges.
    acl {
      enabled = true
      addresses {
        ipv4 = var.control_plane_acl_ipv4
        ipv6  = var.control_plane_acl_ipv6
      }
    }
  }

  # ── Node pools ─────────────────────────────────────────────────────────────
  # Each pool gets a cluster autoscaler. The initial node count is set to
  # pool.min so the autoscaler has full control from the moment the cluster
  # is ready.

  dynamic "pool" {
    for_each = var.node_pools
    content {
      type = pool.value.type

      autoscaler {
        min = pool.value.min
        max = pool.value.max
      }

      labels          = pool.value.labels
      disk_encryption = pool.value.disk_encryption

      dynamic "taint" {
        for_each = pool.value.taints
        content {
          key    = taint.value.key
          value  = taint.value.value
          effect = taint.value.effect
        }
      }
    }
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Write kubeconfig to disk
# ──────────────────────────────────────────────────────────────────────────────
# The controller module reads this file to connect to the cluster.
# Mode 0600 ensures only the current user can read it.
# Add .kubeconfig to your .gitignore — never commit credentials.

resource "local_sensitive_file" "kubeconfig" {
  content         = base64decode(linode_lke_cluster.this.kubeconfig)
  filename        = var.kubeconfig_output_path
  file_permission = "0600"
}
