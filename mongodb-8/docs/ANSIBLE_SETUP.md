# Ansible Setup Guide

This document covers MongoDB installation and replica-set configuration using Ansible.

## 1. Prerequisites

- Ansible installed locally
- SSH access to all MongoDB nodes as root
- Nodes already provisioned by Terraform

## 2. Ansible Layout

- ansible/ansible.cfg
- ansible/inventory.ini
- ansible/playbook.yml
- ansible/templates/mongod.conf.j2
- ansible/scripts/

## 3. Inventory

Update ansible/inventory.ini with current public and private IPs:

```ini
[mongo]
mongo1 ansible_host=PUBLIC_IP_1 mongo_private_ip=PRIVATE_IP_1
mongo2 ansible_host=PUBLIC_IP_2 mongo_private_ip=PRIVATE_IP_2
mongo3 ansible_host=PUBLIC_IP_3 mongo_private_ip=PRIVATE_IP_3

[mongo:vars]
ansible_user=root
ansible_port=22
ansible_connection=ssh
```

The private IPs are used for replica-set member hostnames.

## 4. Admin Password Secret

Create local password file once:

```bash
cd ansible
mkdir -p .secrets
openssl rand -base64 32 > .secrets/mongodb_admin_password.txt
chmod 600 .secrets/mongodb_admin_password.txt
```

## 5. Run Playbook

```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml
```

## 6. What the Playbook Configures

- Installs MongoDB 8.0 from official MongoDB apt repo
- Applies mongod.conf from template
- Enables and starts mongod service
- Verifies nofile/connection prerequisites for 5000+ connection target
- Initializes replica set rs0 (idempotent)
- Detects current PRIMARY dynamically
- Creates admin user on the PRIMARY

## 7. Important Authentication Constraint

Current configuration keeps authorization disabled.

Reason:
- In MongoDB replica sets, enabling authorization requires internal member auth (keyFile or x509).
- Enabling authorization without keyFile/x509 causes mongod startup failure.

If you later want full authentication enforcement:
1. Configure keyFile (or x509) for internal auth.
2. Then enable authorization in mongod config.

## 8. Idempotency

You can rerun the playbook safely after:
- node restarts
- package updates
- scaling events (after inventory update)

## 9. Quick Health Checks

```bash
# Check service state
for ip in PUBLIC_IP_1 PUBLIC_IP_2 PUBLIC_IP_3; do
  ssh root@$ip 'systemctl is-active mongod'
done

# Check replica set roles
ssh root@PRIMARY_PUBLIC_IP 'mongosh --quiet --eval "printjson(db.hello())"'
```
