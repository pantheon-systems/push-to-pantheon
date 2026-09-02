#!/usr/bin/env bats
# Tests for resolve_branch_env_name() and get_env_owner_branch()
#
# Pantheon's 11 character limit makes long branches sharing a prefix sanitise to
# the same environment name. Rather than deploy over each other, the second branch
# takes a numbered variant. Ownership is read back from the source branch recorded
# on every deployment the action starts, so these create real deployments and
# remove them again.

load helpers/common

setup() {
    common_setup
    load_main_script

    if [ -z "${GITHUB_TOKEN}" ] || [ -z "${GITHUB_REPOSITORY}" ]; then
        skip "GitHub credentials not available"
    fi

    CREATED_ENVS=""
}

teardown() {
    _cleanup_fixtures
    common_teardown
}

_fixture_suffix() {
    local sha="${GITHUB_SHA:-}"
    if [ -z "${sha}" ]; then
        sha=$(git -C "${BATS_TEST_DIRNAME}/.." rev-parse HEAD 2>/dev/null || echo "local")
    fi
    echo "${sha:0:6}"
}

# Claim an environment name for a branch by recording a deployment for it.
_claim_env() {
    local env_name="$1" source_branch="$2" ref body
    ref=$(gh api "repos/${GITHUB_REPOSITORY}/commits/0.x" --jq '.sha' 2>/dev/null)
    [ -n "${ref}" ] || return 1

    body="${TEST_TEMP_DIR}/claim-${env_name}.json"
    cat > "${body}" <<JSON
{"ref": "${ref}",
 "environment": "${env_name}",
 "auto_merge": false,
 "required_contexts": [],
 "transient_environment": true,
 "description": "push-to-pantheon BATS fixture",
 "payload": {"source_branch": "${source_branch}"}}
JSON

    gh api --method POST "repos/${GITHUB_REPOSITORY}/deployments" --input "${body}" >/dev/null 2>&1
    CREATED_ENVS="${CREATED_ENVS}${env_name}"$'\n'
}

_cleanup_fixtures() {
    local env_name dep
    for env_name in ${CREATED_ENVS}; do
        [ -n "${env_name}" ] || continue
        for dep in $(gh api "repos/${GITHUB_REPOSITORY}/deployments?environment=${env_name}" --jq '.[].id' 2>/dev/null); do
            gh api --method POST "repos/${GITHUB_REPOSITORY}/deployments/${dep}/statuses" \
                -f state=inactive -f description='fixture teardown' >/dev/null 2>&1 || true
            gh api --method DELETE "repos/${GITHUB_REPOSITORY}/deployments/${dep}" >/dev/null 2>&1 || true
        done
        # Deleting the environment needs administration: write, which is not
        # granted here. The deployments are what this registry reads, so removing
        # them is what matters.
        gh api --method DELETE "repos/${GITHUB_REPOSITORY}/environments/${env_name}" >/dev/null 2>&1 || true
    done
    CREATED_ENVS=""
}

@test "get_env_owner_branch: an unclaimed name has no owner" {
    run get_env_owner_branch "ptp-none-$$"
    assert_success
    [ -z "$output" ]
}

@test "get_env_owner_branch: reads back the branch that claimed a name" {
    local env_name="ptp-own-$(_fixture_suffix)"
    _claim_env "${env_name}" "feature/login-a"

    run get_env_owner_branch "${env_name}"
    assert_success
    [ "$output" = "feature/login-a" ]
}

@test "resolve_branch_env_name: an unclaimed name is used as-is" {
    run resolve_branch_env_name "ptp-free-$(_fixture_suffix)"
    assert_success
    # 11-character limit still applies.
    [ "${#output}" -le 11 ]
}

@test "resolve_branch_env_name: a branch reuses its own environment" {
    # Re-pushing a branch must not allocate a second environment.
    local branch="ptp-mine-$(_fixture_suffix)"
    local expected
    expected=$(sanitize_pantheon_env_name "${branch}")
    _claim_env "${expected}" "${branch}"

    run resolve_branch_env_name "${branch}"
    assert_success
    [ "$output" = "${expected}" ]
}

@test "resolve_branch_env_name: steps around a name another branch owns" {
    local suffix base
    suffix=$(_fixture_suffix)
    # Two branches long enough to truncate to the same name.
    base=$(sanitize_pantheon_env_name "ptp-${suffix}-login-a")
    [ "$base" = "$(sanitize_pantheon_env_name "ptp-${suffix}-login-b")" ]

    _claim_env "${base}" "ptp-${suffix}-login-a"

    run resolve_branch_env_name "ptp-${suffix}-login-b"
    assert_success
    [ "$output" = "${base:0:10}0" ]
    [ "${#output}" -le 11 ]
}

@test "resolve_branch_env_name: keeps counting past a taken variant" {
    local suffix base
    suffix=$(_fixture_suffix)
    base=$(sanitize_pantheon_env_name "ptp-${suffix}-login-a")

    _claim_env "${base}" "ptp-${suffix}-login-a"
    _claim_env "${base:0:10}0" "ptp-${suffix}-login-b"

    run resolve_branch_env_name "ptp-${suffix}-login-c"
    assert_success
    [ "$output" = "${base:0:10}1" ]
}

@test "resolve_branch_env_name: reuses a numbered variant it already owns" {
    local suffix base
    suffix=$(_fixture_suffix)
    base=$(sanitize_pantheon_env_name "ptp-${suffix}-login-a")

    _claim_env "${base}" "ptp-${suffix}-login-a"
    _claim_env "${base:0:10}0" "ptp-${suffix}-login-b"

    # login-b already holds variant 0, so it must return to it rather than take 1.
    run resolve_branch_env_name "ptp-${suffix}-login-b"
    assert_success
    [ "$output" = "${base:0:10}0" ]
}

@test "resolve_branch_env_name: reports when a branch yields nothing usable" {
    run resolve_branch_env_name "///"
    [ "$status" -eq 1 ]
}

@test "resolve_branch_env_name: without a registry it returns the base name" {
    # Local runs have no deployment history to consult, so naming still works.
    unset GITHUB_REPOSITORY

    run resolve_branch_env_name "feature/login-a"
    assert_success
    [ "$output" = "feature-log" ]
}
