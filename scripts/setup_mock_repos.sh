#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

setup_mock_github_repo() {
    local repo_path="$1"

    # Create and initialize the repository
    mkdir -p "$repo_path"
    cd "$repo_path"
    git init -b main
    
    # Create and commit index.php on main branch
    echo '<?php echo "Hello world"; ?>' > index.php
    git add index.php
    git config --local user.email "test@example.com"
    git config --local user.name "Test User"
    git commit -m "Initial commit with Hello World"
    
    # Create test-pr branch
    git checkout -b test-pr
    
    # Modify and commit changes on test-pr branch
    echo '<?php
    echo "Hello world";
    echo "this is a commit on test-pr";
    ?>' > index.php
    git add index.php
    git commit -m "Add additional echo statement in the branch test-pr"

    return 0
}

setup_mock_pantheon_repo() {
    local repo_path="$1"
    local github_repo_path="$2"

    # Create and initialize the repository
    mkdir -p "$repo_path"
    cd "$repo_path"
    git init -b master
    
    # Configure git user for this repo
    git config --local user.email "test@example.com"
    git config --local user.name "Test User"

    # Add GitHub repo as a remote to get its history
    git remote add github "$github_repo_path"
    git fetch github

    # Reset master to GitHub's main branch
    git reset --hard github/main

    # Remove the remote to keep repos separate
    git remote remove github

    return 0
}

setup_mock_repos() {
    local github_path="$1"
    local pantheon_path="$2"

    setup_mock_github_repo "$github_path"
    setup_mock_pantheon_repo "$pantheon_path" "$github_path"

    # Additional setup for shared history will go here
    return 0
}

# Only execute main if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_mock_repos "$1" "$2"
fi 