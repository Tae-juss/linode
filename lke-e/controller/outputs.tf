output "cloud_firewall_controller_status" {
  description = "Helm release status of cloud-firewall-controller (expected: 'deployed')."
  value       = helm_release.cloud_firewall_controller.status
}

output "cloud_firewall_controller_chart_version" {
  description = "Chart version of the deployed cloud-firewall-controller release."
  value       = helm_release.cloud_firewall_controller.metadata[0].version
}

output "cloud_firewall_crd_chart_version" {
  description = "Chart version of the deployed cloud-firewall-crd release."
  value       = helm_release.cloud_firewall_crd.metadata[0].version
}
