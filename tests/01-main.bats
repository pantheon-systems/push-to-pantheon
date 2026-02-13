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
