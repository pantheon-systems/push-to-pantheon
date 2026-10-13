#!/usr/bin/env bats
# Tests for the GitHub deployment bookkeeping (issue #195): _gh_api_retry,
# start_github_deployment, finish_github_deployment, prune_github_deployments.
#
# Unlike the integration tests in 09-cleanup.bats these stub `gh`. That is
# deliberate: retry, give-up and consecutive-failure behaviour need failures on
# demand, which the real API will not provide. The real-API paths are covered in
# 09-cleanup.bats.

load helpers/common

setup() {
    common_setup
    load_main_script

    export GITHUB_REPOSITORY="owner/repo"
    export GITHUB_API_RETRY_DELAY=0
    export GITHUB_PRUNE_DELAY=0
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/github_output"
    : > "${GITHUB_OUTPUT}"

    CALLS="${TEST_TEMP_DIR}/gh_calls"
    BODIES="${TEST_TEMP_DIR}/gh_bodies"
    : > "${CALLS}"
    : > "${BODIES}"
    export CALLS BODIES
    unset GH_STUB_FAIL GH_STUB_LIST GH_STUB_FAIL_FIRST

    # Records each call; --paginate returns GH_STUB_LIST; calls matching
    # GH_STUB_FAIL fail; the first GH_STUB_FAIL_FIRST calls fail unconditionally.
    gh() {
        local IFS=' ' a prev=""
        echo "$*" >> "${CALLS}"
        for a in "$@"; do
            [ "${prev}" = "--input" ] && cat "${a}" >> "${BODIES}"
            prev="${a}"
        done
        if [ -n "${GH_STUB_FAIL_FIRST}" ] && [ "$(wc -l < "${CALLS}")" -le "${GH_STUB_FAIL_FIRST}" ]; then
            echo "HTTP 502" >&2
            return 1
        fi
        if [ -n "${GH_STUB_FAIL}" ] && [[ "$*" =~ ${GH_STUB_FAIL} ]]; then
            echo "HTTP 502" >&2
            return 1
        fi
        if [[ "$*" == *" --paginate "* ]]; then
            printf '%s' "${GH_STUB_LIST}"
            return 0
        fi
        if [[ "$*" == *"/deployments --input "* ]]; then
            echo '{"id": 42}'
        fi
        return 0
    }
}

teardown() {
    unset -f gh
    common_teardown
}

_count_calls() {
    grep -c -e "$1" "${CALLS}" || true
}

# --- _gh_api_retry ---

@test "_gh_api_retry: returns the body on first success" {
    run _gh_api_retry --method GET repos/owner/repo
    assert_success
    [ "$(_count_calls .)" = "1" ]
}

@test "_gh_api_retry: retries transient failures then succeeds" {
    GH_STUB_FAIL_FIRST=2
    run _gh_api_retry --method GET repos/owner/repo
    assert_success
    [ "$(_count_calls .)" = "3" ]
}

@test "_gh_api_retry: gives up after three attempts and reports the error" {
    GH_STUB_FAIL="repo"
    run _gh_api_retry --method GET repos/owner/repo
    assert_failure
    assert_output_contains "HTTP 502"
    [ "$(_count_calls .)" = "3" ]
}

# --- start_github_deployment ---

@test "start_github_deployment: creates the deployment, writes the id, marks it in_progress" {
    export GITHUB_DEPLOYMENT_ENV="dev" CI_COMMIT_SHA="abc123" PANTHEON_SITE="my-site" PANTHEON_TARGET_ENV="dev"
    export CI_BUILD_URL="https://example.test/run/1"

    run start_github_deployment
    assert_success
    grep -qx 'deployment_id=42' "${GITHUB_OUTPUT}"
    grep -q 'deployments/42/statuses.*state=in_progress' "${CALLS}"
}

@test "start_github_deployment: payload survives quotes and backslashes in the branch name" {
    export GITHUB_DEPLOYMENT_ENV="dev" CI_COMMIT_SHA="abc123" PANTHEON_SITE="my-site" PANTHEON_TARGET_ENV="dev"
    export DEPLOYMENT_SOURCE_BRANCH='fix/"quoted"\branch'

    run start_github_deployment
    assert_success

    [ "$(jq -r '.payload.source_branch' "${BODIES}")" = 'fix/"quoted"\branch' ]
    [ "$(jq -r '.payload.pantheon_site' "${BODIES}")" = "my-site" ]
    [ "$(jq -r '.payload.pantheon_env' "${BODIES}")" = "dev" ]
    [ "$(jq -r '.environment' "${BODIES}")" = "dev" ]
    [ "$(jq -r '.ref' "${BODIES}")" = "abc123" ]
    # Empty required_contexts is what stops GitHub rejecting the deployment (409)
    # while checks are still pending.
    [ "$(jq -c '.required_contexts' "${BODIES}")" = "[]" ]
}

