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
