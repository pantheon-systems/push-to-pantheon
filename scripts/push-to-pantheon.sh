#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# todo exit with errors if needed env vars are missing.
# $PANTHEON_REPO_LOCATION
# $TARGET_ENV

git remote add pantheon $PANTHEON_REPO_LOCATION
git remote -v
git fetch pantheon

if git ls-remote --exit-code --heads pantheon "$TARGET_ENV" > /dev/null; then
    echo "the branch already exists in the remote"
else
  git fetch pantheon master
  git push pantheon FETCH_HEAD:refs/heads/$TARGET_ENV
fi

# Reset your working directory to match the remote branch
git reset --hard pantheon/$TARGET_ENV
# Create and switch to a local branch tracking the remote one
# todo, name the branch based on some variable.
git checkout -B temp-build-branch

git add .
# todo use a variable for the commit message.
git commit -m 'build process for pr-123'
git push pantheon temp-build-branch:$TARGET_ENV
