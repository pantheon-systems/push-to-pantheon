#!/usr/bin/env bats

# Source the setup script
load "./test_helper/setup_mock_repos"

setup() {
    # Create temporary directories for testing
    GITHUB_DIR="$(mktemp -d)"
    PANTHEON_DIR="$(mktemp -d)"
    CI_DIR="$(mktemp -d)"
    # LOG_FILE="$(mktemp)"

    # Set up mock repositories
    setup_mock_repos "$GITHUB_DIR" "$PANTHEON_DIR" "$CI_DIR"
}

# teardown() {
    # Clean up temporary directories
    # rm -rf "$GITHUB_DIR" "$PANTHEON_DIR" "$CI_DIR" "$LOG_FILE"
# }

@test "simulate a push to pantheon job" {
    # Run the script

    run mock_ci_build_process "$CI_DIR"
    [ "$status" -eq 0 ]
    run cat "test.css"
    [[ "${output}" =~ "background-color: #FF0000" ]]    
    

    # run push-to-pantheon
    # set a numeric PR env var

    # absolute paths aren't a good idea.
    export PANTHEON_REPO_LOCATION=$PANTHEON_DIR
    run /workspaces/push-to-pantheon/scripts/push-to-pantheon.sh
    # echo ${output}
    [ "$status" -eq 0 ]

        # check that pantheon repo contains the CSS file in the expected branch.
        # check that the pantheon repo contains expected commits. For some definition of expected commits.

    cd $PANTHEON_DIR
    run git log pr-123
    # echo ${output}
    [ "$status" -eq 0 ]

    run git show pr-123:test.css
    echo ${output}
    [[ "${output}" =~ "background-color: #FF0000" ]] 



    # Check if the log contains the start message
    # grep -q "Starting build process" "$LOG_FILE"
}

