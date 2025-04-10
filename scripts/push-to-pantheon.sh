#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

echo "hellooooooooooooo from push to Pantheon"


git remote add pantheon $PANTHEON_REPO_LOCATION
git remote -v


# wrap this in a check for whether or not the remote branch exists.
git fetch pantheon master
git push pantheon FETCH_HEAD:refs/heads/$TARGET_ENV

git fetch

# Reset your working directory to match the remote branch
git reset --hard pantheon/$TARGET_ENV

# Create and switch to a local branch tracking the remote one
git checkout -B $TARGET_ENV --track pantheon/$TARGET_ENV

git add .
git commit -m 'build process for pr-123'
git push pantheon
