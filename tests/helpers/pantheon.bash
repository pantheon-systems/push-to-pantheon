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
        test_id=$(echo "$(get_test_env)" | sed 's/^bats-//' | cut -c1-3)
    fi

    echo "tmp${test_id}-${suffix}"
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
