#!/usr/bin/env bash
################################################################################
# ECA PoC - Infrastructure Volume Initialization Script (Wrapper)
################################################################################
#
# This script is now a thin wrapper around integration-test.sh for backward
# compatibility. All initialization logic has been consolidated into
# integration-test.sh for better control and unified logging.
#
# Usage:
#   ./init-volumes.sh
#
# Environment Variables:
#   ECA_CA_PASSWORD - Set CA password (default: eca-poc-default-password)
#
# Exit Codes:
#   0 - Success
#   1 - Error (prerequisites not met or initialization failed)
#
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Forward all environment variables and call integration-test.sh with --init-only flag
exec "${SCRIPT_DIR}/integration-test.sh" --init-only "$@"
