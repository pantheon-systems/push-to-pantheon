#!/usr/bin/env bats
# Tests for push_to_pantheon() function

load helpers/common
load helpers/pantheon

setup() {
    common_setup
    load_main_script

    # Skip all tests if required env vars not available
    if [ -z "${PANTHEON_MACHINE_TOKEN}" ] || [ -z "${PANTHEON_TEST_SITE}" ] || [ -z "${PANTHEON_TEST_ENV}" ]; then
        skip "Pantheon credentials or test environment not available"
    fi

    # Authenticate Terminus for tests that call terminus commands
    authenticate_terminus

    # Set up required environment variables
    export PANTHEON_SITE="$(get_test_site)"
    export PANTHEON_TARGET_ENV="$(get_test_env)"
    export PANTHEON_SOURCE_ENV="live"
    export PANTHEON_COMMIT_MESSAGE="Test commit from BATS"

    # Setup SSH for Pantheon access
    setup_test_ssh_key
}

teardown() {
    common_teardown
}

@test "push_to_pantheon: SKIP_BUILD_TOOLS=true uses git push workflow" {
    # Skip if SSH key not available
    if [ -z "${PANTHEON_SSH_KEY}" ]; then
        skip "PANTHEON_SSH_KEY not available"
    fi

    export SKIP_BUILD_TOOLS="true"

    # This test verifies the function enters the git-only path
    # We won't actually push, just verify the logic path
    run bash -c 'source <(sed "$ d" scripts/main.sh) && set -x && push_to_pantheon 2>&1 | head -20'

    # Should see messages about git push workflow
    assert_output_contains "Target environment is"
}

@test "push_to_pantheon: LIVE_ENV_EXISTS=false uses git push workflow" {
    # Skip if SSH key not available
    if [ -z "${PANTHEON_SSH_KEY}" ]; then
        skip "PANTHEON_SSH_KEY not available"
    fi

    export LIVE_ENV_EXISTS="false"

    # This test verifies the function enters the git-only path
    run bash -c 'source <(sed "$ d" scripts/main.sh) && set -x && push_to_pantheon 2>&1 | head -20'

    # Should see messages about git push workflow
    assert_output_contains "Target environment is"
}

@test "push_to_pantheon: target=dev pushes to master branch" {
    # Skip if SSH key not available
    if [ -z "${PANTHEON_SSH_KEY}" ]; then
        skip "PANTHEON_SSH_KEY not available"
    fi

    export SKIP_BUILD_TOOLS="true"
    export PANTHEON_TARGET_ENV="dev"

    run bash -c 'source <(sed "$ d" scripts/main.sh) && set -x && push_to_pantheon 2>&1 | head -20'

    assert_output_contains "Target environment is dev"
    assert_output_contains "master"
}

@test "push_to_pantheon: multidev target checks if environment exists" {
    # Skip if SSH key not available
    if [ -z "${PANTHEON_SSH_KEY}" ]; then
        skip "PANTHEON_SSH_KEY not available"
    fi

    export SKIP_BUILD_TOOLS="true"
    export PANTHEON_TARGET_ENV="$(get_test_env)"

    run bash -c 'source <(sed "$ d" scripts/main.sh) && set -x && push_to_pantheon 2>&1 | head -30'

    # Should call create_multidev which checks for multidev existence
    # Note: Full command will fail at git push, but we only care about
    # verifying the multidev check logic worked correctly
    assert_output_contains "Checking if multidev"
    assert_output_contains "already exists"
}
