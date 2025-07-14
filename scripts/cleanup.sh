#!/bin/bash
set +e

# Function to delete a GitHub environment and all of its associated deployments.
# The GitHub API requires that all deployments be deleted before an environment
# can be deleted.
delete_github_environment() {
  local ENV_NAME=$1
  echo "Cleaning up GitHub environment: ${ENV_NAME}..."

  # Check if the environment exists before trying to delete it.
  if ! gh api "repos/${GITHUB_REPOSITORY}/environments/${ENV_NAME}" > /dev/null 2>&1; then
    echo "GitHub environment ${ENV_NAME} does not exist, skipping deletion."
    return
  fi

  # Get the list of deployment IDs for the environment.
  DEPLOYMENT_IDS=$(gh api "repos/${GITHUB_REPOSITORY}/deployments?environment=${ENV_NAME}" --jq '.[].id')

  if [ -n "$DEPLOYMENT_IDS" ]; then
    for DEPLOYMENT_ID in $DEPLOYMENT_IDS; do
      echo "  - Deleting deployment ID ${DEPLOYMENT_ID}..."
      gh api --method POST "repos/${GITHUB_REPOSITORY}/deployments/${DEPLOYMENT_ID}/statuses" -f state='inactive' -f description='Deployment is being deleted.' > /dev/null
      gh api --method DELETE "repos/${GITHUB_REPOSITORY}/deployments/${DEPLOYMENT_ID}"
    done
  else
    echo "  - No deployments found for environment ${ENV_NAME}."
  fi

  # Finally, delete the environment now that it is empty.
  echo "  - Deleting environment ${ENV_NAME}..."
  gh api --method DELETE "repos/${GITHUB_REPOSITORY}/environments/${ENV_NAME}"
}

if [ -n "$SITE_ROOT" ]; then
  cd "${SITE_ROOT}" || return
fi

echo "Deleting stale Pantheon PR multidev environments..."
# This command will find and delete multidev environments that are associated
# with closed or merged pull requests.
terminus build:env:delete:pr "$PANTHEON_SITE" --yes

# The block below is intended to delete old environments that are not associated
# with pull requests. This is useful for cleaning up environments created by
# manual workflows or other automated processes.
if [ -z "$MULTIDEV_DELETE_PATTERN" ] || [ -z "$DELETE_OLD_MULTIDEVS" ] || [ "$DELETE_OLD_MULTIDEVS" != "true" ]; then
  echo "No MULTIDEV_DELETE_PATTERN set or delete_old_environments was not set to true. Skipping deletion of old environments..."
  exit 0
fi

# List all environments, filter out the standard dev/test/live, find the ones
# that match our deletion pattern, and then exclude the most recent one.
ALL_ENVS=$(terminus env:list "$PANTHEON_SITE" --format=list)
OLDEST_ENVIRONMENTS=$(echo "$ALL_ENVS" \
  | grep -v dev \
  | grep -v test \
  | grep -v live \
  | grep "$MULTIDEV_DELETE_PATTERN" \
  | grep -v '^pr-' \
  | sort \
  | sed -e '$d')

# Exit if there are no environments to delete.
if [ -z "$OLDEST_ENVIRONMENTS" ] ; then
  echo "No old environments matching the pattern found to delete."
  exit 0
fi

# Go ahead and delete the oldest environments.
for ENV_TO_DELETE in $OLDEST_ENVIRONMENTS; do
    echo "Deleting Pantheon environment: ${ENV_TO_DELETE}..."
    if terminus env:info "${PANTHEON_SITE}.${ENV_TO_DELETE}" > /dev/null 2>&1; then
        terminus env:delete "${PANTHEON_SITE}.${ENV_TO_DELETE}" --delete-branch --yes
        if [ -n "$GITHUB_REPOSITORY" ]; then
            delete_github_environment "$ENV_TO_DELETE"
        else
            echo "Skipping GitHub deletion for ${ENV_TO_DELETE} — GITHUB_TOKEN or GITHUB_REPOSITORY not set."
        fi
    else
        echo "Pantheon environment ${ENV_TO_DELETE} not found."
    fi
done