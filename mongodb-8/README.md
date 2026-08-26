# MongoDB Cluster on Linode (Terraform + Ansible)

Repository to provision and configure a MongoDB replica set on Linode.

## What This Repo Provides

- Terraform provisioning for Linode instances + firewall
- Ansible automation for MongoDB installation and replica-set setup
- Data seeding and read-load test scripts (including 5K read test via replica-set URI)

## Repository Structure

- main.tf, variables.tf, outputs.tf, versions.tf
- terraform.tfvars.example (sanitized template values)
- ansible/
  - inventory.ini (template placeholders)
  - playbook.yml
  - templates/mongod.conf.j2
  - scripts/
- docs/
  - TERRAFORM_SETUP.md
  - ANSIBLE_SETUP.md
  - TESTING_GUIDE.md

## Quick Start

1. Follow [docs/TERRAFORM_SETUP.md](docs/TERRAFORM_SETUP.md).
2. Follow [docs/ANSIBLE_SETUP.md](docs/ANSIBLE_SETUP.md).
3. Follow [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md).

## Security Notes

- No live infrastructure state is included.
- `.gitignore` excludes Terraform state/plan files and local secrets.
- Replace all placeholder values before deployment:
  - terraform.tfvars.example (copy to terraform.tfvars locally)
  - ansible/inventory.ini

## Important MongoDB Auth Constraint

MongoDB replica sets require internal member auth (keyFile or x509) before enabling authorization.
This repo currently creates an admin user while keeping authorization disabled unless internal auth is configured.
