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
    assert_output_not_contains "Deleting $(get_test_env)"
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

# --- cleanup_closed_pr_multidevs() ---
#
# Workaround for terminus-build-tools-plugin#505 (push-to-pantheon#172). These tests
# pass in an environment list directly so they exercise the PR-resolution logic
# without needing real pr-* multidevs on the test site; the delete calls are no-ops
# because the named environments do not exist.

@test "cleanup_closed_pr_multidevs: skips when GITHUB_REPOSITORY is unset" {
    unset GITHUB_REPOSITORY

    run cleanup_closed_pr_multidevs "pr-1"

    assert_success
    assert_output_contains "GITHUB_REPOSITORY is not set"
}

@test "cleanup_closed_pr_multidevs: no pr-* environments is a no-op" {
    run cleanup_closed_pr_multidevs "$(printf 'dev\ntest\nlive\n0x-std')"

    assert_success
    assert_output_contains "No pr-* multidevs left to check"
}

@test "cleanup_closed_pr_multidevs: ignores environments that only look like PR envs" {
    run cleanup_closed_pr_multidevs "$(printf 'pr-abc\npr-\npr-12-git')"

    assert_success
    assert_output_contains "No pr-* multidevs left to check"
}

@test "cleanup_closed_pr_multidevs: flags an environment whose PR is closed" {
    # PR #171 is merged in this repo, so its state is permanently "closed".
    run cleanup_closed_pr_multidevs "pr-171"

    assert_success
    assert_output_contains "PR #171 is closed"
    assert_output_contains "stale"
}

@test "cleanup_closed_pr_multidevs: keeps an environment whose PR cannot be resolved" {
    run cleanup_closed_pr_multidevs "pr-99999999"

    assert_success
    assert_output_contains "Could not resolve PR #99999999"
    assert_output_contains "No stale closed-PR multidevs found"
}

@test "cleanup_closed_pr_multidevs: never deletes the current target environment" {
    export PANTHEON_TARGET_ENV="pr-171"

    run cleanup_closed_pr_multidevs "pr-171"

    assert_success
    assert_output_not_contains "PR #171 is closed"
    assert_output_contains "No stale closed-PR multidevs found"
}

@test "cleanup_closed_pr_multidevs: keeps an environment whose PR is open" {
    local open_pr
    open_pr=$(gh api "repos/${GITHUB_REPOSITORY}/pulls?state=open&per_page=1" --jq '.[0].number' 2>/dev/null || echo "")
    if [ -z "${open_pr}" ] || [ "${open_pr}" = "null" ]; then
        skip "no open PR on ${GITHUB_REPOSITORY} to test against"
    fi

    run cleanup_closed_pr_multidevs "pr-${open_pr}"

    assert_success
    assert_output_not_contains "is stale"
    assert_output_contains "No stale closed-PR multidevs found"
}
