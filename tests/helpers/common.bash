#!/bin/bash
# Common test utilities for BATS tests

# Load the main.sh script for testing
# This sources all functions without executing main()
load_main_script() {
    # BATS_TEST_DIRNAME is the tests/ directory
    # Go up one level to get to the repo root
    SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    MAIN_SCRIPT="${SCRIPT_DIR}/scripts/main.sh"

    # Source the script but prevent main() from executing
    # We remove the last line which calls main "$@"
    source <(sed '$ d' "${MAIN_SCRIPT}")
}

# Setup function to run before each test
common_setup() {
    # Create temp directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Save original HOME
    ORIGINAL_HOME="${HOME}"
    export ORIGINAL_HOME

    # Use test temp dir as HOME for SSH config isolation
    export HOME="${TEST_TEMP_DIR}"

    # Preserve Terminus cache directory for authentication
    # The workflow authenticated Terminus, we need to keep that session
    if [ -d "${ORIGINAL_HOME}/.terminus" ]; then
        mkdir -p "${HOME}/.terminus"
        cp -r "${ORIGINAL_HOME}/.terminus"/* "${HOME}/.terminus/" 2>/dev/null || true
    fi
}

# Teardown function to run after each test
common_teardown() {
    # Restore original HOME
    export HOME="${ORIGINAL_HOME}"

    # Clean up temp directory
    if [ -n "${TEST_TEMP_DIR}" ] && [ -d "${TEST_TEMP_DIR}" ]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi

    # Clean up any test-specific environment variables
    # to prevent pollution between tests
    unset INPUT_TARGET_ENV
    unset PR_NUM
    unset GITHUB_REF
    unset SSH_KEY
    unset SITE_ROOT
    unset PANTHEON_REPO_DIR
    unset SKIP_BUILD_TOOLS
    unset LIVE_ENV_EXISTS
    unset DELETE_OLD_MULTIDEVS
    unset MULTIDEV_AGE_THRESHOLD_DAYS
    unset MULTIDEV_DELETE_PATTERN
    unset PANTHEON_COMMIT_MESSAGE
    unset PANTHEON_CLONE_CONTENT_FLAG
    unset PANTHEON_DESTINATION_BRANCH
}

# Assert that command succeeded (exit code 0)
assert_success() {
    if [ "$status" -ne 0 ]; then
        echo "Expected success but got status: $status"
        echo "Output: $output"
        return 1
    fi
}

# Assert that command failed (non-zero exit code)
assert_failure() {
    if [ "$status" -eq 0 ]; then
        echo "Expected failure but command succeeded"
        echo "Output: $output"
        return 1
    fi
}

# Assert that output contains expected string
assert_output_contains() {
    local expected="$1"
    if [[ ! "$output" =~ $expected ]]; then
        echo "Expected output to contain: $expected"
        echo "Actual output: $output"
        return 1
    fi
}

# Assert that output does not contain string
assert_output_not_contains() {
    local unexpected="$1"
    if [[ "$output" =~ $unexpected ]]; then
        echo "Expected output NOT to contain: $unexpected"
        echo "Actual output: $output"
        return 1
    fi
}

# Assert that file or directory exists
assert_file_exists() {
    local file="$1"
    if [ ! -e "$file" ]; then
        echo "Expected file to exist: $file"
        return 1
    fi
}

# Assert file has specific permissions
assert_file_perms() {
    local file="$1"
    local expected_perms="$2"

    # Try macOS stat first, then Linux stat
    local actual_perms
    if actual_perms=$(stat -f "%OLp" "$file" 2>/dev/null); then
        : # macOS succeeded
    elif actual_perms=$(stat -c "%a" "$file" 2>/dev/null); then
        : # Linux succeeded
    else
        echo "Failed to get permissions for $file"
        return 1
    fi

    if [ "$actual_perms" != "$expected_perms" ]; then
        echo "Expected file $file to have permissions $expected_perms but got $actual_perms"
        return 1
    fi
}

# Assert file contains text
assert_file_contains() {
    local file="$1"
    local expected="$2"

    if ! grep -q "$expected" "$file"; then
        echo "Expected file $file to contain: $expected"
        echo "File contents:"
        cat "$file"
        return 1
    fi
}
