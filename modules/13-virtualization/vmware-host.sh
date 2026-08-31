#!/usr/bin/env bash
# modules/13-virtualization/vmware-host.sh
# shellcheck shell=bash
set -euo pipefail

# shellcheck source=../../lib/core.sh
# shellcheck disable=SC2154,SC1091
source "${ARCHFORGE_DIR}/lib/core.sh"
# shellcheck source=../../lib/packages.sh
# shellcheck disable=SC1091
source "${ARCHFORGE_DIR}/lib/packages.sh"
# shellcheck source=../../lib/backup.sh
# shellcheck disable=SC1091
source "${ARCHFORGE_DIR}/lib/backup.sh"

module_info() {
  MODULE_NAME="Virtualization: VMware Workstation (host)"
  MODULE_DESC="Install VMware Workstation Pro on Arch Linux as hypervisor host"
  MODULE_REQUIRES_ROOT=true
  MODULE_HW_WARN=""
  MODULE_PACKAGES=""
  MODULE_AUR_PACKAGES="vmware-workstation"
  MODULE_WIKI_SOURCE="aur-wiki-vmware.txt"
  MODULE_DEPENDS=""
}

module_run() {
  module_info

  # ── Step 1: Nested virtualization check ────────────────────────────────────
  # VMware Workstation as a hypervisor inside another VM rarely works without
  # explicit CPU passthrough configured in the outer host hypervisor.
  local virt_type=""
  virt_type="$(systemd-detect-virt 2>/dev/null || true)"

  if [[ -n "${virt_type}" && "${virt_type}" != "none" ]]; then
    log_warn "Running inside a virtual machine: ${virt_type}"
    log_warn "Installing a hypervisor (VMware Workstation) inside a VM rarely works."
    log_warn "Nested virtualization requires explicit CPU passthrough configuration in the host hypervisor."
    log_warn "VMware kernel modules may fail to compile or load in this environment."
    confirm "Understood — proceed with VMware Workstation installation inside a VM?" || return 2
  fi

  # ── Step 2: Hardware virtualization check ──────────────────────────────────
  # VMware requires Intel VT-x (vmx) or AMD-V (svm) CPU extensions.
  local hv_support=""
  hv_support="$(grep -cE 'vmx|svm' /proc/cpuinfo 2>/dev/null || echo "0")"
  if [[ "${hv_support}" == "0" ]]; then
    log_warn "No hardware virtualization support detected (vmx/svm flags absent from /proc/cpuinfo)."
    log_warn "VMware Workstation requires Intel VT-x or AMD-V enabled in BIOS/UEFI."
    confirm "Proceed without confirmed hardware virtualization support?" || return 2
  else
    log_info "Hardware virtualization supported (${hv_support} CPU thread(s) with vmx/svm)."
  fi

  # ── Step 3: linux-headers check ────────────────────────────────────────────
  # VMware compiles kernel modules at install time; headers matching the running
  # kernel must be present. Check for common header packages.
  local headers_pkg=""
  for pkg in linux-headers linux-lts-headers linux-zen-headers linux-hardened-headers; do
    if pacman -Qq "${pkg}" &>/dev/null; then
      headers_pkg="${pkg}"
      break
    fi
  done

  if [[ -z "${headers_pkg}" ]]; then
    log_warn "No linux-headers package found. VMware kernel modules require headers matching your running kernel."
    log_info "Install the appropriate headers first: pacman -S linux-headers (or linux-lts-headers, etc.)"
    confirm "Proceed without kernel headers installed?" || return 2
  else
    log_info "Kernel headers found: ${headers_pkg}"
  fi

  # ── Step 4: Install VMware Workstation ────────────────────────────────────
  log_info "Installing vmware-workstation from AUR — this downloads a large installer and compiles kernel modules."
  log_info "This may take 15-30 minutes depending on your connection and CPU speed."
  aur_install vmware-workstation

  # ── Step 5: Enable VMware services ────────────────────────────────────────
  # vmware-networks: guest network access (NAT, bridged, host-only)
  # vmware-usbarbitrator: USB passthrough to VMs
  # vmware-hostd: sharing virtual machines (removed since VMware Workstation 16 —
  # source: aur-wiki-vmware.txt, Installation section). Guarded on unit-file
  # existence so a v16+ install doesn't abort here under `set -e`.
  run_cmd sudo systemctl enable --now vmware-networks.service
  run_cmd sudo systemctl enable --now vmware-usbarbitrator.service
  if systemctl list-unit-files vmware-hostd.service &>/dev/null 2>&1; then
    run_cmd sudo systemctl enable --now vmware-hostd.service
  else
    log_info "vmware-hostd.service not present (removed since VMware Workstation 16) — skipping."
  fi

  # ── Step 6: Optional kernel module loading ────────────────────────────────
  # Load vmmon and vmnet now so VMware is usable without a reboot.
  if confirm "Load VMware kernel modules now (vmmon, vmnet) without rebooting?"; then
    run_cmd sudo modprobe vmmon
    run_cmd sudo modprobe vmnet
    run_cmd sudo vmware-networks --start
    log_ok "VMware kernel modules loaded."
  fi

  # ── Step 7: Final messages ─────────────────────────────────────────────────
  log_ok "VMware Workstation installed."
  log_info "Launch: vmware"
  log_info "If kernel modules fail to load after a kernel update, run: sudo vmware-modconfig --console --install-all"
  log_info "USB arbitrator service allows USB passthrough to VMs."
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || module_run
