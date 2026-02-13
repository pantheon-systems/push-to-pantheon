#!/usr/bin/env bats
# Tests for get_commit_message() function

load helpers/common

setup() {
    common_setup
    load_main_script

    # Clear all environment variables that affect get_commit_message
    unset PANTHEON_COMMIT_MESSAGE
    unset PR_NUM
    unset GITHUB_REF
}

teardown() {
    common_teardown
}

@test "get_commit_message: PANTHEON_COMMIT_MESSAGE set returns that value" {
    export PANTHEON_COMMIT_MESSAGE="Custom commit message"

    run get_commit_message
    assert_success
    [ "$output" = "Custom commit message" ]
}

@test "get_commit_message: PR_NUM set returns PR deployment message" {
    export PR_NUM="123"

    run get_commit_message
    assert_success
    [ "$output" = "Deploy PR #123 to Pantheon" ]
}

@test "get_commit_message: PANTHEON_COMMIT_MESSAGE takes precedence over PR_NUM" {
    export PANTHEON_COMMIT_MESSAGE="Override message"
    export PR_NUM="123"

    run get_commit_message
    assert_success
    [ "$output" = "Override message" ]
}

@test "get_commit_message: GITHUB_REF set returns branch deployment message" {
    export GITHUB_REF="refs/heads/feature-branch"

    run get_commit_message
    assert_success
    [ "$output" = "Deploy feature-branch to Pantheon" ]
}

@test "get_commit_message: PR_NUM takes precedence over GITHUB_REF" {
    export PR_NUM="456"
    export GITHUB_REF="refs/heads/main"

    run get_commit_message
    assert_success
    [ "$output" = "Deploy PR #456 to Pantheon" ]
}

@test "get_commit_message: main branch returns main deployment message" {
    export GITHUB_REF="refs/heads/main"

    run get_commit_message
    assert_success
    [ "$output" = "Deploy main to Pantheon" ]
}

@test "get_commit_message: master branch returns master deployment message" {
    export GITHUB_REF="refs/heads/master"

    run get_commit_message
    assert_success
    [ "$output" = "Deploy master to Pantheon" ]
}

@test "get_commit_message: no env vars returns generic message" {
    run get_commit_message
    assert_success
    # When GITHUB_REF is empty, it should strip "refs/heads/" prefix from empty string
    [ "$output" = "Deploy  to Pantheon" ]
}