@test "start_github_deployment: retries a transient failure and still succeeds" {
    export GITHUB_DEPLOYMENT_ENV="dev" CI_COMMIT_SHA="abc123" PANTHEON_SITE="my-site" PANTHEON_TARGET_ENV="dev"
    GH_STUB_FAIL_FIRST=1

    run start_github_deployment
    assert_success
    grep -qx 'deployment_id=42' "${GITHUB_OUTPUT}"
}

@test "start_github_deployment: persistent API failure warns, writes no id, exits 0" {
    export GITHUB_DEPLOYMENT_ENV="dev" CI_COMMIT_SHA="abc123" PANTHEON_SITE="my-site" PANTHEON_TARGET_ENV="dev"
    GH_STUB_FAIL="/deployments"

    run start_github_deployment
    assert_success
    assert_output_contains "::warning::Could not create a GitHub deployment"
    assert_output_contains "HTTP 502"
    ! grep -q deployment_id "${GITHUB_OUTPUT}"
}

@test "start_github_deployment: a failed in_progress status warns but keeps the id" {
    export GITHUB_DEPLOYMENT_ENV="dev" CI_COMMIT_SHA="abc123" PANTHEON_SITE="my-site" PANTHEON_TARGET_ENV="dev"
    GH_STUB_FAIL="/statuses"

    run start_github_deployment
    assert_success
    assert_output_contains "::warning::Could not mark GitHub deployment 42 in_progress"
    grep -qx 'deployment_id=42' "${GITHUB_OUTPUT}"
}

# --- finish_github_deployment ---

@test "finish_github_deployment: no deployment id makes no API calls" {
    unset GITHUB_DEPLOYMENT_ID

    run finish_github_deployment
    assert_success
    assert_output_contains "No GitHub deployment to update"
    [ "$(_count_calls .)" = "0" ]
}

@test "finish_github_deployment: success records state and environment_url" {
    export GITHUB_DEPLOYMENT_ID=7 DEPLOYMENT_JOB_STATUS=success DEPLOYMENT_ENV_URL="https://dev-site.pantheonsite.io"

    run finish_github_deployment
    assert_success
    grep -q 'deployments/7/statuses.*state=success' "${CALLS}"
    grep -q 'environment_url=https://dev-site.pantheonsite.io' "${CALLS}"
}

@test "finish_github_deployment: failure records state=failure without an environment_url" {
    export GITHUB_DEPLOYMENT_ID=7 DEPLOYMENT_JOB_STATUS=failure DEPLOYMENT_ENV_URL="https://dev-site.pantheonsite.io"

    run finish_github_deployment
    assert_success
    grep -q 'state=failure' "${CALLS}"
    ! grep -q environment_url "${CALLS}"
}

@test "finish_github_deployment: cancelled records state=inactive" {
    export GITHUB_DEPLOYMENT_ID=7 DEPLOYMENT_JOB_STATUS=cancelled

    run finish_github_deployment
    assert_success
    grep -q 'state=inactive' "${CALLS}"
}

@test "finish_github_deployment: an unrecognised job status is treated as a failure" {
    export GITHUB_DEPLOYMENT_ID=7 DEPLOYMENT_JOB_STATUS=skipped

    run finish_github_deployment
    assert_success
    grep -q 'state=failure' "${CALLS}"
}

@test "finish_github_deployment: persistent API failure warns and exits 0" {
    export GITHUB_DEPLOYMENT_ID=7 DEPLOYMENT_JOB_STATUS=success
    GH_STUB_FAIL="/statuses"

    run finish_github_deployment
    assert_success
    assert_output_contains "::warning::Could not mark GitHub deployment 7 success"
    assert_output_contains "HTTP 502"
}

@test "finish_github_deployment: makes one status call, not one per old deployment" {
    export GITHUB_DEPLOYMENT_ID=7 DEPLOYMENT_JOB_STATUS=success

    run finish_github_deployment
    assert_success
    [ "$(_count_calls .)" = "1" ]
}

# --- prune_github_deployments ---

# Newest first, tab-separated "id<TAB>pantheon_site", as the real listing prints.
_listing() {
    local line
    for line in "$@"; do
        printf '%s\n' "${line//|/$'\t'}"
    done
}

_deleted() {
    grep -- "--method DELETE repos/owner/repo/deployments/$1\$" "${CALLS}"
}

@test "prune_github_deployments: no environment or repository is a no-op" {
    run prune_github_deployments ""
    assert_success
    unset GITHUB_REPOSITORY
    run prune_github_deployments "dev"
    assert_success
    [ "$(_count_calls .)" = "0" ]
}

@test "prune_github_deployments: keeps the newest N of ours and deletes the rest" {
    export PANTHEON_SITE="site-a"
    GH_STUB_LIST=$(_listing "5|site-a" "4|site-a" "3|site-a" "2|site-a")

    run prune_github_deployments dev 2
    assert_success
    _deleted 3
    _deleted 2
    ! _deleted 5
    ! _deleted 4
}

@test "prune_github_deployments: deactivates before deleting" {
    export PANTHEON_SITE="site-a"
    GH_STUB_LIST=$(_listing "2|site-a" "1|site-a")

    run prune_github_deployments dev 1
    assert_success
    grep -n -- 'deployments/1/statuses.*state=inactive' "${CALLS}"
    [ "$(grep -n 'deployments/1/statuses' "${CALLS}" | cut -d: -f1)" -lt "$(grep -n 'DELETE repos/owner/repo/deployments/1$' "${CALLS}" | cut -d: -f1)" ]
}

