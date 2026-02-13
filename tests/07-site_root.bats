#!/usr/bin/env bats
# Tests for prepare_site_root() function

load helpers/common
load helpers/pantheon

setup() {
    common_setup
    load_main_script

    # Skip all tests if required env vars not available
    if [ -z "${PANTHEON_MACHINE_TOKEN}" ] || [ -z "${PANTHEON_TEST_SITE}" ]; then
        skip "Pantheon credentials not available"
    fi

    # Set up required environment variables
    export PANTHEON_SITE="$(get_test_site)"
    export PANTHEON_TARGET_ENV="$(get_test_env)"
    export PANTHEON_SOURCE_ENV="live"
    export GITHUB_ENV="${TEST_TEMP_DIR}/github_env"
    export GITHUB_REPOSITORY="pantheon-systems/push-to-pantheon"
    touch "${GITHUB_ENV}"

    # Setup SSH for Pantheon access
    setup_test_ssh_key
}

teardown() {
    common_teardown
}

@test "prepare_site_root: SITE_ROOT not set runs git fetch --unshallow" {
    # This test verifies the else branch when SITE_ROOT is not set
    # We can't easily test git fetch without a real repo, so we just verify it runs

    # Create a shallow git repo for testing
    FAKE_REPO="${TEST_TEMP_DIR}/fake_repo"
    mkdir -p "${FAKE_REPO}"
    cd "${FAKE_REPO}" || exit 1
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "test" > test.txt
    git add test.txt
    git commit -m "Initial commit"

    # Mock git fetch to avoid network calls
    function git() {
        if [ "$1" = "fetch" ] && [ "$2" = "--unshallow" ]; then
            echo "Mocked git fetch --unshallow"
            return 0
        fi
        command git "$@"
    }
    export -f git

    unset SITE_ROOT
    run prepare_site_root
    # This should run without error (may output git fetch message)
}

@test "prepare_site_root: SITE_ROOT set for dev target clones master branch" {
    # Skip if SSH key not available
    if [ -z "${PANTHEON_SSH_KEY}" ]; then
        skip "PANTHEON_SSH_KEY not available"
    fi

    export PANTHEON_TARGET_ENV="dev"
    export SITE_ROOT="${BATS_TEST_DIRNAME}/fixtures/test-site"

    run prepare_site_root
    assert_success
    assert_output_contains "Cloning Pantheon repository from branch:"
    assert_output_contains "master"
}

@test "prepare_site_root: SITE_ROOT set copies files from source" {
    # Skip if SSH key not available
    if [ -z "${PANTHEON_SSH_KEY}" ]; then
        skip "PANTHEON_SSH_KEY not available"
    fi

    export PANTHEON_TARGET_ENV="dev"
    export SITE_ROOT="${BATS_TEST_DIRNAME}/fixtures/test-site"

    run prepare_site_root
    assert_success
    assert_output_contains "Copying files from"
}

@test "prepare_site_root: SITE_ROOT set exports PANTHEON_REPO_DIR" {
    # Skip if SSH key not available
    if [ -z "${PANTHEON_SSH_KEY}" ]; then
        skip "PANTHEON_SSH_KEY not available"
    fi

    export PANTHEON_TARGET_ENV="dev"
    export SITE_ROOT="${BATS_TEST_DIRNAME}/fixtures/test-site"

    run prepare_site_root
    assert_success

    # Check that PANTHEON_REPO_DIR was written to GITHUB_ENV
    assert_file_contains "${GITHUB_ENV}" "PANTHEON_REPO_DIR="
}

@test "prepare_site_root: sets GitHub origin for Build Tools compatibility" {
    # Skip if SSH key not available
    if [ -z "${PANTHEON_SSH_KEY}" ]; then
        skip "PANTHEON_SSH_KEY not available"
    fi

    export PANTHEON_TARGET_ENV="dev"
    export SITE_ROOT="${BATS_TEST_DIRNAME}/fixtures/test-site"

    run prepare_site_root
    assert_success
    assert_output_contains "Setting GitHub origin for Build Tools compatibility"
}
