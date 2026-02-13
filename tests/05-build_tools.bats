#!/usr/bin/env bats
# Tests for verify_build_tools() function

load helpers/common

setup() {
    common_setup
    load_main_script
}

teardown() {
    common_teardown
}

@test "verify_build_tools: Build Tools installed returns success" {
    # Skip if terminus not available
    if ! command -v terminus &> /dev/null; then
        skip "Terminus not installed"
    fi

    # Skip if Build Tools not installed
    if ! terminus self:plugin:list --format=list --field=name | grep -q '^terminus-build-tools-plugin$'; then
        skip "Build Tools plugin not installed"
    fi

    run verify_build_tools
    assert_success
    assert_output_contains "Build Tools plugin is installed"
}

@test "verify_build_tools: displays version information" {
    # Skip if terminus not available
    if ! command -v terminus &> /dev/null; then
        skip "Terminus not installed"
    fi

    # Skip if Build Tools not installed
    if ! terminus self:plugin:list --format=list --field=name | grep -q '^terminus-build-tools-plugin$'; then
        skip "Build Tools plugin not installed"
    fi

    run verify_build_tools
    assert_success
    assert_output_contains "version:"
}

@test "verify_build_tools: Build Tools not installed exits with error" {
    # Skip if terminus not available
    if ! command -v terminus &> /dev/null; then
        skip "Terminus not installed"
    fi

    # Only run if Build Tools is actually not installed
    if terminus self:plugin:list --format=list --field=name | grep -q '^terminus-build-tools-plugin$'; then
        skip "Build Tools is installed, cannot test not-installed case"
    fi

    run verify_build_tools
    assert_failure
    assert_output_contains "Build Tools plugin installation failed"
}
