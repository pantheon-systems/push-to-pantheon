#!/usr/bin/env bats
# Tests for get_target_env() function

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

@test "get_target_env: no env vars set exits with failure" {
    run get_target_env
    assert_failure
}

@test "get_target_env: other branch without PR_NUM exits with failure" {
    export GITHUB_REF="refs/heads/feature-branch"

    run get_target_env
    assert_failure
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
# Follows KameleonCI: the branch name is used verbatim and validated against
# Pantheon's rules, rather than sanitised or truncated. Truncating would make
# distinct branches collide; a hash suffix would throw away the readability that
# makes branch naming worth having. So an unusable branch name is an error with
# the requirements spelled out.

@test "get_target_env: branch strategy uses the PR source branch verbatim" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export PR_NUM="123"
    export GITHUB_HEAD_REF="my-feature"
    export GITHUB_REF="refs/pull/123/merge"

    run get_target_env
    assert_success
    [ "$output" = "my-feature" ]
}

@test "get_target_env: branch strategy uses the pushed branch when there is no PR" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_REF="refs/heads/short"

    run get_target_env
    assert_success
    [ "$output" = "short" ]
}

@test "get_target_env: pr strategy is the default and is unchanged" {
    export PR_NUM="123"
    export GITHUB_HEAD_REF="my-feature"
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

@test "get_target_env: branch strategy rejects a branch name over 11 characters" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_REF="refs/heads/feature-xyz1"

    run get_target_env
    assert_failure
    assert_output_contains "is not a valid Pantheon environment name"
    assert_output_contains "maximum of 11 characters"
}

@test "get_target_env: branch strategy rejects uppercase" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_REF="refs/heads/MyBranch"

    run get_target_env
    assert_failure
    assert_output_contains "all lowercase"
}

@test "get_target_env: branch strategy rejects a slash" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_REF="refs/heads/feat/x"

    run get_target_env
    assert_failure
    assert_output_contains "is not a valid Pantheon environment name"
}

@test "get_target_env: branch strategy rejects a leading hyphen" {
    export INPUT_TARGET_ENV_STRATEGY="branch"
    export GITHUB_REF="refs/heads/-nope"

    run get_target_env
    assert_failure
    assert_output_contains "starts with a letter or number"
}

@test "get_target_env: rejects an unknown strategy" {
    export INPUT_TARGET_ENV_STRATEGY="nonsense"
    export GITHUB_REF="refs/heads/main"

    run get_target_env
    assert_failure
    assert_output_contains "Invalid target_env_strategy"
}

@test "get_target_env: a branch with no PR and pr strategy explains itself" {
    # This used to exit 1 with no output at all.
    export GITHUB_REF="refs/heads/my-feature"

    run get_target_env
    assert_failure
    assert_output_contains "Could not determine a target environment"
    assert_output_contains "target_env_strategy"
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
