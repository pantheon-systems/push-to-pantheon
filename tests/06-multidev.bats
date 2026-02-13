#!/usr/bin/env bats
# Tests for create_multidev() and delete_multidev() functions

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

@test "create_multidev: creates multidev if it doesn't exist" {
    # Use a short, predictable name (11 char limit)
    export MULTIDEV_NAME="bats-tmp1"
    export SOURCE_ENV="live"

    # Ensure it doesn't exist first
    terminus env:delete "${PANTHEON_SITE}.${MULTIDEV_NAME}" --delete-branch --yes 2>/dev/null || true

    run create_multidev
    assert_success
    assert_output_contains "Creating multidev"

    # Cleanup
    terminus env:delete "${PANTHEON_SITE}.${MULTIDEV_NAME}" --delete-branch --yes || true
}

@test "create_multidev: skips creation if multidev already exists" {
    # Use the test environment which should already exist
    export MULTIDEV_NAME="$(get_test_env)"
    export SOURCE_ENV="live"

    run create_multidev
    assert_success
    assert_output_contains "already exists"
}

@test "create_multidev: uses custom SOURCE_ENV when specified" {
    export MULTIDEV_NAME="bats-tmp2"
    export SOURCE_ENV="dev"

    # Cleanup first
    terminus env:delete "${PANTHEON_SITE}.${MULTIDEV_NAME}" --delete-branch --yes 2>/dev/null || true

    run create_multidev
    assert_success
    assert_output_contains "from"
    assert_output_contains "dev"

    # Cleanup
    terminus env:delete "${PANTHEON_SITE}.${MULTIDEV_NAME}" --delete-branch --yes || true
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

@test "delete_multidev: deletes existing multidev" {
    # Use a short, predictable name (11 char limit)
    export MULTIDEV_NAME="bats-tmp3"

    # Ensure it doesn't exist first, then create it
    terminus env:delete "${PANTHEON_SITE}.${MULTIDEV_NAME}" --delete-branch --yes 2>/dev/null || true
    terminus multidev:create "${PANTHEON_SITE}.live" "${MULTIDEV_NAME}" --yes

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
    export MULTIDEV_NAME="bats-tmp4"

    # Make sure it doesn't exist
    terminus env:delete "${PANTHEON_SITE}.${MULTIDEV_NAME}" --delete-branch --yes 2>/dev/null || true

    run delete_multidev
    assert_success
    assert_output_contains "does not exist"
}
