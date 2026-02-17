#!/usr/bin/env bats
# Tests for cleanup() function

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
    export PANTHEON_TARGET_ENV="$(get_test_env)"
    export GITHUB_REPOSITORY="pantheon-systems/push-to-pantheon"
}

teardown() {
    common_teardown
}

@test "cleanup: DELETE_OLD_MULTIDEVS not true skips deletion" {
    unset DELETE_OLD_MULTIDEVS

    run cleanup
    # Should exit 0 but skip deletion
    assert_output_contains "delete_old_environments was not set to true"
}

@test "cleanup: DELETE_OLD_MULTIDEVS=false skips deletion" {
    export DELETE_OLD_MULTIDEVS="false"

    run cleanup
    assert_output_contains "delete_old_environments was not set to true"
}

@test "cleanup: runs build:env:delete:pr for PR environments" {
    export DELETE_OLD_MULTIDEVS="true"

    # Just verify the function attempts to run the command
    # We can't easily verify actual deletion without creating test PRs
    run cleanup

    # Should see the terminus command output
    assert_output_contains "Deleting stale Pantheon PR multidev environments"
}

@test "cleanup: respects MULTIDEV_AGE_THRESHOLD_DAYS" {
    export DELETE_OLD_MULTIDEVS="true"
    export MULTIDEV_AGE_THRESHOLD_DAYS="30"

    run cleanup

    assert_output_contains "Age threshold:"
    assert_output_contains "30 days"
}

@test "cleanup: default age threshold is 14 days" {
    export DELETE_OLD_MULTIDEVS="true"
    unset MULTIDEV_AGE_THRESHOLD_DAYS

    run cleanup

    assert_output_contains "Age threshold:"
    assert_output_contains "14 days"
}

@test "cleanup: protects current target environment" {
    export DELETE_OLD_MULTIDEVS="true"
    export PANTHEON_TARGET_ENV="$(get_test_env)"

    # The test multidev should never be deleted during this test
    run cleanup

    # Should succeed and not attempt to delete the current environment
    assert_success
    # The output should not contain deletion of the test environment
    refute_output_contains "Deleting $(get_test_env)"
}

@test "cleanup: protects environments with same prefix" {
    export DELETE_OLD_MULTIDEVS="true"
    export PANTHEON_TARGET_ENV="test-std"

    run cleanup

    # Should protect test-std, test-cont, test-git, test-term, test-adv
    assert_output_contains "Protecting all environments with prefix"
}

@test "cleanup: no old environments results in no deletion" {
    export DELETE_OLD_MULTIDEVS="true"
    export MULTIDEV_AGE_THRESHOLD_DAYS="365"  # Very old threshold

    run cleanup

    # With such a high threshold, no environments should match
    assert_success
    assert_output_contains "No old environments found older than 365 days"
}
