#!/usr/bin/env bats
# Tests for validation and check_multidev_limit functions

load helpers/common
load helpers/pantheon

setup() {
    common_setup
    load_main_script

    # Skip all tests if required env vars not available
    if [ -z "${PANTHEON_MACHINE_TOKEN}" ] || [ -z "${PANTHEON_TEST_SITE}" ]; then
        skip "Pantheon credentials not available"
    fi

    # Authenticate Terminus for tests that call terminus commands
    authenticate_terminus

    # Set up required environment variables
    export PANTHEON_SITE="$(get_test_site)"
}

teardown() {
    common_teardown
}

# Validation tests (no environment creation needed)

@test "create_multidev: PANTHEON_SITE not set exits with error" {
    unset PANTHEON_SITE
    export MULTIDEV_NAME="test-env"

    run create_multidev
    assert_failure
    assert_output_contains "PANTHEON_SITE environment variable is required"
}

@test "create_multidev: MULTIDEV_NAME not set exits with error" {
    unset MULTIDEV_NAME

    run create_multidev
    assert_failure
    assert_output_contains "MULTIDEV_NAME environment variable is required"
}

@test "delete_multidev: PANTHEON_SITE not set exits with error" {
    unset PANTHEON_SITE
    export MULTIDEV_NAME="test-env"

    run delete_multidev
    assert_failure
    assert_output_contains "PANTHEON_SITE environment variable is required"
}

@test "delete_multidev: MULTIDEV_NAME not set exits with error" {
    unset MULTIDEV_NAME

    run delete_multidev
    assert_failure
    assert_output_contains "MULTIDEV_NAME environment variable is required"
}


# Check limit tests (no environment creation needed)

@test "check_multidev_limit: PANTHEON_SITE not set exits with error" {
    unset PANTHEON_SITE

    run check_multidev_limit
    assert_failure
    assert_output_contains "PANTHEON_SITE environment variable is required"
}

@test "check_multidev_limit: successfully checks multidev availability" {
    run check_multidev_limit
    assert_success
    # Should contain either "available" or "limit reached"
    # Most test sites will have availability, but we can't assume
}

@test "check_multidev_limit: sets GITHUB_OUTPUT when env var is set" {
    # Create temp file for GITHUB_OUTPUT
    local temp_output="${TEST_TEMP_DIR}/github_output"
    export GITHUB_OUTPUT="${temp_output}"

    run check_multidev_limit
    assert_success

    # Verify GITHUB_OUTPUT was written to
    assert_file_exists "${temp_output}"
    assert_file_contains "${temp_output}" "multidev_available="
    assert_file_contains "${temp_output}" "available_count="
}

@test "check_multidev_limit: reports max multidevs correctly" {
    run check_multidev_limit
    assert_success
    # Output should mention the count of available environments
}
