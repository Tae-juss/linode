output "mongo_instances" {
  description = "MongoDB Linode instance details"

  value = {
    for i, instance in linode_instance.mongo :
    instance.label => {
      id         = instance.id
      public_ip  = instance.ip_address
      private_ip = instance.interface[0].ipv4[0].vpc
    }
  }
}

output "mongo_public_ips" {
  description = "Public IPv4 addresses"

  value = {
    for instance in linode_instance.mongo :
    instance.label => instance.ip_address
  }
}

output "mongo_cluster_shape" {
  description = "Deployed cluster size and instance class"

  value = {
    node_count    = var.node_count
    instance_type = var.instance_type
  }
}

output "mongo_firewall_id" {
  description = "Linode firewall ID protecting MongoDB nodes"
  value       = linode_firewall.mongo.id
}