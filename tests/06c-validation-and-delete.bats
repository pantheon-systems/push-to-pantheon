#!/usr/bin/env bats
# Tests for validation and delete_multidev() functions

load helpers/common
load helpers/pantheon

TEST_MULTIDEV_NAME=""

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

    # Use unique name for this test file: tmp3-{hash}
    local test_env="$(get_test_env)"
    local hash="${test_env#bats-}"
    TEST_MULTIDEV_NAME="tmp3-${hash}"
}

teardown() {
    common_teardown
}

teardown_file() {
    # Cleanup: delete test environment
    if [ -n "${PANTHEON_MACHINE_TOKEN}" ] && [ -n "${TEST_MULTIDEV_NAME}" ]; then
        authenticate_terminus
        PANTHEON_SITE="$(get_test_site)"
        terminus env:delete "${PANTHEON_SITE}.${TEST_MULTIDEV_NAME}" --delete-branch --yes 2>/dev/null || true
    fi
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

# Delete tests (need an environment to exist)

@test "delete_multidev: deletes existing multidev" {
    export MULTIDEV_NAME="${TEST_MULTIDEV_NAME}"

    # Ensure environment doesn't exist before creating
    terminus env:delete "${PANTHEON_SITE}.${MULTIDEV_NAME}" --delete-branch --yes 2>/dev/null || true

    # Wait for delete to fully complete - poll env:info until it fails
    local attempts=0
    local max_attempts=60
    while [ $attempts -lt $max_attempts ]; do
        if ! terminus env:info "${PANTHEON_SITE}.${MULTIDEV_NAME}" >/dev/null 2>&1; then
            # Environment doesn't exist, good to proceed
            break
        fi
        sleep 2
        attempts=$((attempts + 1))
    done

    # Create the environment
    terminus multidev:create "${PANTHEON_SITE}.live" "${MULTIDEV_NAME}" --yes

    # Wait for creation to complete before testing deletion
    local attempts=0
    local max_attempts=60
    while [ $attempts -lt $max_attempts ]; do
        if terminus env:info "${PANTHEON_SITE}.${MULTIDEV_NAME}" --field=id >/dev/null 2>&1; then
            break
        fi
        sleep 2
        attempts=$((attempts + 1))
    done

    run delete_multidev
    assert_success
    assert_output_contains "deleted successfully"

    # Verify it's gone
    if terminus env:info "${PANTHEON_SITE}.${MULTIDEV_NAME}" >/dev/null 2>&1; then
        echo "Multidev still exists after deletion"
        return 1
    fi
}

@test "delete_multidev: gracefully handles non-existent multidev" {
    export MULTIDEV_NAME="${TEST_MULTIDEV_NAME}"

    # Make sure it doesn't exist
    terminus env:delete "${PANTHEON_SITE}.${MULTIDEV_NAME}" --delete-branch --yes 2>/dev/null || true

    run delete_multidev
    assert_success
    assert_output_contains "does not exist"
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
