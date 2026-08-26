# LKE Enterprise Terraform Automation

Terraform automation that provisions a production-ready **Linode Kubernetes Engine (LKE) Enterprise** cluster and installs the [cloud-firewall-controller](https://github.com/linode/cloud-firewall-controller) on it — all without touching the Linode Cloud Manager UI.

Everything is managed via Terraform: cluster creation, autoscaling, node pool configuration, VPC attachment, control-plane ACL, firewall rules, and the firewall controller lifecycle.

---

## Architecture

The automation is split into two independent Terraform root modules to avoid the provider chicken-and-egg problem (Helm and Kubernetes providers need a live kubeconfig at plan time):

```
lke-e/
├── cluster/          # Phase 1 — LKE Enterprise cluster + optional VPC
├── controller/       # Phase 2 — cloud-firewall-controller (Helm)
├── deploy.sh         # Orchestration script
└── .gitignore
```

`deploy.sh` wires the two phases together: it runs Phase 1, captures the written kubeconfig path from Terraform outputs, then passes it to Phase 2.

### Firewall model

The `cloud-firewall-controller` creates and manages a Linode Cloud Firewall named `lke-<cluster-id>`. It automatically attaches every node in the cluster — including nodes added by the autoscaler — to that firewall and enforces the rule set defined in Terraform.

Default inbound policy is **DROP**; default outbound policy is **ACCEPT**.

The controller's built-in `defaultRules=true` automatically enforces all rules required for the cluster to function:

| Rule | Protocol | Ports | Source |
|---|---|---|---|
| ICMP | ICMP | — | `0.0.0.0/0`, `::/0` |
| Kubelet API + health check | TCP | `10250`, `10256` | `192.168.128.0/17` |
| WireGuard node overlay | UDP | `51820` | `192.168.128.0/17` |
| Cluster DNS | TCP + UDP | `53` | `192.168.128.0/17` |
| Calico BGP | TCP | `179` | `192.168.128.0/17` |
| Calico Typha | TCP | `5473` | `192.168.128.0/17` |
| NodePort services | TCP + UDP | `30000–32767` | `192.168.255.0/24` |
| IP-in-IP (Calico) | IPENCAP | — | `192.168.128.0/17` |

Application-facing ports (e.g. `80`, `443`) are added on top via the `additional_inbound_rules` variable in the `controller` module.

---

## Prerequisites

| Tool | Version |
|---|---|
| Terraform | >= 1.5.0 |
| Helm | >= 3.x (used by the Helm provider, not needed locally) |
| curl / jq | For version discovery (optional) |

A Linode Personal Access Token with the following scopes:
- **Linodes** — Read/Write
- **Kubernetes** — Read/Write
- **Firewalls** — Read/Write
- **VPCs** — Read/Write *(only required when `vpc_mode = "create"`)*

Your account must have **LKE Enterprise** access. Contact [Linode support](https://www.linode.com/support/) if the enterprise tier is not available.

---

## Quick Start

### 1 — Clone and configure

```bash
git clone <repo-url> lke-e
cd lke-e

# Cluster configuration
cp cluster/terraform.tfvars.example cluster/terraform.tfvars
# Fill in: linode_token, cluster_label, region

# Firewall controller configuration
cp controller/terraform.tfvars.example controller/terraform.tfvars
# Fill in: linode_token
```

> **Security tip:** Instead of storing the token in a file, export it as an environment variable — Terraform picks it up automatically:
> ```bash
> export TF_VAR_linode_token="your-token-here"
> ```

### 2 — Verify enterprise version availability

```bash
curl -s -H "Authorization: Bearer $TF_VAR_linode_token" \
     "https://api.linode.com/v4beta/lke/tiers/enterprise/versions" \
  | jq -r '.data[].id'
```

The automation auto-selects the highest available version. You can pin a specific one via `k8s_version` in `cluster/terraform.tfvars`.

### 3 — Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

The script runs both phases sequentially and prints next steps when complete.

---

## Configuration Reference

### `cluster/terraform.tfvars`

| Variable | Required | Default | Description |
|---|---|---|---|
| `linode_token` | ✓ | — | Linode API token |
| `cluster_label` | ✓ | — | Unique cluster name |
| `region` | ✓ | — | Linode region slug (e.g. `us-lax`) |
| `k8s_version` | | auto-detected | Enterprise version ID (e.g. `v1.34.6+lke2`). Leave null to auto-select. |
| `tags` | | `[]` | Tags applied to the cluster |
| `node_pools` | | `[{type=g7-premium-2, min=3, max=10}]` | List of node pool configs |
| `enable_ha_control_plane` | | `true` | HA control plane — **irreversible** once enabled |
| `control_plane_acl_ipv4` | | `["0.0.0.0/0"]` | IPv4 CIDRs allowed to reach the API server |
| `control_plane_acl_ipv6` | | `["::/0"]` | IPv6 CIDRs allowed to reach the API server |
| `vpc_mode` | | `"none"` | `"none"` / `"create"` / `"existing"` |
| `vpc_label` | | `null` | New VPC label (required when `vpc_mode = "create"`) |
| `subnet_cidr` | | `"10.0.0.0/24"` | Subnet CIDR (used when `vpc_mode = "create"`) |
| `existing_vpc_id` | | `null` | Existing VPC ID (required when `vpc_mode = "existing"`) |
| `existing_subnet_id` | | `null` | Existing subnet ID (required when `vpc_mode = "existing"`) |

**Node pool object schema:**

```hcl
node_pools = [
  {
    type            = "g7-premium-2"   # Required — must be g7-premium-*
    min             = 3                # Autoscaler lower bound
    max             = 10               # Autoscaler upper bound
    labels          = {}               # Optional k8s node labels
    disk_encryption = "enabled"        # "enabled" | "disabled" (changing forces replacement)
    taints          = []               # Optional [{key, value, effect}]
  }
]
```

### `controller/terraform.tfvars`

| Variable | Required | Default | Description |
|---|---|---|---|
| `linode_token` | ✓ | — | Linode API token (same as cluster module) |
| `additional_inbound_rules` | | HTTP + HTTPS | Firewall rules appended after the LKE defaults |

**Firewall rule object schema:**

```hcl
additional_inbound_rules = [
  {
    label       = "allow-https"         # Unique identifier
    action      = "ACCEPT"              # "ACCEPT" | "DROP"
    protocol    = "TCP"                 # "TCP" | "UDP" | "ICMP" | "IPENCAP"
    ports       = "443"                 # Port or range, e.g. "8000-8080"
    description = "HTTPS from internet" # Optional
    ipv4_cidrs  = ["0.0.0.0/0"]
    ipv6_cidrs  = ["::/0"]
  }
]
```

---

## Updating via Terraform

All changes are applied without touching the UI.

### Change firewall rules

Edit `additional_inbound_rules` in `controller/terraform.tfvars`, then:

```bash
terraform -chdir=controller apply
```

The controller automatically syncs the new rule set to the Linode Cloud Firewall.

### Change autoscaler bounds

Edit `node_pools[*].min` / `node_pools[*].max` in `cluster/terraform.tfvars`, then:

```bash
terraform -chdir=cluster apply
```

### Add a node pool

Append a new entry to `node_pools` and run `terraform -chdir=cluster apply`.

### Lock down the API server

Set specific CIDR ranges in `cluster/terraform.tfvars`:

```hcl
control_plane_acl_ipv4 = ["203.0.113.0/24"]   # your office/VPN CIDR
control_plane_acl_ipv6 = []
```

Then run `terraform -chdir=cluster apply`.

> **Note:** LKE Enterprise always requires ACL to be enabled. The default addresses (`0.0.0.0/0` / `::/0`) allow access from anywhere — they are not a restriction.

---

## Outputs

After `./deploy.sh` completes, the following Terraform outputs are available:

```bash
# Cluster module
terraform -chdir=cluster output cluster_id
terraform -chdir=cluster output api_endpoints
terraform -chdir=cluster output selected_k8s_version
terraform -chdir=cluster output available_enterprise_versions

# Controller module
terraform -chdir=controller output cloud_firewall_controller_status
terraform -chdir=controller output cloud_firewall_controller_chart_version
```

The kubeconfig is written to `.kubeconfig` in the repo root:

```bash
export KUBECONFIG="$(terraform -chdir=cluster output -raw kubeconfig_path)"
kubectl get nodes
kubectl -n kube-system get cloudfirewalls
```

---

## Tearing Down

```bash
./deploy.sh --destroy
```

The script destroys the firewall controller first, then the cluster and VPC (if one was created).

---

## LKE Enterprise Specifics

| Requirement | Detail |
|---|---|
| Node types | Must be `g7-premium-*` |
| Kubernetes version format | `vX.Y.Z+lkeN` (e.g. `v1.34.6+lke2`) — different from standard LKE |
| API version | Requires `v4beta` — set automatically by the provider config |
| Control plane ACL | Always enabled; cannot be disabled on enterprise clusters |
| High availability | Enabled by default — **irreversible** once set to `true` |
| Version discovery endpoint | `/v4beta/lke/tiers/enterprise/versions` — different from `/v4beta/lke/versions?tier=enterprise` |

---

## Security Notes

- `terraform.tfvars` files contain your API token and are excluded from git via `.gitignore`. **Never commit them.**
- `.kubeconfig` is also excluded from git.
- Use `TF_VAR_linode_token` environment variable as an alternative to storing the token in a file.
- The Linode API token for the firewall controller is stored in a Kubernetes Secret (`kube-system/linode`). Restrict access to that namespace appropriately.

---

## License

See [LICENSE](LICENSE) if present, or contact the repository owner.
