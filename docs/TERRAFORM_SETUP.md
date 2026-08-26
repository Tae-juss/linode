# Terraform Setup Guide

This document explains the full Terraform provisioning flow for the MongoDB test cluster in this repository.

## 1. Prerequisites

- Terraform 1.6+
- Linode account and API token with required permissions
- Existing VPC subnet ID in your target region
- SSH public key for root access

## 2. Repository Files

- main.tf: Linode instance and firewall resources
- variables.tf: input variables and validation
- terraform.tfvars: environment-specific values
- outputs.tf: instance and firewall outputs
- versions.tf: Terraform and provider constraints

## 3. Configure Variables

Edit terraform.tfvars:

```hcl
region = "YOUR_REGION"
instance_type = "g6-dedicated-8"
node_count = 3
vpc_subnet_id = YOUR_VPC_SUBNET_ID

operator_allowed_cidrs = [
  "YOUR_PUBLIC_IP/32"
]

vpc_allowed_cidrs = [
  "10.0.0.0/8"
]

ssh_public_key = "ssh-rsa ..."
```

Notes:
- node_count: use 3 for test and 5 for production.
- operator_allowed_cidrs must include your current public IP (/32) so SSH access works.
- If your IP changes, update operator_allowed_cidrs and re-apply.

## 4. Set Linode Token

Use an environment variable to avoid interactive prompts:

```bash
export TF_VAR_linode_token="YOUR_LINODE_TOKEN"
```

## 5. Provision Infrastructure

```bash
terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

## 6. What Gets Created

- 3 Linode instances (or 5 if node_count=5)
- VPC interface with 1:1 NAT on each instance
- Firewall with inbound allowlist for:
  - SSH (22) from operator_allowed_cidrs
  - MongoDB (27017) from operator_allowed_cidrs + vpc_allowed_cidrs

## 7. Scale from 3 to 5 Nodes

1. Update node_count in terraform.tfvars to 5.
2. Run:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

## 8. Outputs

View provisioned details:

```bash
terraform output
```

Useful outputs:
- mongo_instances
- mongo_public_ips
- mongo_cluster_shape
- mongo_firewall_id

## 9. Common Troubleshooting

### SSH suddenly fails
- Your public IP likely changed.
- Update operator_allowed_cidrs in terraform.tfvars.
- Re-apply firewall:

```bash
terraform apply -target=linode_firewall.mongo
```

### Linode interface errors
- This repository uses instance VPC interface + NAT 1:1 in main.tf.
- Keep current interface structure unless you are intentionally migrating models.
