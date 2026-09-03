#!/usr/bin/env bats
# Tests for get_target_env() function

# `run --separate-stderr` needs 1.5.0; CI installs 1.10.0. Declaring it turns a
# silent misparse on an older bats into an explicit failure.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
    common_setup
    load_main_script

    # Clear all environment variables that affect get_target_env
    unset INPUT_TARGET_ENV
    unset PR_NUM
    unset GITHUB_REF
    unset INPUT_TARGET_ENV_STRATEGY
    unset GITHUB_HEAD_REF
}

teardown() {
    common_teardown
}

@test "get_target_env: INPUT_TARGET_ENV set returns that value" {
    export INPUT_TARGET_ENV="custom-env"

    run get_target_env
    assert_success
    [ "$output" = "custom-env" ]
}

@test "get_target_env: PR_NUM set returns pr-{NUM}" {
    export PR_NUM="123"

    run get_target_env
    assert_success
    [ "$output" = "pr-123" ]
}

@test "get_target_env: INPUT_TARGET_ENV takes precedence over PR_NUM" {
    export INPUT_TARGET_ENV="custom"
    export PR_NUM="123"

    run get_target_env
    assert_success
    [ "$output" = "custom" ]
}

@test "get_target_env: main branch returns dev" {
    export GITHUB_REF="refs/heads/main"

    run get_target_env
    assert_success
    [ "$output" = "dev" ]
}

@test "get_target_env: master branch returns dev" {
    export GITHUB_REF="refs/heads/master"

    run get_target_env
    assert_success
    [ "$output" = "dev" ]
}

@test "get_target_env: no env vars set yields no environment" {
    # Nothing to derive a name from is a skip, not a failure.
    run --separate-stderr get_target_env
    assert_success
    [ -z "$output" ]
}

@test "get_target_env: other branch without PR_NUM yields no environment" {
    export GITHUB_REF="refs/heads/feature-branch"

    run --separate-stderr get_target_env
    assert_success
    [ -z "$output" ]
}

@test "get_target_env: rejects INPUT_TARGET_ENV with special characters" {
    export INPUT_TARGET_ENV="test;rm -rf /"

    run get_target_env
    assert_failure
    [[ "$output" == *"is not a valid Pantheon environment name"* ]]
}

@test "get_target_env: rejects INPUT_TARGET_ENV with newlines" {
    export INPUT_TARGET_ENV="test
newline"

    run get_target_env
    assert_failure
    [[ "$output" == *"is not a valid Pantheon environment name"* ]]
}

@test "get_target_env: accepts INPUT_TARGET_ENV with valid characters" {
    export INPUT_TARGET_ENV="test-env-1"

    run get_target_env
    assert_success
    [ "$output" = "test-env-1" ]
}

@test "get_target_env: rejects INPUT_TARGET_ENV Pantheon would not accept" {
    # This value used to pass validation and then fail at Terminus: underscores
    # are not allowed and it is 12 characters, one over the limit.
    export INPUT_TARGET_ENV="test-env_123"

    run get_target_env
    assert_failure
    assert_output_contains "is not a valid Pantheon environment name"
}

@test "get_target_env: rejects INPUT_TARGET_ENV with spaces" {
    export INPUT_TARGET_ENV="test env"

    run get_target_env
    assert_failure
    [[ "$output" == *"is not a valid Pantheon environment name"* ]]
}

# --- target_env_strategy: branch (issue #102) ---
#
# Branch names routinely contain characters Pantheon rejects and run past its 11
# character limit, so they are normalised rather than refused. Reserved names are
# the exception: normalising form is one thing, but renaming "debug" to something
# else would invent a name the caller never asked for.

@test "get_target_env: branch strategy uses the PR source branch" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export PR_NUM="123"
    export GITHUB_HEAD_REF="redesign"
    export GITHUB_REF="refs/pull/123/merge"

    run get_target_env
    assert_success
    [ "$output" = "redesign" ]
}

@test "get_target_env: branch strategy uses the pushed branch when there is no PR" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_REF="refs/heads/short"

    run get_target_env
    assert_success
    [ "$output" = "short" ]
}

