#!/bin/bash
# Pantheon-specific test helpers

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
    terminus multidev:list "${site}" --format=list | grep -q "^${env}$"
}

# Get Pantheon site ID
get_site_id() {
    local site="$1"
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
