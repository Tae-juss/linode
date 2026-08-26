terraform {
  required_version = ">= 1.5.0"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# api_version = "v4beta" is required for:
#   - tier = "enterprise"
#   - vpc_id / subnet_id cluster attachment
#   - pool.k8s_version (per-pool version for Enterprise rolling upgrades)
provider "linode" {
  token       = var.linode_token
  api_version = "v4beta"
}