@test "get_target_env: branch strategy sanitises an unusable branch name" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_HEAD_REF="feat/102-branch-name-strategy"

    # The adjustment notice goes to stderr so it stays out of the captured value;
    # bats' `run` merges the two, hence comparing the last line rather than $output.
    run get_target_env
    assert_success
    [ "${lines[-1]}" = "feat-102-br" ]
    assert_output_contains "adjusted to"
}

@test "get_target_env: the adjustment notice stays off stdout" {
    # action.yml captures this with command substitution, so anything explanatory
    # must go to stderr or it would be taken as part of the environment name.
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_HEAD_REF="feat/102-branch-name-strategy"

    run --separate-stderr get_target_env
    assert_success
    [ "$output" = "feat-102-br" ]
    [[ "$stderr" == *"adjusted to"* ]]
}

@test "get_target_env: branch strategy overrides target_env" {
    # Choosing the strategy is enough; an existing target_env need not be unset.
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export INPUT_TARGET_ENV="some-env"
    export GITHUB_REF="refs/heads/redesign"

    run get_target_env
    assert_success
    [ "$output" = "redesign" ]
}

@test "get_target_env: pr strategy is the default and target_env still wins" {
    export INPUT_TARGET_ENV="some-env"
    export PR_NUM="123"
    export GITHUB_HEAD_REF="redesign"

    run get_target_env
    assert_success
    [ "$output" = "some-env" ]
}

@test "get_target_env: pr strategy is unchanged for pull requests" {
    export PR_NUM="123"
    export GITHUB_HEAD_REF="redesign"
    export GITHUB_REF="refs/pull/123/merge"

    run get_target_env
    assert_success
    [ "$output" = "pr-123" ]
}

@test "get_target_env: branch strategy still sends main to dev" {
    # Pantheon's Dev environment is fed by the master branch, so there is no
    # Multidev to name and the strategy does not apply.
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_REF="refs/heads/main"

    run get_target_env
    assert_success
    [ "$output" = "dev" ]
}

@test "get_target_env: branch strategy still sends master to dev" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_REF="refs/heads/master"

    run get_target_env
    assert_success
    [ "$output" = "dev" ]
}

@test "get_target_env: branch strategy reports a reserved branch name" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_REF="refs/heads/debug"

    run get_target_env
    assert_failure
    assert_output_contains "reserved by Pantheon"
}

@test "get_target_env: branch strategy fails when nothing can be derived" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_HEAD_REF="///"

    run get_target_env
    assert_failure
    assert_output_contains "Could not derive an environment name"
}

@test "get_target_env: rejects an unknown strategy" {
    export INPUT_TARGET_ENV_STRATEGY="nonsense"
    export GITHUB_REF="refs/heads/main"

    run get_target_env
    assert_failure
    assert_output_contains "Invalid target_env_strategy"
}

@test "get_target_env: a branch with no PR and pr strategy is a skip, not a failure" {
    # A Multidev comes from a pull request, so a push to another branch has
    # nowhere to go. That is not a misconfiguration, so it must not fail the job.
    export GITHUB_REF="refs/heads/my-feature"

    run --separate-stderr get_target_env
    assert_success
    [ -z "$output" ]
    [[ "$stderr" == *"No target environment to deploy to"* ]]
    [[ "$stderr" == *"target_env_strategy"* ]]
}

@test "get_target_env: a misconfiguration still fails rather than skipping" {
    # The skip above must not swallow genuine errors.
    export INPUT_TARGET_ENV="My_Env"
    run get_target_env
    assert_failure

    unset INPUT_TARGET_ENV
    export INPUT_TARGET_ENV_STRATEGY="nonsense"
    export GITHUB_REF="refs/heads/main"
    run get_target_env
    assert_failure
}

