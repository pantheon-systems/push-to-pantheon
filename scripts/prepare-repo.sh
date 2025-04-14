#!/usr/bin/env bash

# This script prepares the local repository in a CI environment for pushing to Pantheon.
# To avoid force pushing, it brings in a history from Pantheon so that in a later step
# we can commit on top of it and push to Pantheon.

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# todo exit with errors if needed env vars are missing.
if [[ -z "${PANTHEON_REPO_LOCATION:-}" ]]; then
  echo "Error: PANTHEON_REPO_LOCATION is not set. It should be set to the Pantheon repository URL."
  exit 1
fi
if [[ -z "${PANTHEON_TARGET_ENV:-}" ]]; then
  echo "Error: PANTHEON_TARGET_ENV is not set."
  exit 1
fi

git remote add pantheon $PANTHEON_REPO_LOCATION

if git ls-remote --exit-code --heads pantheon "$PANTHEON_TARGET_ENV" > /dev/null; then
    echo "the branch already exists in the remote"
else
  git fetch pantheon master
  git push pantheon FETCH_HEAD:refs/heads/$PANTHEON_TARGET_ENV
fi
git fetch pantheon $PANTHEON_TARGET_ENV

# Reset your working directory to match the remote branch
git reset --hard pantheon/$PANTHEON_TARGET_ENV
# Create and switch to a local branch tracking the remote one
# todo, name the branch based on some variable.
git checkout -B temp-build-branch
