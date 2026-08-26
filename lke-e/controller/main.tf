# ──────────────────────────────────────────────────────────────────────────────
# Linode API token Secret
# ──────────────────────────────────────────────────────────────────────────────
# The cloud-firewall-controller reads the "token" key from this Secret to
# authenticate with the Linode API. It manages the Cloud Firewall lifecycle
# (create, update, attach/detach nodes) on behalf of the cluster.

resource "kubernetes_secret" "linode_token" {
  metadata {
    name      = "linode"
    namespace = "kube-system"
  }

  data = {
    token = var.linode_token
  }

  type = "Opaque"
}

# ──────────────────────────────────────────────────────────────────────────────
# cloud-firewall-crd Helm release
# ──────────────────────────────────────────────────────────────────────────────
# Installs the CloudFirewall CRD (networking.linode.com/alpha1v1).
# wait = true ensures the CRD is fully established before the controller
# is installed — prevents "no kind is registered" errors on first apply.

resource "helm_release" "cloud_firewall_crd" {
  name       = "cloud-firewall-crd"
  repository = "https://linode.github.io/cloud-firewall-controller"
  chart      = "cloud-firewall-crd"

  namespace        = "kube-system"
  create_namespace = false

  wait    = true
  timeout = 120
}

# ──────────────────────────────────────────────────────────────────────────────
# cloud-firewall-controller Helm release
# ──────────────────────────────────────────────────────────────────────────────
# Deploys the controller and creates the primary CloudFirewall CR.
#
# defaultRules behaviour (spec.defaultRules = true by default):
#   The controller automatically enforces the full set of rules required for
#   LKE to function — no manual management of the following rules is needed:
#
#     allow-all-icmp              ICMP       0.0.0.0/0, ::/0
#     allow-kubelet-health-checks TCP 10250,10256   192.168.128.0/17
#     allow-lke-wireguard         UDP 51820         192.168.128.0/17
#     allow-cluster-dns-tcp       TCP 53            192.168.128.0/17
#     allow-cluster-dns-udp       UDP 53            192.168.128.0/17
#     allow-calico-bgp            TCP 179           192.168.128.0/17
#     allow-calico-typha          TCP 5473          192.168.128.0/17
#     allow-cluster-nodeports-tcp TCP 30000-32767   192.168.255.0/24
#     allow-cluster-nodeports-udp UDP 30000-32767   192.168.255.0/24
#     allow-cluster-ipencap       IPENCAP           192.168.128.0/17
#
#   Inbound policy : DROP (default deny)
#   Outbound policy: ACCEPT (allow all)
#
# var.additional_inbound_rules are appended after the defaults. By default this
# includes allow-http (TCP 80) and allow-https (TCP 443) from 0.0.0.0/0/::/0.
# Override in terraform.tfvars to customise application-facing ports.
#
# Node autoscaling: the controller watches cluster node events and automatically
# attaches/detaches Linode instances from the firewall as the autoscaler adds
# or removes nodes — no manual firewall updates are ever needed.

resource "helm_release" "cloud_firewall_controller" {
  name       = "cloud-firewall"
  repository = "https://linode.github.io/cloud-firewall-controller"
  chart      = "cloud-firewall-controller"

  namespace        = "kube-system"
  create_namespace = false

  wait    = true
  timeout = 300

  # Build the firewall.inbound values block from var.additional_inbound_rules.
  # An empty list produces an empty firewall block — only LKE defaults apply.
  values = length(var.additional_inbound_rules) > 0 ? [
    yamlencode({
      firewall = {
        inbound = [
          for rule in var.additional_inbound_rules : {
            label       = rule.label
            action      = rule.action
            protocol    = rule.protocol
            ports       = rule.ports
            description = rule.description
            addresses = {
              ipv4 = rule.ipv4_cidrs
              ipv6  = rule.ipv6_cidrs
            }
          }
        ]
      }
    })
  ] : []

  depends_on = [
    helm_release.cloud_firewall_crd,
    kubernetes_secret.linode_token,
  ]
}