@test "action.yml: every step but the first is gated on the skip flag" {
    # The skip only works if the remaining steps honour it; a new step added
    # without the guard would deploy to an empty environment name.
    run ruby -ryaml -e '
      steps = YAML.safe_load(File.read("'"${BATS_TEST_DIRNAME}"'/../action.yml"), aliases: true)["runs"]["steps"]
      ungated = steps.reject { |s| s["if"].to_s.include?("PANTHEON_DEPLOY_SKIPPED") }
      puts ungated.map { |s| s["name"] }.join(",")
    '
    assert_success
    [ "$output" = "Set target_env" ]
}

# --- sanitize_pantheon_env_name() ---

@test "sanitize_pantheon_env_name: leaves a valid name alone" {
    run sanitize_pantheon_env_name "redesign"
    assert_success
    [ "$output" = "redesign" ]
}

@test "sanitize_pantheon_env_name: lowercases" {
    run sanitize_pantheon_env_name "MyBranch"
    assert_success
    [ "$output" = "mybranch" ]
}

@test "sanitize_pantheon_env_name: folds unusable characters to hyphens" {
    run sanitize_pantheon_env_name "release_2.1"
    assert_success
    [ "$output" = "release-2-1" ]
}

@test "sanitize_pantheon_env_name: collapses hyphen runs and trims the edges" {
    run sanitize_pantheon_env_name "feat//x"
    assert_success
    [ "$output" = "feat-x" ]

    run sanitize_pantheon_env_name "-leading"
    assert_success
    [ "$output" = "leading" ]
}

@test "sanitize_pantheon_env_name: trims to 11 characters" {
    run sanitize_pantheon_env_name "feat/102-branch-name-strategy"
    assert_success
    [ "$output" = "feat-102-br" ]
    [ "${#output}" -le 11 ]
}

@test "sanitize_pantheon_env_name: long branches sharing a prefix converge" {
    # Documented consequence of Pantheon's 11 character limit.
    run sanitize_pantheon_env_name "feature/login-a"
    local a="$output"
    run sanitize_pantheon_env_name "feature/login-b"
    [ "$a" = "$output" ]
}

@test "sanitize_pantheon_env_name: yields nothing when there is nothing usable" {
    run sanitize_pantheon_env_name "///"
    assert_success
    [ -z "$output" ]
}

@test "sanitize_pantheon_env_name: output always satisfies the validator" {
    for branch in "Feature/My-Thing" "release_2.1" "-x" "UPPER" "a/b/c/d/e/f/g/h"; do
        run sanitize_pantheon_env_name "$branch"
        assert_success
        run validate_pantheon_env_name "$output"
        assert_success
    done
}

# --- validate_pantheon_env_name() ---
@test "validate_pantheon_env_name: accepts the core environments" {
    for name in dev test live; do
        run validate_pantheon_env_name "$name"
        assert_success
    done
}

@test "validate_pantheon_env_name: accepts a valid multidev name" {
    run validate_pantheon_env_name "pr-123"
    assert_success

    run validate_pantheon_env_name "a"
    assert_success

    run validate_pantheon_env_name "12345678901"
    assert_success
}

@test "validate_pantheon_env_name: rejects Pantheon's reserved names" {
    for name in master settings team support debug multidev multi files tags billing; do
        run validate_pantheon_env_name "$name"
        [ "$status" -eq 2 ]
    done
}

@test "validate_pantheon_env_name: rejects names Pantheon will not accept" {
    # Uppercase and underscores passed the previous check and then failed at
    # Terminus; 12 characters exceeds the limit.
    for name in "MyEnv" "my_env" "abcdefghijkl" "-lead" "my env" ""; do
        run validate_pantheon_env_name "$name"
        [ "$status" -eq 1 ]
    done
}

@test "get_branch_name: prefers the PR source branch over the ref" {
    export GITHUB_HEAD_REF="from-head-ref"
    export GITHUB_REF="refs/heads/from-ref"

    run get_branch_name
    assert_success
    [ "$output" = "from-head-ref" ]
}

@test "get_branch_name: falls back to the pushed ref" {
    export GITHUB_REF="refs/heads/from-ref"

    run get_branch_name
    assert_success
    [ "$output" = "from-ref" ]
}
