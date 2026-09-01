#!/usr/bin/env bats
# Tests for create_multidev() - creation from live environment

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

    # Use unique name for this test file: tmp1-{hash}. Derived via the shared helper
    # so teardown_file() can arrive at the same name without seeing this variable.
    TEST_MULTIDEV_NAME="$(get_file_multidev_name tmp1)"
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
    env_name="$(get_file_multidev_name tmp1)"
    if [ -z "${env_name}" ]; then
        return 0
    fi

    authenticate_terminus
    local site
    site="$(get_test_site)"
    terminus env:delete "${site}.${env_name}" --delete-branch --yes 2>/dev/null || true
}

@test "create_multidev and delete_multidev: create, detect existing, and delete" {
    export SOURCE_ENV="live"

    # Ensure it doesn't exist first
    terminus env:delete "${PANTHEON_SITE}.${TEST_MULTIDEV_NAME}" --delete-branch --yes 2>/dev/null || true

    # First call: create the environment
    run create_multidev "${TEST_MULTIDEV_NAME}"
    assert_success
    assert_output_contains "Creating multidev"

    # Wait for environment to be fully created and accessible
    local attempts=0
    local max_attempts=60
    while [ $attempts -lt $max_attempts ]; do
        if terminus env:info "${PANTHEON_SITE}.${TEST_MULTIDEV_NAME}" --field=id >/dev/null 2>&1; then
            break
        fi
        sleep 2
        attempts=$((attempts + 1))
    done

    # Verify it's accessible
    if ! terminus env:info "${PANTHEON_SITE}.${TEST_MULTIDEV_NAME}" --field=id >/dev/null 2>&1; then
        return 1
    fi

    # Second call: verify it detects the existing environment and returns early
    run create_multidev "${TEST_MULTIDEV_NAME}"
    assert_success
    assert_output_contains "✅ Multidev"
    assert_output_contains "already exists."

    # Test deletion
    run delete_multidev "${TEST_MULTIDEV_NAME}"
    assert_success
    assert_output_contains "deleted successfully"

    # Verify it's gone
    if terminus env:info "${PANTHEON_SITE}.${TEST_MULTIDEV_NAME}" >/dev/null 2>&1; then
        echo "Multidev still exists after deletion"
        return 1
    fi
}

# --- guards for the cleanup leak (see get_file_multidev_name) ---

@test "get_file_multidev_name: derives the name from the test environment" {
    export PANTHEON_TEST_ENV="bats-a1b2"

    run get_file_multidev_name tmp1
    assert_success
    [ "$output" = "tmp1-a1b2" ]
}

@test "get_file_multidev_name: is stable for the same prefix and test env" {
    export PANTHEON_TEST_ENV="bats-a1b2"

    # setup() and teardown_file() must agree, or cleanup targets the wrong name.
    run get_file_multidev_name tmp2
    assert_success
    [ "$output" = "tmp2-a1b2" ]
}

@test "get_file_multidev_name: no test environment yields no name" {
    unset PANTHEON_TEST_ENV

    run get_file_multidev_name tmp1
    assert_success
    # Must be empty, so callers no-op rather than deleting "tmp1-".
    [ -z "$output" ]
}

@test "teardown_file does not depend on a variable assigned in setup" {
    # TEST_MULTIDEV_NAME is assigned in setup(), which runs in a different process
    # context, so it reads as empty in teardown_file(). Referencing it there meant
    # the environment was never deleted and leaked on every run.
    for f in "${BATS_TEST_DIRNAME}/06a-create-from-live.bats" \
             "${BATS_TEST_DIRNAME}/06b-create-from-dev.bats"; do
        # Ignore comment lines -- the fix documents the variable by name.
        run bash -c "sed -n '/^teardown_file()/,/^}/p' '$f' | grep -v '^[[:space:]]*#' | grep -c TEST_MULTIDEV_NAME"
        assert_failure
    done
}
