#!/usr/bin/env bash

# This script prepares the local repository in a CI environment for pushing to Pantheon.
# To avoid force pushing, it brings in a history from Pantheon so that in a later step
# we can commit on top of it and push to Pantheon.

# Exit on error, undefined variables, and pipe failures
set -euo pipefail


cat index.php


# todo exit with errors if needed env vars are missing.
if [[ -z "${PANTHEON_REPO_LOCATION:-}" ]]; then
  echo "Error: PANTHEON_REPO_LOCATION is not set. It should be set to the Pantheon repository URL."
  exit 1
fi
if [[ -z "${PANTHEON_TARGET_ENV:-}" ]]; then
  echo "Error: PANTHEON_TARGET_ENV is not set."
  exit 1
fi

# When runnning on the "main" branch, the target environment is "dev" but the
# associated git branch on Pantheon is "master". So that is the branch we need to
# fetch and reset to.
if [[ "$PANTHEON_TARGET_ENV" == "dev" ]]; then
  PANTHEON_TARGET_ENV="master"
fi

git remote add pantheon $PANTHEON_REPO_LOCATION

if git ls-remote --exit-code --heads pantheon "$PANTHEON_TARGET_ENV" > /dev/null; then
    echo "the branch already exists in the remote"
else
  git fetch pantheon master
  git push pantheon FETCH_HEAD:refs/heads/$PANTHEON_TARGET_ENV
fi
git fetch pantheon $PANTHEON_TARGET_ENV

git reset --soft pantheon/"$PANTHEON_TARGET_ENV"
git checkout -b ci-temp-branch
