#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

build_and_deploy() {
    local ci_dir="$1"
    local pantheon_dir="$2"
    local log_file="$3"

    # Redirect all output to the log file
    exec 1>>"$log_file" 2>&1

    # Log start of process
    echo "Starting build process"

    # Create a new branch for this CI run
    cd "$ci_dir"
    local ci_branch="ci-$(date +%s)"
    git checkout -b "$ci_branch"
    echo "Creating new branch $ci_branch"

    # Run npm build
    echo "Running npm build"
    # TODO: Actually run npm build
    # For now, just create a dummy CSS file
    mkdir -p css
    echo "/* Built by CI at $(date) */" > css/style.css

    # Commit build artifacts
    git add css/style.css
    git commit -m "Add build artifacts"
    echo "Committing build artifacts"

    return 0
}

# Only execute main if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    build_and_deploy "$1" "$2" "$3"
fi 