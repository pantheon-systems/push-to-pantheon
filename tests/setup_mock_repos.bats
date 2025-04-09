#!/usr/bin/env bats

# Load the script to test
load '../scripts/setup_mock_repos'

setup() {
    # Create temporary directories for our tests
    export GITHUB_DIR="$(mktemp -d)"
    export PANTHEON_DIR="$(mktemp -d)"
    export CI_DIR="$(mktemp -d)"
}

teardown() {
    # Clean up temporary directories
    rm -rf "$GITHUB_DIR"
    rm -rf "$PANTHEON_DIR"
    rm -rf "$CI_DIR"
}

@test "setup creates a git repository at specified path" {
    run setup_mock_github_repo "$GITHUB_DIR"
    [ "$status" -eq 0 ]
    [ -d "$GITHUB_DIR/.git" ]
}

@test "repository has a main branch" {
    run setup_mock_github_repo "$GITHUB_DIR"
    [ "$status" -eq 0 ]
    
    cd "$GITHUB_DIR"
    run git branch --list main
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "main" ]]
}

@test "main branch has index.php with expected content" {
    run setup_mock_github_repo "$GITHUB_DIR"
    [ "$status" -eq 0 ]
    
    cd "$GITHUB_DIR"
    git checkout main
    [ -f "index.php" ]
    run cat "index.php"
    [[ "${output}" =~ "Hello world" ]]
}

@test "repository has test-pr branch" {
    run setup_mock_github_repo "$GITHUB_DIR"
    [ "$status" -eq 0 ]
    
    cd "$GITHUB_DIR"
    run git branch --list test-pr
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "test-pr" ]]
}

@test "test-pr branch contains main's commit and has additional commit" {
    run setup_mock_github_repo "$GITHUB_DIR"
    [ "$status" -eq 0 ]
    
    cd "$GITHUB_DIR"
    
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

@test "setup creates Pantheon repository with master branch" {
    run setup_mock_repos "$GITHUB_DIR" "$PANTHEON_DIR"
    [ "$status" -eq 0 ]
    
    # Check that Pantheon repo exists
    [ -d "$PANTHEON_DIR/.git" ]
    
    cd "$PANTHEON_DIR"
    run git branch --list master
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "master" ]]
}

@test "Pantheon master branch contains GitHub main branch commit" {
    run setup_mock_repos "$GITHUB_DIR" "$PANTHEON_DIR"
    [ "$status" -eq 0 ]
    
    # Get GitHub main branch HEAD commit
    cd "$GITHUB_DIR"
    git checkout main
    GITHUB_MAIN_COMMIT=$(git rev-parse HEAD)
    
    # Check if this commit exists in Pantheon's history
    cd "$PANTHEON_DIR"
    git checkout master
    run git merge-base --is-ancestor "$GITHUB_MAIN_COMMIT" HEAD
    [ "$status" -eq 0 ]
}

@test "CI environment has correct GitHub checkout on test-pr branch" {
    run setup_mock_repos "$GITHUB_DIR" "$PANTHEON_DIR" "$CI_DIR"
    [ "$status" -eq 0 ]
    
    # Check that CI repo exists and is a git repo
    [ -d "$CI_DIR/.git" ]
    
    # Check that we're on test-pr branch
    cd "$CI_DIR"
    run git branch --show-current
    [ "$status" -eq 0 ]
    [[ "${output}" == "test-pr" ]]
    
    # Get the HEAD commit of test-pr branch in GitHub repo
    cd "$GITHUB_DIR"
    git checkout test-pr
    GITHUB_PR_COMMIT=$(git rev-parse HEAD)
    
    # Verify CI repo has the same HEAD commit
    cd "$CI_DIR"
    CI_COMMIT=$(git rev-parse HEAD)
    [ "$GITHUB_PR_COMMIT" = "$CI_COMMIT" ]
} 