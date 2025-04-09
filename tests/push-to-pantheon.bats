#!/usr/bin/env bats

# Source the setup script
load "./test_helper/setup_mock_repos.sh"

setup() {
    # Create temporary directories for testing
    GITHUB_DIR="$(mktemp -d)"
    PANTHEON_DIR="$(mktemp -d)"
    CI_DIR="$(mktemp -d)"
    LOG_FILE="$(mktemp)"

    # Set up mock repositories
    setup_mock_repos "$GITHUB_DIR" "$PANTHEON_DIR" "$CI_DIR"
}

teardown() {
    # Clean up temporary directories
   # rm -rf "$GITHUB_DIR" "$PANTHEON_DIR" "$CI_DIR" "$LOG_FILE"
}

@test "script logs start of build process" {
    # Run the script
    run scripts/build_and_deploy.sh "$CI_DIR" "$PANTHEON_DIR" "$LOG_FILE"
    [ "$status" -eq 0 ]

    # Check if the log contains the start message
    grep -q "Starting build process" "$LOG_FILE"
}

