#!/usr/bin/env bash
# deploy.sh — two-phase Terraform orchestration for LKE Enterprise
#             + cloud-firewall-controller
#
# Phase 1: provisions the LKE Enterprise cluster (and optional VPC).
#          Writes the cluster kubeconfig to .kubeconfig at the repo root.
# Phase 2: installs the cloud-firewall-controller Helm chart onto the cluster.
#
# Usage:
#   ./deploy.sh [--destroy]
#
# Options:
#   --destroy   Tear down all resources in reverse order (controller first,
#               then cluster). Prompts for confirmation.
#
# Prerequisites:
#   - terraform >= 1.5.0 on PATH
#   - cluster/terraform.tfvars   (copy from cluster/terraform.tfvars.example)
#   - controller/terraform.tfvars (copy from controller/terraform.tfvars.example)
#
# Tip: export TF_VAR_linode_token="..." in your shell to avoid storing the
# token in tfvars files. Both modules will pick it up automatically.

set -euo pipefail

# ─── Resolve script directory ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Parse arguments ──────────────────────────────────────────────────────────
DESTROY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destroy)
      DESTROY=true
      shift
      ;;
    -h|--help)
      sed -n '2,/^set /p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--destroy]" >&2
      exit 1
      ;;
  esac
done

# ─── Colour helpers ───────────────────────────────────────────────────────────
_tput() { command -v tput &>/dev/null && tput "$@" 2>/dev/null || true; }
BOLD="$(_tput bold)"
GREEN="$(_tput setaf 2)"
YELLOW="$(_tput setaf 3)"
CYAN="$(_tput setaf 6)"
RED="$(_tput setaf 1)"
RESET="$(_tput sgr0)"

info()    { printf "%s==>%s  %s\n"    "${CYAN}"   "${RESET}" "$*"; }
success() { printf "%s✓%s    %s\n"    "${GREEN}"  "${RESET}" "$*"; }
warn()    { printf "%sWARNING:%s %s\n" "${YELLOW}" "${RESET}" "$*"; }
fatal()   { printf "%sERROR:%s   %s\n" "${RED}"    "${RESET}" "$*" >&2; exit 1; }
banner()  { printf "\n%s%s%s\n\n" "${BOLD}${GREEN}" "$*" "${RESET}"; }

# ─── Preflight checks ─────────────────────────────────────────────────────────
if ! command -v terraform &>/dev/null; then
  fatal "terraform is not installed or not on PATH."
fi

TERRAFORM_VERSION=$(terraform version -json | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
info "Using Terraform ${TERRAFORM_VERSION}"

# ─── Helpers ──────────────────────────────────────────────────────────────────

# require_tfvars DIR — abort with a helpful message if DIR/terraform.tfvars
# does not exist.
require_tfvars() {
  local dir="$1"
  if [[ ! -f "${dir}/terraform.tfvars" ]]; then
    fatal "Missing ${dir}/terraform.tfvars — copy ${dir}/terraform.tfvars.example, fill in your values, and retry."
  fi
}

# tf DIR [args...] — run terraform in the given directory
tf() {
  local dir="$1"; shift
  terraform -chdir="${dir}" "$@"
}

# ─── Destroy path ─────────────────────────────────────────────────────────────
if [[ "${DESTROY}" == "true" ]]; then
  warn "This will permanently destroy ALL resources created by this automation."
  warn "Resources destroyed: LKE cluster, node pools, Cloud Firewall, VPC (if created)."
  printf "\nType %s'yes'%s to continue: " "${BOLD}" "${RESET}"
  read -r confirm
  [[ "${confirm}" == "yes" ]] || { info "Aborted."; exit 0; }

  KUBECONFIG_FILE="${SCRIPT_DIR}/.kubeconfig"

  # ── Phase 2 destroy: remove the controller before destroying the cluster ──
  info "Phase 2 (destroy): Removing cloud-firewall-controller..."
  tf "${SCRIPT_DIR}/controller" init -upgrade -input=false

  if [[ -f "${KUBECONFIG_FILE}" ]]; then
    tf "${SCRIPT_DIR}/controller" destroy -auto-approve \
      -var="kubeconfig_path=${KUBECONFIG_FILE}"
  else
    warn "Kubeconfig not found at ${KUBECONFIG_FILE} — skipping controller destroy."
    warn "If the controller is still installed, remove it manually with:"
    warn "  helm -n kube-system uninstall cloud-firewall cloud-firewall-crd"
  fi
  success "cloud-firewall-controller removed."

  # ── Phase 1 destroy: destroy the cluster and VPC ──────────────────────────
  info "Phase 1 (destroy): Destroying LKE Enterprise cluster..."
  tf "${SCRIPT_DIR}/cluster" init -upgrade -input=false
  tf "${SCRIPT_DIR}/cluster" destroy -auto-approve
  success "Cluster destroyed."

  [[ -f "${KUBECONFIG_FILE}" ]] && rm -f "${KUBECONFIG_FILE}" && info "Removed ${KUBECONFIG_FILE}"

  banner "All resources have been destroyed."
  exit 0
fi

# ─── Apply path ───────────────────────────────────────────────────────────────
require_tfvars "${SCRIPT_DIR}/cluster"
require_tfvars "${SCRIPT_DIR}/controller"

# ── Phase 1: LKE Enterprise cluster ──────────────────────────────────────────
info "Phase 1: Provisioning LKE Enterprise cluster..."
tf "${SCRIPT_DIR}/cluster" init -upgrade -input=false
tf "${SCRIPT_DIR}/cluster" apply -auto-approve
success "Cluster provisioned."

# Capture the absolute path of the kubeconfig written by the cluster module
KUBECONFIG_FILE=$(tf "${SCRIPT_DIR}/cluster" output -raw kubeconfig_path)
info "Kubeconfig written to: ${KUBECONFIG_FILE}"

# ── Phase 2: cloud-firewall-controller ────────────────────────────────────────
info "Phase 2: Installing cloud-firewall-controller..."
tf "${SCRIPT_DIR}/controller" init -upgrade -input=false
tf "${SCRIPT_DIR}/controller" apply -auto-approve \
  -var="kubeconfig_path=${KUBECONFIG_FILE}"
success "cloud-firewall-controller installed."

# ── Done ──────────────────────────────────────────────────────────────────────
banner "LKE Enterprise cluster is ready!"

printf "  %sExport kubeconfig:%s\n"              "${BOLD}" "${RESET}"
printf "    export KUBECONFIG=%s\n\n"             "${KUBECONFIG_FILE}"
printf "  %sVerify firewall controller:%s\n"      "${BOLD}" "${RESET}"
printf "    kubectl -n kube-system get cloudfirewalls\n"
printf "    kubectl -n kube-system get pods -l app.kubernetes.io/name=cloud-firewall-controller\n\n"
printf "  %sVerify firewall rules (Linode API):%s\n" "${BOLD}" "${RESET}"
printf "    # The firewall is named lke-<cluster-id> in your Linode account.\n"
printf "    # Check Cloud Manager → Firewalls, or:\n"
printf "    curl -H \"Authorization: Bearer \$LINODE_TOKEN\" \\\\\n"
printf "         https://api.linode.com/v4/networking/firewalls\n\n"
printf "  %sTear down:%s\n"                       "${BOLD}" "${RESET}"
printf "    ./deploy.sh --destroy\n\n"
