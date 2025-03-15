#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Function to validate environment names
validate_environment_name() {
    local env_name="$1"
    
    # Check if environment name is empty
    if [ -z "$env_name" ]; then
        echo "Error: Environment name cannot be empty"
        return 1
    fi
    
    # Check if environment name contains only allowed characters
    if ! [[ "$env_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Environment name can only contain alphanumeric characters, hyphens, and underscores"
        return 1
    fi
    
    return 0
}

# Function to determine the target environment
set_target_environment() {
    local target_env=""
    
    # Use manual override if provided
    if [ -n "${INPUT_TARGET_ENV:-}" ]; then
        target_env="${INPUT_TARGET_ENV}"
    # Use PR number if available
    elif [ -n "${PR_NUM:-}" ]; then
        target_env="pr-${PR_NUM}"
    # Default to dev for main/master branch
    elif [ "${GITHUB_REF:-}" == "refs/heads/main" ] || [ "${GITHUB_REF:-}" == "refs/heads/master" ]; then
        target_env="dev"
    else
        echo "Error: Unable to determine target environment. Please set INPUT_TARGET_ENV or ensure PR_NUM or GITHUB_REF is available."
        return 1
    fi
    
    # Validate the determined environment name
    if ! validate_environment_name "$target_env"; then
        return 1
    fi
    
    echo "$target_env"
    return 0
}

# Only execute main if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set_target_environment
fi 