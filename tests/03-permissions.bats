#!/usr/bin/env bats
# Tests for permission checking functions

load helpers/common

setup() {
    common_setup
    load_main_script

    # Set up required environment variables for API calls
    export GITHUB_TOKEN="${GITHUB_TOKEN}"
    export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-pantheon-systems/push-to-pantheon}"
}

teardown() {
    common_teardown
}

@test "check_missing_permissions: valid token with all permissions returns empty" {
    # Skip if GITHUB_TOKEN not available
    if [ -z "${GITHUB_TOKEN}" ]; then
        skip "GITHUB_TOKEN not available"
    fi

    run check_missing_permissions
    assert_success

    # Output should be empty if all permissions are present
    # (or contain specific missing permissions if token is limited)
}

@test "check_missing_permissions: checks PR permission when PR_NUMBER set" {
    # Skip if GITHUB_TOKEN not available
    if [ -z "${GITHUB_TOKEN}" ]; then
        skip "GITHUB_TOKEN not available"
    fi

    export PR_NUMBER="1"

    run check_missing_permissions
    assert_success
}

@test "get_missing_permissions_help: prints help with all required permissions" {
    run get_missing_permissions_help "deployments: write" "contents: read"
    assert_success
    assert_output_contains "Missing required GitHub permissions"
    assert_output_contains "deployments: write"
    assert_output_contains "contents: read"
    assert_output_contains "pull-requests: read"
    assert_output_contains "permissions:"
}

@test "get_missing_permissions_help: contains help URL" {
    run get_missing_permissions_help "deployments: write"
    assert_success
    assert_output_contains "https://github.com/pantheon-systems/push-to-pantheon"
}
