#!/usr/bin/env bash
set -euo pipefail

# Push all Coder templates under workspaces/
# Requires: coder CLI logged in (`coder login`)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACES=(
  "Developer"
  "AdvancedHostDANGER"
  "DeveloperAndroid"
  "Maker"
  "Minimal"
  "OpenClaw"
  "ProxmoxVM"
)

ICON_BASE_URL="https://raw.githubusercontent.com/makespacemadrid/coder-workspaces/main"

for ws in "${WORKSPACES[@]}"; do
  dir="${ROOT_DIR}/workspaces/${ws}"
  if [ ! -d "$dir" ]; then
    echo "Skipping ${ws}: not found at ${dir}" >&2
    continue
  fi
  echo ">> Pushing template ${ws}..."
  if [ "$ws" = "ProxmoxVM" ]; then
    required_vars=(
      TF_VAR_proxmox_api_url
      TF_VAR_proxmox_api_token_id
      TF_VAR_proxmox_api_token_secret
      TF_VAR_proxmox_host
      TF_VAR_proxmox_password
      TF_VAR_proxmox_ssh_user
      TF_VAR_proxmox_node
      TF_VAR_disk_storage
      TF_VAR_snippet_storage
      TF_VAR_bridge
      TF_VAR_vlan
      TF_VAR_clone_template_vmid
    )

    for v in "${required_vars[@]}"; do
      if [ -z "${!v:-}" ]; then
        echo "Missing required env var for ProxmoxVM push: ${v}" >&2
        exit 1
      fi
    done

    coder templates push --yes --directory "$dir" \
      --variable "proxmox_api_url=${TF_VAR_proxmox_api_url}" \
      --variable "proxmox_api_token_id=${TF_VAR_proxmox_api_token_id}" \
      --variable "proxmox_api_token_secret=${TF_VAR_proxmox_api_token_secret}" \
      --variable "proxmox_host=${TF_VAR_proxmox_host}" \
      --variable "proxmox_password=${TF_VAR_proxmox_password}" \
      --variable "proxmox_ssh_user=${TF_VAR_proxmox_ssh_user}" \
      --variable "proxmox_node=${TF_VAR_proxmox_node}" \
      --variable "disk_storage=${TF_VAR_disk_storage}" \
      --variable "snippet_storage=${TF_VAR_snippet_storage}" \
      --variable "bridge=${TF_VAR_bridge}" \
      --variable "vlan=${TF_VAR_vlan}" \
      --variable "clone_template_vmid=${TF_VAR_clone_template_vmid}"
  else
    coder templates push --yes --directory "$dir"
  fi

  icon_path="$dir/icon.svg"
  if [ -f "$icon_path" ]; then
    icon_url="${ICON_BASE_URL}/workspaces/${ws}/icon.svg"
    echo ">> Updating icon for ${ws}..."
    coder templates edit --yes --icon "$icon_url" "$ws"
  else
    echo "!! Missing icon for ${ws}: ${icon_path}" >&2
  fi
done

echo "Done."
