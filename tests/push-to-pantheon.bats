#!/usr/bin/env bats

# Source the setup script
load "./test_helper/setup_mock_repos"

setup() {

    ROOT_OF_TESTS_INVOCATION="$(pwd)"
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

@test "simulate a push to pantheon job when Pantheon does not have the target branch" {

    export PANTHEON_REPO_LOCATION=$PANTHEON_DIR
    export TARGET_ENV=pr-123

    run mock_ci_build_process "$CI_DIR"
    [ "$status" -eq 0 ]

    run cat "test.css"
    [[ "${output}" =~ "background-color: #FF0000" ]]

    run $ROOT_OF_TESTS_INVOCATION/scripts/push-to-pantheon.sh
    echo ${output}
    [ "$status" -eq 0 ]

    git add .
    # todo use a variable for the commit message.
    git commit -m 'build process for pr-123'
    git push pantheon temp-build-branch:$TARGET_ENV


    echo "checkout that the pantheon repo contains the built CSS"
    cd $PANTHEON_DIR
    run git show pr-123:test.css
    echo ${output}
    [[ "${output}" =~ "background-color: #FF0000" ]]
}


@test "simulate a push to pantheon job when Pantheon already does have the target branch" {

    export PANTHEON_REPO_LOCATION=$PANTHEON_DIR
    export TARGET_ENV=pr-123

    cd $PANTHEON_DIR
    git checkout -b $TARGET_ENV
    echo "hello world" > test.txt
    git add .
    git commit -m 'adding test.txt'
    git checkout master

    run git show $TARGET_ENV:test.txt
    echo ${output}
    [[ "${output}" =~ "hello world" ]]

    cd $CI_DIR
    run mock_ci_build_process "$CI_DIR"
    [ "$status" -eq 0 ]

    run cat "test.css"
    [[ "${output}" =~ "background-color: #FF0000" ]]


    run $ROOT_OF_TESTS_INVOCATION/scripts/push-to-pantheon.sh
    echo ${output}
    [ "$status" -eq 0 ]

    git add .
    # todo use a variable for the commit message.
    git commit -m 'build process for pr-123'
    git push pantheon temp-build-branch:$TARGET_ENV



    echo "checkout that the pantheon repo contains the built CSS"
    cd $PANTHEON_DIR
    run git show pr-123:test.css
    echo ${output}
    [[ "${output}" =~ "background-color: #FF0000" ]]
}
