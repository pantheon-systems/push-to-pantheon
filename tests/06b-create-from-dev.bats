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

    # Use unique name for this test file: tmp2-{hash}. Derived via the shared helper
    # so teardown_file() can arrive at the same name without seeing this variable.
    TEST_MULTIDEV_NAME="$(get_file_multidev_name tmp2)"
}

teardown() {
    common_teardown
}

teardown_file() {
    # Cleanup: delete test environment.
    #
    # Do not reference TEST_MULTIDEV_NAME here. It is assigned in setup(), which runs
    # in a different process context, so it reads as empty in this function -- the
    # guard below never passed and the environment was never deleted. Re-derive the
    # name instead.
    if [ -z "${PANTHEON_MACHINE_TOKEN}" ]; then
        return 0
    fi

    local env_name
    env_name="$(get_file_multidev_name tmp2)"
    if [ -z "${env_name}" ]; then
        return 0
    fi

    authenticate_terminus
    local site
    site="$(get_test_site)"
    terminus env:delete "${site}.${env_name}" --delete-branch --yes 2>/dev/null || true
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

@test "create_multidev: a genuine creation failure is fatal, not a note" {
    # Previously this path printed "may already exist or creation failed" and
    # returned success, so the BATS workflow's setup step reported success without a
    # test environment and the whole integration suite ran against one that was not
    # there. The existence check runs before the create, so reaching the failure
    # branch means the create really failed.
    export SOURCE_ENV="no-such-source-env"

    # Short name: Pantheon caps environment names at 11 characters.
    local name="tmpf-$(get_test_env | sed 's/^bats-//')"

    run create_multidev "${name}"

    assert_failure
    assert_output_contains "failed to create multidev"
}
