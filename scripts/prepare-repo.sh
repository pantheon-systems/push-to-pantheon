#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

if [[ -n "${PANTHEON_REPO_LOCATION:-}" ]]; then
  echo "PANTHEON_REPO_LOCATION exists."
else
  export PANTHEON_REPO_LOCATION=$(terminus connection:info ${PANTHEON_SITE}.dev  --field=git_url)
fi

# todo exit with errors if needed env vars are missing.
# $PANTHEON_REPO_LOCATION
# $PANTHEON_TARGET_ENV

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
