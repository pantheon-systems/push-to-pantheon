#!/usr/bin/env bats

# Load the script to test
load '../scripts/setup_mock_repo.sh'

setup() {
    # Create a temporary directory for our test
    export TEMP_DIR="$(mktemp -d)"
}

teardown() {
    # Clean up our temporary directory
    rm -rf "$TEMP_DIR"
}

@test "setup creates a git repository at specified path" {
    run setup_mock_repo "$TEMP_DIR"
    [ "$status" -eq 0 ]
    [ -d "$TEMP_DIR/.git" ]
}

@test "repository has a main branch" {
    run setup_mock_repo "$TEMP_DIR"
    [ "$status" -eq 0 ]
    
    cd "$TEMP_DIR"
    run git branch --list main
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "main" ]]
}

@test "main branch has index.php with expected content" {
    run setup_mock_repo "$TEMP_DIR"
    [ "$status" -eq 0 ]
    
    cd "$TEMP_DIR"
    git checkout main
    [ -f "index.php" ]
    run cat "index.php"
    [[ "${output}" =~ "Hello world" ]]
}

@test "repository has test-pr branch" {
    run setup_mock_repo "$TEMP_DIR"
    [ "$status" -eq 0 ]
    
    cd "$TEMP_DIR"
    run git branch --list test-pr
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "test-pr" ]]
}

@test "test-pr branch contains main's commit and has additional commit" {
    run setup_mock_repo "$TEMP_DIR"
    [ "$status" -eq 0 ]
    
    cd "$TEMP_DIR"
    
    # Get main branch commit
    git checkout main
    MAIN_COMMIT=$(git rev-parse HEAD)
    
    # Check test-pr branch
    git checkout test-pr
    
    # Verify main's commit is in test-pr's history
    run git merge-base --is-ancestor "$MAIN_COMMIT" HEAD
    [ "$status" -eq 0 ]
    
    # Verify test-pr has an additional commit
    run git log --oneline main..test-pr
    [ "$status" -eq 0 ]
    [ -n "$output" ]  # Output should not be empty (indicating at least one commit)
    
    # Verify content is different from main
    run cat "index.php"
    [[ "${output}" =~ "this is a commit on test-pr" ]]
} 