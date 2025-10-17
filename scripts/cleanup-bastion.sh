#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
#
# Cleanup OpenStack bastion host

set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/tmp/bastion-cleanup.log}"

# Configuration from environment or arguments
BASTION_NAME="${1:-${BASTION_NAME:-}}"
DEBUG_MODE="${DEBUG_MODE:-false}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

error() {
    echo "[ERROR] $*" >&2 | tee -a "${LOG_FILE}"
}

# Validate required tools
check_dependencies() {
    if ! command -v openstack &>/dev/null; then
        error "openstack CLI not found"
        return 1
    fi

    log "✅ Dependencies available"
}

# Delete bastion instance
delete_bastion() {
    local bastion_name="$1"

    log "🗑️  Deleting bastion instance: ${bastion_name}"

    # Check if instance exists
    if ! openstack server show "${bastion_name}" &>/dev/null; then
        log "⚠️  Bastion instance '${bastion_name}' not found"
        return 0
    fi

    # Delete the instance
    if openstack server delete --wait "${bastion_name}" >> "${LOG_FILE}" 2>&1; then
        log "✅ Bastion instance deleted successfully"
    else
        error "Failed to delete bastion instance"
        return 1
    fi

    # Verify deletion
    local timeout=60
    local elapsed=0
    local interval=5

    while [[ $elapsed -lt $timeout ]]; do
        if ! openstack server show "${bastion_name}" &>/dev/null; then
            log "✅ Bastion instance confirmed deleted"
            return 0
        fi

        log "Waiting for instance deletion... (${elapsed}s/${timeout}s)"
        sleep "${interval}"
        elapsed=$((elapsed + interval))
    done

    error "Timeout waiting for bastion deletion"
    return 1
}

# Main execution
main() {
    log "=== Starting Bastion Cleanup ==="

    # Validate bastion name
    if [[ -z "${BASTION_NAME}" ]]; then
        error "BASTION_NAME not provided"
        echo "Usage: $0 <bastion-name>"
        echo "   or: BASTION_NAME=<name> $0"
        exit 1
    fi

    log "Bastion Name: ${BASTION_NAME}"

    # Check dependencies
    if ! check_dependencies; then
        error "Dependency check failed"
        exit 1
    fi

    # Delete bastion
    if ! delete_bastion "${BASTION_NAME}"; then
        error "Bastion cleanup failed"
        exit 1
    fi

    log "=== Bastion Cleanup Complete ==="
}

# Run main function
main "$@"
