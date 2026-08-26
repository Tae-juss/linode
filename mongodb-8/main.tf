resource "linode_instance" "mongo" {
  count = var.node_count

  label                = "tfansamk-mongo-${count.index + 1}"
  region               = var.region
  type                 = var.instance_type
  image                = var.image
  interface_generation = "legacy_config"
  firewall_id          = linode_firewall.mongo.id

  authorized_keys = [
    var.ssh_public_key
  ]

  tags = [
    "mongodb",
    "mongodb-replica-set"
  ]
  interface {
    purpose   = "vpc"
    subnet_id = var.vpc_subnet_id
    primary   = true

    ipv4 {
      nat_1_1 = "any"
    }
  }
}

locals {
  mongodb_allowed_cidrs = distinct(concat(var.operator_allowed_cidrs, var.vpc_allowed_cidrs))
}

resource "linode_firewall" "mongo" {
  label           = "tfansamk-mongo-firewall"
  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-ssh-operator"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = tostring(var.ssh_port)
    ipv4     = var.operator_allowed_cidrs
  }

  inbound {
    label    = "allow-mongodb"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = tostring(var.mongodb_port)
    ipv4     = local.mongodb_allowed_cidrs
  }
}