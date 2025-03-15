#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

setup_mock_repo() {
    local repo_path="$1"

    # Uncomment and implement each step to make tests pass
    
    # # 1. Create and initialize the repository
    mkdir -p "$repo_path"
    cd "$repo_path"
    git init -b main
    
    # # 2. Create and commit index.php on main branch
    echo '<?php echo "Hello world"; ?>' > index.php
    git add index.php
    git config --local user.email "test@example.com"
    git config --local user.name "Test User"
    git commit -m "Initial commit with Hello World"
    
    # # 3. Create test-pr branch
    git checkout -b test-pr
    
    # # 4. Modify and commit changes on test-pr branch
    echo '<?php
    echo "Hello world";
    echo "this is a commit on test-pr";
    ?>' > index.php
    git add index.php
    git commit -m "Add additional echo statement in the branch test-pr"
    


    return 0
}

# Only execute main if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_mock_repo "$1"
fi 