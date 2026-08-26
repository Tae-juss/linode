output "selected_k8s_version" {
  description = "The Kubernetes version used for this cluster (auto-discovered or explicitly set)."
  value       = local.effective_k8s_version
}

output "available_enterprise_versions" {
  description = "LKE versions returned by the ?tier=enterprise endpoint (newest first)."
  value       = local._enterprise_versions
}

output "cluster_id" {
  description = "Numeric ID of the LKE Enterprise cluster."
  value       = linode_lke_cluster.this.id
}

output "api_endpoints" {
  description = "List of Kubernetes API server endpoints for this cluster."
  value       = linode_lke_cluster.this.api_endpoints
}

output "kubeconfig" {
  description = "Decoded kubeconfig for the cluster. Treat as a secret."
  value       = base64decode(linode_lke_cluster.this.kubeconfig)
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Absolute path to the kubeconfig file written by this module. Pass this to the controller module via -var=kubeconfig_path."
  value       = abspath(local_sensitive_file.kubeconfig.filename)
}

output "vpc_id" {
  description = "ID of the attached VPC. Null when vpc_mode is 'none'."
  value       = local.effective_vpc_id
}

output "subnet_id" {
  description = "ID of the attached VPC subnet. Null when vpc_mode is 'none'."
  value       = local.effective_subnet_id
}

output "cluster_status" {
  description = "Current provisioning status of the cluster."
  value       = linode_lke_cluster.this.status
}
