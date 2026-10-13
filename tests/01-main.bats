#!/usr/bin/env bats
# Tests for main() dispatcher function

load helpers/common

setup() {
    common_setup
    load_main_script
}

teardown() {
    common_teardown
}

@test "main: no arguments provided exits with error" {
    run main
    assert_failure
    assert_output_contains "No command provided"
}

@test "main: help command shows usage" {
    run main help
    assert_success
    assert_output_contains "Usage: bash ./scripts/main.sh"
    assert_output_contains "Available commands:"
    assert_output_contains "get_target_env"
}

@test "main: invalid command exits with error" {
    run main invalid_command
    assert_failure
    assert_output_contains "Invalid command: invalid_command"
}

@test "main: valid command executes successfully" {
    # Set up environment for get_target_env to succeed
    export INPUT_TARGET_ENV="test"

    run main get_target_env
    assert_success
    assert_output_contains "test"
}

@test "main: help lists and dispatch accepts every deployment bookkeeping command" {
    # Stub gh: this is a fast test, so nothing here may reach the network.
    gh() { return 0; }
    export GITHUB_API_RETRY_DELAY=0
    unset GITHUB_REPOSITORY

    local cmd
    for cmd in cleanup_orphaned_github_deployments start_github_deployment finish_github_deployment prune_github_deployments; do
        run main help
        assert_output_contains "- ${cmd}:"

        # Past the allowlist, each command returns cleanly instead of printing
        # "Invalid command".
        run main "${cmd}"
        assert_output_not_contains "Invalid command"
    done
    unset -f gh
}
