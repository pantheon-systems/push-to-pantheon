#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

setup_mock_repos() {
    local github_dir="$1"
    local pantheon_dir="$2"
    local ci_dir="$3"

    # Create GitHub repository
    mkdir -p "$github_dir"
    cd "$github_dir"
    git init
    echo "# GitHub Repository" > README.md
    git add README.md
    git commit -m "Initial commit"

    # Create Pantheon repository
    mkdir -p "$pantheon_dir"
    cd "$pantheon_dir"
    git init
    echo "# Pantheon Repository" > README.md
    git add README.md
    git commit -m "Initial commit"

    # Create CI repository
    mkdir -p "$ci_dir"
    cd "$ci_dir"
    git init
    echo "# CI Repository" > README.md
    git add README.md
    git commit -m "Initial commit"

    # Set up remotes in CI repository
    cd "$ci_dir"
    git remote add github "$github_dir"
    git remote add pantheon "$pantheon_dir"

    return 0
} 