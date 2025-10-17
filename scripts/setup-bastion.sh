#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
#
# Setup OpenStack bastion host with Tailscale

set -euo pipefail

# Script variables
LOG_FILE="${LOG_FILE:-/tmp/bastion-setup.log}"

# Configuration from environment
BASTION_NAME="${BASTION_NAME:?Error: BASTION_NAME not set}"
BASTION_FLAVOR="${BASTION_FLAVOR:-v3-standard-2}"
BASTION_IMAGE="${BASTION_IMAGE:-Ubuntu 22.04.5 LTS (x86_64) [2025-03-27]}"
BASTION_NETWORK="${BASTION_NETWORK:-odlci}"
BASTION_SSH_KEY="${BASTION_SSH_KEY:-}"
DEBUG_MODE="${DEBUG_MODE:-false}"

# Tailscale configuration
TAILSCALE_OAUTH_CLIENT_ID="${TAILSCALE_OAUTH_CLIENT_ID:-}"
TAILSCALE_OAUTH_SECRET="${TAILSCALE_OAUTH_SECRET:-}"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
TAILSCALE_TAGS="${TAILSCALE_TAGS:-tag:ci}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}" >&2
}

error() {
    echo "[ERROR] $*" >&2 | tee -a "${LOG_FILE}"
}

# Validate required tools
check_dependencies() {
    local missing_deps=()

    for cmd in openstack jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        return 1
    fi

    log "✅ All dependencies available"
}

# Generate cloud-init configuration
generate_cloud_init() {
    local cloud_init_file="/tmp/bastion-cloud-init.yaml"

    log "Generating cloud-init configuration..."

    # Determine which Tailscale authentication to use
    local tailscale_auth_cmd
    if [[ -n "${TAILSCALE_AUTH_KEY}" ]]; then
        tailscale_auth_cmd="--authkey=${TAILSCALE_AUTH_KEY}"
    elif [[ -n "${TAILSCALE_OAUTH_CLIENT_ID}" ]] && [[ -n "${TAILSCALE_OAUTH_SECRET}" ]]; then
        # OAuth cannot be used directly in cloud-init, we need an auth key
        error "Error: Bastion requires tailscale_auth_key. OAuth can only be used for the GitHub runner."
        error "Please provide tailscale_auth_key input for bastion authentication."
        return 1
    else
        error "Error: No Tailscale authentication provided for bastion"
        return 1
    fi

    cat > "${cloud_init_file}" <<'EOF'
#cloud-config
# OpenStack Tailscale Bastion Host Cloud-Init

hostname: BASTION_HOSTNAME_PLACEHOLDER
manage_etc_hosts: true

package_update: true
package_upgrade: true

packages:
  - curl
  - wget
  - jq
  - net-tools
  - iputils-ping
  - ca-certificates
  - python3
  - python3-pip

write_files:
  - path: /etc/sysctl.d/99-tailscale.conf
    content: |
      net.ipv4.ip_forward = 1
      net.ipv6.conf.all.forwarding = 1
      net.netfilter.nf_conntrack_max = 131072
    permissions: '0644'

  - path: /usr/local/bin/bastion-init.sh
    content: |
      #!/bin/bash
      set -e
      echo "[$(date)] Bastion initialization started" | tee -a /var/log/bastion-init.log

      # Wait for network
      until ping -c 1 8.8.8.8 &>/dev/null; do
        echo "Waiting for network..." | tee -a /var/log/bastion-init.log
        sleep 2
      done

      echo "[$(date)] Network ready" | tee -a /var/log/bastion-init.log

      # Install Tailscale
      echo "[$(date)] Installing Tailscale..." | tee -a /var/log/bastion-init.log
      curl -fsSL https://tailscale.com/install.sh | sh

      # Start Tailscale
      echo "[$(date)] Starting Tailscale..." | tee -a /var/log/bastion-init.log
      tailscale up \
        TAILSCALE_AUTH_PLACEHOLDER \
        --hostname="BASTION_HOSTNAME_PLACEHOLDER" \
        --advertise-tags=TAILSCALE_TAGS_PLACEHOLDER \
        --ssh \
        --accept-routes \
        --accept-dns=false

      TAILSCALE_IP=$(tailscale ip -4)
      echo "[$(date)] Tailscale connected: ${TAILSCALE_IP}" | tee -a /var/log/bastion-init.log

      # Create ready marker
      echo "READY" > /tmp/bastion-ready
      echo "[$(date)] Bastion ready" | tee -a /var/log/bastion-init.log
    permissions: '0755'

  - path: /etc/motd
    content: |
      ╔═══════════════════════════════════════════╗
      ║   OpenStack Tailscale Bastion Host        ║
      ║   GitHub Actions Build Environment        ║
      ╚═══════════════════════════════════════════╝
      Logs: /var/log/bastion-init.log
    permissions: '0644'

timezone: UTC

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: sudo
    lock_passwd: true

ssh_pwauth: false
disable_root: false

runcmd:
  - sysctl -p /etc/sysctl.d/99-tailscale.conf
  - /usr/local/bin/bastion-init.sh

final_message: "Bastion initialization complete after $UPTIME seconds"
EOF

    # Substitute placeholders
    sed -i "s/BASTION_HOSTNAME_PLACEHOLDER/${BASTION_NAME}/g" "${cloud_init_file}"
    sed -i "s|TAILSCALE_AUTH_PLACEHOLDER|${tailscale_auth_cmd}|g" "${cloud_init_file}"
    sed -i "s/TAILSCALE_TAGS_PLACEHOLDER/${TAILSCALE_TAGS}/g" "${cloud_init_file}"

    if [[ "${DEBUG_MODE}" == "true" ]]; then
        log "Cloud-init configuration:"
        cat "${cloud_init_file}" | tee -a "${LOG_FILE}"
    fi

    echo "${cloud_init_file}"
}

