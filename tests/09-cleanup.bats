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

# --- resolve_github_environments() / delete_github_environment() (issue #101) ---
#
# The GitHub deployment environment is normally named after the Pantheon multidev,
# but deployment_environment breaks that on purpose so several sites deploying one
# branch get distinct entries in the pull request timeline. Cleanup therefore
# resolves the mapping from each deployment's payload rather than trusting the name.
#
# These create real deployments and environments on this repository and remove them
# again in teardown. Names are suffixed with the commit SHA so concurrent runs on
# different commits cannot collide.

# Unique suffix for this run's fixtures.
_fixture_suffix() {
    local sha="${GITHUB_SHA:-}"
    if [ -z "${sha}" ]; then
        sha=$(git -C "${BATS_TEST_DIRNAME}/.." rev-parse HEAD 2>/dev/null || echo "local")
    fi
    echo "${sha:0:7}"
}

# A ref that definitely exists on the remote, for the deployment to point at.
_fixture_ref() {
    gh api "repos/${GITHUB_REPOSITORY}/commits/0.x" --jq '.sha' 2>/dev/null
}

# Create a real deployment carrying our payload. Creating a deployment in a new
# environment creates the environment too.
_make_deployment() {
    local env_name="$1" pantheon_env="$2" pantheon_site="$3" ref
    ref=$(_fixture_ref)
    [ -n "${ref}" ] || return 1

    # Write the body to a file rather than piping it on stdin.
    local body="${TEST_TEMP_DIR}/deployment-${env_name}.json"
    cat > "${body}" <<JSON
{"ref": "${ref}",
 "environment": "${env_name}",
 "auto_merge": false,
 "required_contexts": [],
 "transient_environment": true,
 "description": "push-to-pantheon BATS fixture",
 "payload": {"pantheon_site": "${pantheon_site}", "pantheon_env": "${pantheon_env}"}}
JSON

    gh api --method POST "repos/${GITHUB_REPOSITORY}/deployments" --input "${body}" >/dev/null 2>&1

    # Newline-separated: main.sh sets IFS to newline+tab, so a space-joined list
    # would never split and the whole string would be treated as one name.
    CREATED_ENVS="${CREATED_ENVS}${env_name}"$'\n'
}

# Remove every fixture environment this test created, deployments first.
_cleanup_fixtures() {
    local env_name dep
    for env_name in ${CREATED_ENVS}; do
        [ -n "${env_name}" ] || continue
        for dep in $(gh api "repos/${GITHUB_REPOSITORY}/deployments?environment=${env_name}" --jq '.[].id' 2>/dev/null); do
            gh api --method POST "repos/${GITHUB_REPOSITORY}/deployments/${dep}/statuses" \
                -f state=inactive -f description='fixture teardown' >/dev/null 2>&1 || true
            gh api --method DELETE "repos/${GITHUB_REPOSITORY}/deployments/${dep}" >/dev/null 2>&1 || true
        done
        gh api --method DELETE "repos/${GITHUB_REPOSITORY}/environments/${env_name}" >/dev/null 2>&1 || true
    done
    CREATED_ENVS=""
}

@test "resolve_github_environments: empty multidev name yields nothing" {
    run resolve_github_environments ""
    assert_success
    [ -z "$output" ]
}

@test "resolve_github_environments: no GITHUB_REPOSITORY yields nothing" {
    unset GITHUB_REPOSITORY

    run resolve_github_environments "pr-1"
    assert_success
    [ -z "$output" ]
}

@test "resolve_github_environments: unknown multidev yields nothing" {
    run resolve_github_environments "no-such-env-$$"
    assert_success
    [ -z "$output" ]
}

@test "resolve_github_environments: matching name short-circuits the payload lookup" {
    CREATED_ENVS=""
    local suffix env_name
    suffix=$(_fixture_suffix)
    env_name="ptp-same-${suffix}"

    _make_deployment "${env_name}" "${env_name}" "$(get_test_site)"

    run resolve_github_environments "${env_name}"
    _cleanup_fixtures

    assert_success
    [ "$output" = "${env_name}" ]
}

