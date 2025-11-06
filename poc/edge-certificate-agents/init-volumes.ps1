#!/usr/bin/env pwsh
################################################################################
# ECA PoC - Infrastructure Volume Initialization Script (Wrapper) - PowerShell
################################################################################
#
# This script is now a thin wrapper around integration-test.ps1 for backward
# compatibility. All initialization logic has been consolidated into
# integration-test.ps1 for better control and unified logging.
#
# Usage:
#   ./init-volumes.ps1
#
# Environment Variables:
#   ECA_CA_PASSWORD - Set CA password (default: eca-poc-default-password)
#
# Exit Codes:
#   0 - Success
#   1 - Error (prerequisites not met or initialization failed)
#
################################################################################

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Forward all arguments and call integration-test.ps1 with -InitOnly flag
& "$ScriptDir/integration-test.ps1" -InitOnly @args
exit $LASTEXITCODE