@test "prune_github_deployments: leaves other sites and payload-less deployments alone" {
    export PANTHEON_SITE="site-a"
    GH_STUB_LIST=$(_listing "5|site-a" "4|other-site" "3|" "2|site-a")

    run prune_github_deployments dev 1
    assert_success
    _deleted 2
    ! _deleted 4
    ! _deleted 3
    ! _deleted 5
}

@test "prune_github_deployments: without PANTHEON_SITE still skips payload-less deployments" {
    unset PANTHEON_SITE
    GH_STUB_LIST=$(_listing "3|site-a" "2|" "1|site-b")

    run prune_github_deployments dev 0
    assert_success
    _deleted 3
    _deleted 1
    ! _deleted 2
}

@test "prune_github_deployments: never deletes the deployment just made" {
    export PANTHEON_SITE="site-a" GITHUB_DEPLOYMENT_ID=1
    GH_STUB_LIST=$(_listing "3|site-a" "2|site-a" "1|site-a")

    run prune_github_deployments dev 0
    assert_success
    _deleted 3
    _deleted 2
    ! _deleted 1
}

@test "prune_github_deployments: caps deletions per run" {
    export PANTHEON_SITE="site-a"
    GH_STUB_LIST=$(_listing "5|site-a" "4|site-a" "3|site-a" "2|site-a" "1|site-a")

    run prune_github_deployments dev 0 2
    assert_success
    [ "$(_count_calls '--method DELETE')" = "2" ]
}

@test "prune_github_deployments: keep defaults from GITHUB_DEPLOYMENTS_KEEP, then to 20" {
    export PANTHEON_SITE="site-a"
    GH_STUB_LIST=$(_listing "3|site-a" "2|site-a" "1|site-a")

    GITHUB_DEPLOYMENTS_KEEP=1 run prune_github_deployments dev
    assert_success
    [ "$(_count_calls '--method DELETE')" = "2" ]

    : > "${CALLS}"
    unset GITHUB_DEPLOYMENTS_KEEP
    run prune_github_deployments dev
    assert_success
    [ "$(_count_calls '--method DELETE')" = "0" ]
}

@test "prune_github_deployments: nothing beyond the keep window deletes nothing" {
    export PANTHEON_SITE="site-a"
    GH_STUB_LIST=$(_listing "2|site-a" "1|site-a")

    run prune_github_deployments dev 5
    assert_success
    [ "$(_count_calls '--method')" = "0" ]
}

@test "prune_github_deployments: a deployment that will not delete is skipped, not fatal" {
    export PANTHEON_SITE="site-a"
    GH_STUB_LIST=$(_listing "3|site-a" "2|site-a" "1|site-a")
    GH_STUB_FAIL="deployments/2/statuses"

    run prune_github_deployments dev 0
    assert_success
    assert_output_contains "Could not delete deployment 2"
    _deleted 3
    _deleted 1
    ! _deleted 2
}

@test "prune_github_deployments: stops after three consecutive failures" {
    export PANTHEON_SITE="site-a"
    GH_STUB_LIST=$(_listing "6|site-a" "5|site-a" "4|site-a" "3|site-a" "2|site-a" "1|site-a")
    GH_STUB_FAIL="/statuses"

    run prune_github_deployments dev 0
    assert_success
    assert_output_contains "Stopping the deployment prune after 3 consecutive failures"
    # Three deployments tried, three attempts each, none reached DELETE.
    [ "$(_count_calls '/statuses')" = "9" ]
    [ "$(_count_calls '--method DELETE')" = "0" ]
}

@test "prune_github_deployments: a success resets the consecutive-failure count" {
    export PANTHEON_SITE="site-a"
    GH_STUB_LIST=$(_listing "5|site-a" "4|site-a" "3|site-a" "2|site-a" "1|site-a")
    # Fail 5, 4 and 2, 1: never three in a row because 3 succeeds between them.
    GH_STUB_FAIL="deployments/(5|4|2|1)/statuses"

    run prune_github_deployments dev 0
    assert_success
    assert_output_not_contains "Stopping the deployment prune"
    _deleted 3
}

@test "prune_github_deployments: a listing failure warns and exits 0" {
    GH_STUB_FAIL="--paginate"

    run prune_github_deployments dev 0
    assert_success
    assert_output_contains "skipping prune"
    [ "$(_count_calls '--method')" = "0" ]
}

@test "prune_github_deployments: tolerates deployments with a non-object payload" {
    export PANTHEON_SITE="site-a"
    # The jq filter maps a string payload to an empty site; the stub stands in
    # for that output, so this checks the empty-site line is ignored cleanly.
    GH_STUB_LIST=$(_listing "2|" "1|site-a")

    run prune_github_deployments dev 0
    assert_success
    _deleted 1
    ! _deleted 2
}