@test "resolve_github_environments: finds a differently named environment via payload" {
    CREATED_ENVS=""
    local suffix multidev env_name
    suffix=$(_fixture_suffix)
    multidev="ptp-diff-${suffix}"
    env_name="mysite-${multidev}"

    _make_deployment "${env_name}" "${multidev}" "$(get_test_site)"

    run resolve_github_environments "${multidev}"
    _cleanup_fixtures

    assert_success
    [ "$output" = "${env_name}" ]
}

@test "resolve_github_environments: picks the environment belonging to this site" {
    CREATED_ENVS=""
    local suffix multidev env_a env_b
    suffix=$(_fixture_suffix)
    multidev="ptp-two-${suffix}"
    env_a="site-a-${multidev}"
    env_b="site-b-${multidev}"

    _make_deployment "${env_a}" "${multidev}" "site-a"
    _make_deployment "${env_b}" "${multidev}" "site-b"

    PANTHEON_SITE="site-b" run resolve_github_environments "${multidev}"
    _cleanup_fixtures

    assert_success
    [ "$output" = "${env_b}" ]
}

@test "resolve_github_environments: does not match on a name substring alone" {
    CREATED_ENVS=""
    local suffix multidev env_name
    suffix=$(_fixture_suffix)
    # The environment belongs to "<multidev>9", so a lookup for "<multidev>" must
    # not claim it even though the name contains that string.
    multidev="ptp-sub-${suffix}"
    env_name="mysite-${multidev}9"

    _make_deployment "${env_name}" "${multidev}9" "$(get_test_site)"

    run resolve_github_environments "${multidev}"
    _cleanup_fixtures

    assert_success
    [ -z "$output" ]
}

@test "delete_github_environment: reports when nothing resolves and deletes nothing" {
    run delete_github_environment "no-such-env-$$"
    assert_success
    assert_output_contains "No GitHub environment found"
    assert_output_not_contains "Deleting environment"
}

@test "delete_github_environment: removes the environment and its deployments" {
    CREATED_ENVS=""
    local suffix env_name
    suffix=$(_fixture_suffix)
    env_name="ptp-del-${suffix}"

    _make_deployment "${env_name}" "${env_name}" "$(get_test_site)"

    # Sanity: it exists before we delete it.
    run gh api "repos/${GITHUB_REPOSITORY}/environments/${env_name}"
    assert_success

    run delete_github_environment "${env_name}"

    # Must never fail the job, whether or not the token may delete environments.
    assert_success
    assert_output_contains "Deleting deployment ID"
    assert_output_contains "Deleting environment"

    # The deployments are the part that matters -- they are what appears in the
    # pull request timeline -- and they must be gone regardless.
    run gh api "repos/${GITHUB_REPOSITORY}/deployments?environment=${env_name}" --jq 'length'
    assert_success
    [ "$output" = "0" ]

    _cleanup_fixtures
}

@test "delete_github_environment: surfaces a failed environment deletion without failing" {
    # Deleting an environment needs administration: write, which the action does not
    # request. That must be reported rather than swallowed -- it used to be neither
    # checked nor surfaced, so runs claimed to delete environments they had not.
    CREATED_ENVS=""
    local suffix env_name
    suffix=$(_fixture_suffix)
    env_name="ptp-perm-${suffix}"

    _make_deployment "${env_name}" "${env_name}" "$(get_test_site)"

    run delete_github_environment "${env_name}"
    _cleanup_fixtures

    assert_success
    if [ "${status}" -eq 0 ] && [[ "$output" == *"Kept environment"* ]]; then
        # Token cannot delete environments: the reason must be explained.
        assert_output_contains "administration: write"
    else
        # Token can: it must say so rather than silently doing nothing.
        assert_output_contains "deleted"
    fi
}
