#!/usr/bin/env bats
# Tests for create_multidev() - creation from custom source environment

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

    # Use unique name for this test file: tmp2-{hash}
    local test_env="$(get_test_env)"
    local hash="${test_env#bats-}"
    TEST_MULTIDEV_NAME="tmp2-${hash}"
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

@test "create_multidev: uses custom SOURCE_ENV when specified" {
    export SOURCE_ENV="dev"

    # Ensure it doesn't exist first
    terminus env:delete "${PANTHEON_SITE}.${TEST_MULTIDEV_NAME}" --delete-branch --yes 2>/dev/null || true

    run create_multidev "${TEST_MULTIDEV_NAME}"
    assert_success
    assert_output_contains "from"
    assert_output_contains "dev"
}
