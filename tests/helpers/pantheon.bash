#!/bin/bash
# Pantheon-specific test helpers

# Authenticate Terminus if not already authenticated
authenticate_terminus() {
    if [ -z "${PANTHEON_MACHINE_TOKEN}" ]; then
        return 0  # Skip if no token available
    fi

    # Check if already authenticated
    if terminus auth:whoami >/dev/null 2>&1; then
        return 0
    fi

    # Authenticate with machine token
    # Don't hide errors - we need to see if this fails
    terminus auth:login --machine-token="${PANTHEON_MACHINE_TOKEN}"

    # Verify authentication succeeded
    if ! terminus auth:whoami >/dev/null 2>&1; then
        echo "ERROR: Terminus authentication failed"
        return 1
    fi
}

# Get the test site name from environment or default
get_test_site() {
    echo "${PANTHEON_TEST_SITE:-dtp-nearly-empty-site}"
}

# Get the test environment name from environment
get_test_env() {
    echo "${PANTHEON_TEST_ENV}"
}

# Generate a unique temporary multidev name for tests
# Takes a suffix number and returns a unique name based on PR/branch context
# Example: get_temp_multidev_name 1 -> "tmp123-1" (if PR #123)
get_temp_multidev_name() {
    local suffix="$1"
    local test_id

    # Use PR number directly if available (most accurate)
    if [ -n "${GITHUB_PR_NUMBER}" ]; then
        test_id="${GITHUB_PR_NUMBER}"
    else
        # Fall back to extracting from test env name
        # (e.g., "123" from "bats-123" or "126" from "bats-126bat")
        test_id=$(get_test_env | sed 's/^bats-//' | cut -c1-3)
    fi

    echo "tmp${test_id}-${suffix}"
}

# Name of the scratch multidev a test file uses, derived from the run's test
# environment so setup() and teardown_file() always agree on it.
#
# teardown_file() runs in a different process context from setup(), so a variable
# assigned in setup() reads as empty there. Deriving the name in both places is what
# makes the cleanup actually fire -- while it did not, every run leaked one of these
# environments and they accumulated until the site hit its multidev cap.
#
# Takes the file's prefix, e.g. "tmp1" -> "tmp1-a1b2" for test env "bats-a1b2".
get_file_multidev_name() {
    local prefix="$1"
    local test_env
    test_env="$(get_test_env)"

    # No test environment means no derived name; callers must treat this as "nothing
    # to do" rather than deleting "<prefix>-".
    if [ -z "${test_env}" ]; then
        return 0
    fi

    echo "${prefix}-${test_env#bats-}"
}

# Check if a multidev environment exists
multidev_exists() {
    local site="$1"
    local env="$2"
    authenticate_terminus
    terminus multidev:list "${site}" --format=list | grep -q "^${env}$"
}

# Get Pantheon site ID
get_site_id() {
    local site="$1"
    authenticate_terminus
    terminus site:info "${site}" --field=id
}

# Setup SSH key from environment variable
setup_test_ssh_key() {
    if [ -n "${PANTHEON_SSH_KEY}" ]; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        printf "%s" "${PANTHEON_SSH_KEY}" > ~/.ssh/id_rsa
        chmod 600 ~/.ssh/id_rsa
    fi
}
