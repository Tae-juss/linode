# ──────────────────────────────────────────────────────────────────────────────
# Connection
# ──────────────────────────────────────────────────────────────────────────────

variable "kubeconfig_path" {
  description = <<-EOT
    Absolute path to the kubeconfig file for the LKE cluster.
    Written by the cluster module and captured by deploy.sh via:
      terraform -chdir=cluster/ output -raw kubeconfig_path
    You can also set this explicitly when running this module standalone.
  EOT
  type = string
}

# ──────────────────────────────────────────────────────────────────────────────
# Authentication
# ──────────────────────────────────────────────────────────────────────────────

variable "linode_token" {
  description = <<-EOT
    Linode Personal Access Token. The cloud-firewall-controller reads this from
    a Kubernetes Secret (name: "linode", namespace: "kube-system") to
    authenticate with the Linode API for firewall management.
    Must have: Linodes (read), Firewalls (read/write).
  EOT
  type      = string
  sensitive = true
}

# ──────────────────────────────────────────────────────────────────────────────
# Firewall rules
# ──────────────────────────────────────────────────────────────────────────────

variable "additional_inbound_rules" {
  description = <<-EOT
    Additional inbound firewall rules appended AFTER the LKE default ruleset.

    The cloud-firewall-controller's defaultRules=true automatically enforces
    all rules required for LKE to function:
      • ICMP         — all sources
      • TCP 10250    — kubelet API          (192.168.128.0/17)
      • TCP 10256    — kube-proxy health    (192.168.128.0/17)
      • UDP 51820    — WireGuard overlay    (192.168.128.0/17)
      • TCP/UDP 53   — cluster DNS          (192.168.128.0/17)
      • TCP 179      — Calico BGP           (192.168.128.0/17)
      • TCP 5473     — Calico Typha         (192.168.128.0/17)
      • TCP/UDP 30000–32767 — NodePorts     (192.168.255.0/24)
      • IPENCAP      — IP-in-IP (Calico)    (192.168.128.0/17)

    Use this variable ONLY for application-facing traffic (e.g. 80/443 for
    ingress). Inbound policy is DROP by default; outbound is ACCEPT.

    Rule fields:
      label       - unique identifier for this rule (required)
      action      - "ACCEPT" or "DROP" (required)
      protocol    - "TCP", "UDP", "ICMP", or "IPENCAP" (required)
      ports       - port or range, e.g. "443" or "8000-8080" (optional for ICMP/IPENCAP)
      description - human-readable note (optional)
      ipv4_cidrs  - list of IPv4 CIDRs (default: ["0.0.0.0/0"])
      ipv6_cidrs  - list of IPv6 CIDRs (default: ["::/0"])
  EOT
  type = list(object({
    label       = string
    action      = string
    protocol    = string
    ports       = optional(string, "")
    description = optional(string, "")
    ipv4_cidrs  = optional(list(string), ["0.0.0.0/0"])
    ipv6_cidrs  = optional(list(string), ["::/0"])
  }))

  default = [
    {
      label       = "allow-http"
      action      = "ACCEPT"
      protocol    = "TCP"
      ports       = "80"
      description = "Allow HTTP traffic from the internet"
      ipv4_cidrs  = ["0.0.0.0/0"]
      ipv6_cidrs  = ["::/0"]
    },
    {
      label       = "allow-https"
      action      = "ACCEPT"
      protocol    = "TCP"
      ports       = "443"
      description = "Allow HTTPS traffic from the internet"
      ipv4_cidrs  = ["0.0.0.0/0"]
      ipv6_cidrs  = ["::/0"]
    }
  ]

  validation {
    condition = alltrue([
      for rule in var.additional_inbound_rules :
      contains(["ACCEPT", "DROP"], rule.action)
    ])
    error_message = "Each rule's action must be 'ACCEPT' or 'DROP'."
  }

  validation {
    condition = alltrue([
      for rule in var.additional_inbound_rules :
      contains(["TCP", "UDP", "ICMP", "IPENCAP"], rule.protocol)
    ])
    error_message = "Each rule's protocol must be one of: TCP, UDP, ICMP, IPENCAP."
  }

  validation {
    condition = alltrue([
      for rule in var.additional_inbound_rules :
      length(rule.label) > 0
    ])
    error_message = "Each rule must have a non-empty label."
  }
}
