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
