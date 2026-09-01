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

    run create_multidev "test-env"
    assert_failure
    assert_output_contains "PANTHEON_SITE environment variable is required"
}

@test "create_multidev: MULTIDEV_NAME not set exits with error" {
    run create_multidev ""
    assert_failure
    assert_output_contains "MULTIDEV_NAME environment variable is required"
}

@test "delete_multidev: PANTHEON_SITE not set exits with error" {
    unset PANTHEON_SITE

    run delete_multidev "test-env"
    assert_failure
    assert_output_contains "PANTHEON_SITE environment variable is required"
}

@test "delete_multidev: MULTIDEV_NAME not set exits with error" {
    run delete_multidev ""
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

# --- limit check must not block redeploys to an existing environment ---
#
# The limit steps in action.yml used to be gated on `inputs.target_env == ''`, so
# they never ran for explicitly named environments -- including every test suite
# deployment. Removing that gate means the check now runs for those too, which makes
# it important that an existing target does not read as "no room".

@test "check_multidev_limit: existing target env does not consume a slot" {
    export PANTHEON_TARGET_ENV="$(get_test_env)"

    run check_multidev_limit
    assert_success
    assert_output_contains "already exists; no new multidev slot required"
}

@test "check_multidev_limit: existing target env reports availability to GITHUB_OUTPUT" {
    export PANTHEON_TARGET_ENV="$(get_test_env)"
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/github_output"
    : > "${GITHUB_OUTPUT}"

    run check_multidev_limit
    assert_success
    assert_file_contains "${GITHUB_OUTPUT}" "multidev_available=true"
}

@test "check_multidev_limit: absent target env falls through to the slot count" {
    export PANTHEON_TARGET_ENV="definitely-not-a-real-env"

    run check_multidev_limit
    assert_success
    assert_output_not_contains "no new multidev slot required"
}

@test "action.yml: limit steps are not gated on an empty target_env" {
    # Regression guard: the gate meant the multidev limit warning never reached a PR
    # that passed target_env explicitly.
    run grep -c "inputs.target_env == ''" "${BATS_TEST_DIRNAME}/../action.yml"
    assert_failure
}
