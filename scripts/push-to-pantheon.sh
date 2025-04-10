#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

echo "hellooooooooooooo from push to Pantheon"

git checkout -b pr-123
git remote add pantheon $PANTHEON_REPO_LOCATION
git remote -v
git add .
git commit -m 'build process for pr-123'
git push pantheon

