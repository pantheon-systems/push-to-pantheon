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
# but deployment_environment breaks that on purpose so that several sites deploying
# one branch get distinct entries in the pull request timeline. Cleanup therefore
# resolves the mapping from each deployment's payload instead of trusting the name.
#
# The multi-environment cases stub `gh`, because exercising them for real would mean
# creating GitHub environments and deployments on this repository. The guard and
# no-match cases run against the real API.

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

# Stub `gh` so the environment list and deployment payloads are controllable.
# ENVS lists environment names; ENVOF_<key>/SITEOF_<key> give each one's payload.
_stub_gh() {
    local dir="${TEST_TEMP_DIR}/ghstub"
    mkdir -p "${dir}"
    cat > "${dir}/gh" <<'STUB'
#!/bin/bash
path=""; jq=""; prev=""
for a in "$@"; do
  case "$prev" in --jq) jq="$a";; esac
  case "$a" in repos/*) path="$a";; esac
  prev="$a"
done
key() { printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_'; }
[ -n "$GH_CALL_LOG" ] && printf '%s\n' "$*" >> "$GH_CALL_LOG"
case "$path" in
  */deployments/*/statuses) exit 0 ;;
  */environments/*) n="${path##*/environments/}"
      case " $EXACT_ENVS " in *" $n "*) exit 0;; *) exit 1;; esac ;;
  */environments) printf '%s\n' $ENVS; exit 0 ;;
  */deployments*)
      e="${path##*environment=}"; e="${e%%&*}"; k=$(key "$e")
      case "$jq" in
        *pantheon_env*)  eval "printf '%s\n' \"\${ENVOF_$k}\"" ;;
        *pantheon_site*) eval "printf '%s\n' \"\${SITEOF_$k}\"" ;;
        *.id*)           printf '%s\n' $DEPLOY_IDS ;;
      esac; exit 0 ;;
esac
exit 1
STUB
    chmod +x "${dir}/gh"
    export PATH="${dir}:${PATH}"
}

@test "resolve_github_environments: matching name short-circuits the payload lookup" {
    _stub_gh
    export EXACT_ENVS="pr-114" ENVS="pr-114"

    run resolve_github_environments "pr-114"
    assert_success
    [ "$output" = "pr-114" ]
}

@test "resolve_github_environments: picks the environment belonging to this site" {
    _stub_gh
    export EXACT_ENVS="" ENVS="siteA-pr-114 siteB-pr-114"
    export ENVOF_siteA_pr_114="pr-114" SITEOF_siteA_pr_114="siteA"
    export ENVOF_siteB_pr_114="pr-114" SITEOF_siteB_pr_114="siteB"
    export PANTHEON_SITE="siteB"

    run resolve_github_environments "pr-114"
    assert_success
    [ "$output" = "siteB-pr-114" ]
}

@test "resolve_github_environments: does not match on a name substring alone" {
    # "pr-11" is a substring of "siteA-pr-114"; the payload says otherwise.
    _stub_gh
    export EXACT_ENVS="" ENVS="siteA-pr-114"
    export ENVOF_siteA_pr_114="pr-114" SITEOF_siteA_pr_114="siteA"
    export PANTHEON_SITE="siteA"

    run resolve_github_environments "pr-11"
    assert_success
    [ -z "$output" ]
}

@test "delete_github_environment: reports when nothing resolves and deletes nothing" {
    _stub_gh
    export EXACT_ENVS="" ENVS=""

    run delete_github_environment "no-such-env-$$"
    assert_success
    assert_output_contains "No GitHub environment found"
    assert_output_not_contains "Deleting environment"
}

@test "delete_github_environment: still deletes deployments then the environment" {
    # Regression guard for the refactor that introduced resolve_github_environments:
    # the default (matching name) path must behave exactly as before.
    _stub_gh
    export EXACT_ENVS="pr-114" ENVS="pr-114" DEPLOY_IDS="11 22"
    export GH_CALL_LOG="${TEST_TEMP_DIR}/gh-calls.log"
    : > "${GH_CALL_LOG}"

    run delete_github_environment "pr-114"
    assert_success
    assert_output_contains "Deleting deployment ID"
    assert_output_contains "Deleting environment"

    # Deployments must be removed before the environment, or GitHub refuses.
    assert_file_contains "${GH_CALL_LOG}" "deployments/11"
    assert_file_contains "${GH_CALL_LOG}" "deployments/22"
    assert_file_contains "${GH_CALL_LOG}" "environments/pr-114"
    local last_dep last_env
    last_dep=$(grep -n 'deployments/' "${GH_CALL_LOG}" | tail -1 | cut -d: -f1)
    last_env=$(grep -n 'DELETE' "${GH_CALL_LOG}" | grep 'environments/' | tail -1 | cut -d: -f1)
    [ "${last_dep}" -lt "${last_env}" ]
}