# Create bastion instance
create_bastion() {
    local cloud_init_file="$1"

    log "🚀 Creating bastion instance: ${BASTION_NAME}"
    log "  Flavor: ${BASTION_FLAVOR}"
    log "  Image: ${BASTION_IMAGE}"
    log "  Network: ${BASTION_NETWORK}"

    # Build openstack command
    local cmd=(
        "openstack" "server" "create"
        "--flavor" "${BASTION_FLAVOR}"
        "--image" "${BASTION_IMAGE}"
        "--network" "${BASTION_NETWORK}"
    )

    # Add SSH key if specified
    if [[ -n "${BASTION_SSH_KEY}" ]]; then
        cmd+=("--key-name" "${BASTION_SSH_KEY}")
        log "  SSH Key: ${BASTION_SSH_KEY}"
    else
        log "  SSH Key: None (using Tailscale SSH)"
    fi

    cmd+=(
        "--user-data" "${cloud_init_file}"
        "--wait"
        "${BASTION_NAME}"
    )

    if [[ "${DEBUG_MODE}" == "true" ]]; then
        log "Command: ${cmd[*]}"
    fi

    # Capture both stdout and stderr
    if ! ERROR_OUTPUT=$("${cmd[@]}" 2>&1); then
        error "Failed to create bastion instance"
        error "OpenStack error output:"
        error "${ERROR_OUTPUT}"
        echo "${ERROR_OUTPUT}" >> "${LOG_FILE}"
        return 1
    fi

    log "✅ Bastion instance created successfully"
    echo "${ERROR_OUTPUT}" >> "${LOG_FILE}"

    # Get instance details
    if [[ "${DEBUG_MODE}" == "true" ]]; then
        log "Instance details:"
        openstack server show "${BASTION_NAME}" -f yaml | tee -a "${LOG_FILE}"
    fi
}

# Main execution
main() {
    log "=== Starting Bastion Setup ==="
    log "Bastion Name: ${BASTION_NAME}"

    # Check dependencies
    if ! check_dependencies; then
        error "Dependency check failed"
        exit 1
    fi

    # Validate Tailscale authentication
    if [[ -z "${TAILSCALE_AUTH_KEY}" ]] && [[ -z "${TAILSCALE_OAUTH_CLIENT_ID}" ]]; then
        error "Either TAILSCALE_AUTH_KEY or TAILSCALE_OAUTH_CLIENT_ID must be set"
        exit 1
    fi

    # Generate cloud-init
    cloud_init_file=$(generate_cloud_init)

    # Create bastion
    if ! create_bastion "${cloud_init_file}"; then
        error "Bastion setup failed"
        exit 1
    fi

    log "=== Bastion Setup Complete ==="
}

# Run main function
main "$@"
