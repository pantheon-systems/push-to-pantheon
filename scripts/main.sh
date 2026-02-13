#!/bin/bash
set -o pipefail

IFS=$'\n\t'

# Define some global variables for colors using ANSI escape codes.
# These work reliably in GitHub Actions without requiring tput or a TTY.
normal='\033[0m'      # Reset
bold='\033[1m'        # Bold
red='\033[0;31m'      # Red
green='\033[0;32m'    # Green
yellow='\033[0;33m'   # Yellow

# Main function to execute the script logic.
function main() {
	help_msg="Usage: bash ./scripts/main.sh <command>
	Available commands:
	- compute_multidev_name: Compute a multidev name for PR or branch-based workflows (respects 11-char limit).
	- get_target_env: Determine the target environment based on the context of the GitHub Actions workflow.
	- check_missing_permissions: Check for missing GitHub permissions and return a list of any that are missing.
	- get_missing_permissions_help: Print a help message with instructions for how to add the missing permissions to your workflow.
	- check_multidev_limit: Check if there are available multidev slots and output availability status.
	- setup_ssh_hostkeys: Set up SSH host keys for Pantheon.
	- prepare_site_root: Prepare the site root by cloning the Pantheon repository, copying files from the specified SITE_ROOT, and setting up the GitHub origin for Build Tools compatibility.
	- verify_build_tools: Verify that the Terminus Build Tools plugin is installed and available.
	- push_to_pantheon: Push code to Pantheon, either via Git or Build Tools depending on configuration and environment state.
	- cleanup: Clean up stale Pantheon multidev environments. This includes environments associated with closed PRs as well as old environments matching a specified pattern.
	- create_multidev: Create a multidev environment from a source environment if it doesn't already exist.
	- delete_multidev: Delete a specific multidev environment and its Git branch.
	"

	if [ -z "$1" ]; then
		echo -e "${red}No command provided.${normal}"
		echo -e "${help_msg}"
		exit 1
	fi

	if [ "$1" == "help" ]; then
		echo -e "${help_msg}"
		exit 0
	fi

	# Check for a valid command.
	if [ "$1" != 'compute_multidev_name' ] && [ "$1" != 'get_target_env' ] && [ "$1" != 'check_missing_permissions' ] && [ "$1" != 'get_missing_permissions_help' ] && [ "$1" != 'check_multidev_limit' ] && [ "$1" != 'setup_ssh_hostkeys' ] && [ "$1" != 'prepare_site_root' ] && [ "$1" != 'push_to_pantheon' ] && [ "$1" != 'cleanup' ] && [ "$1" != 'verify_build_tools' ] && [ "$1" != 'create_multidev' ] && [ "$1" != 'delete_multidev' ]; then
		echo -e "${red}Invalid command: $1${normal}"
		echo -e "${help_msg}"
		exit 1
	fi

	# Execute the command.
	"$1"
}

# Compute a multidev name for PR or branch-based workflows.
# This logic is reused across multiple workflows (BATS tests, deployments, etc.)
# Requires environment variables:
#   MULTIDEV_PREFIX: Prefix for the environment name (e.g., "bats-", "pr-")
#   GITHUB_SHA: Git commit SHA (first 4 chars used for uniqueness)
# Outputs the computed multidev name (respects 11-character Pantheon limit)
function compute_multidev_name() {
	if [ -z "${MULTIDEV_PREFIX}" ]; then
		echo -e "${red}Error: MULTIDEV_PREFIX environment variable is required${normal}"
		exit 1
	fi

	if [ -z "${GITHUB_SHA}" ]; then
		echo -e "${red}Error: GITHUB_SHA environment variable is required${normal}"
		exit 1
	fi

	# Use first 4 characters of commit SHA for uniqueness
	# This prevents race conditions when workflows are canceled and restarted
	# Different commits = different hash = different multidev
	local commit_hash="${GITHUB_SHA:0:4}"

	# Compute multidev name (max 11 chars for Pantheon)
	# Format: {prefix}{hash} (e.g., bats-a1b2, pr-c3d4)
	echo "${MULTIDEV_PREFIX}${commit_hash}"
}

# Function to determine the target environment based on the context of the
# GitHub Actions workflow.
function get_target_env() {
	if [ -n "${INPUT_TARGET_ENV}" ]; then
		TARGET_ENV="${INPUT_TARGET_ENV}"
	elif [ -n "${PR_NUM}" ]; then
		TARGET_ENV="pr-${PR_NUM}"
	elif [ "${GITHUB_REF}" == "refs/heads/main" ] || [ "${GITHUB_REF}" == "refs/heads/master" ]; then
		TARGET_ENV='dev'
	else
		exit 1
	fi

	echo "${TARGET_ENV}"
}

# Check if we have the required permissions by attempting API calls
# This provides helpful error messages if permissions are missing
function check_missing_permissions() {
	MISSING_PERMISSIONS=()

	# Check deployments permission
	DEPLOY_RESPONSE=$(curl -s -w "\n%{http_code}" \
	-H "Authorization: token ${GITHUB_TOKEN}" \
	-H "Accept: application/vnd.github.v3+json" \
	"https://api.github.com/repos/${GITHUB_REPOSITORY}/deployments?per_page=1")
	DEPLOY_HTTP_CODE=$(echo "$DEPLOY_RESPONSE" | tail -n1)

	if [ "$DEPLOY_HTTP_CODE" = "403" ]; then
	MISSING_PERMISSIONS+=("deployments: write")
	fi

	# Check contents permission
	CONTENTS_RESPONSE=$(curl -s -w "\n%{http_code}" \
	-H "Authorization: token ${GITHUB_TOKEN}" \
	-H "Accept: application/vnd.github.v3+json" \
	"https://api.github.com/repos/${GITHUB_REPOSITORY}")
	CONTENTS_HTTP_CODE=$(echo "$CONTENTS_RESPONSE" | tail -n1)

	if [ "$CONTENTS_HTTP_CODE" = "403" ]; then
		MISSING_PERMISSIONS+=("contents: read")
	fi

	# Check pull-requests permission (only if this is a PR event)
	if [ -n "${PR_NUMBER}" ]; then
		PR_RESPONSE=$(curl -s -w "\n%{http_code}" \
			-H "Authorization: token ${GITHUB_TOKEN}" \
			-H "Accept: application/vnd.github.v3+json" \
			"https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}")
		PR_HTTP_CODE=$(echo "$PR_RESPONSE" | tail -n1)

		if [ "$PR_HTTP_CODE" = "403" ]; then
			MISSING_PERMISSIONS+=("pull-requests: read")
		fi
	fi

	echo "${MISSING_PERMISSIONS[@]}"
}

# Check if there are available multidev environment slots.
# Requires environment variables:
#   PANTHEON_SITE: The Pantheon site name
# Outputs to GITHUB_OUTPUT:
#   multidev_available: true/false
#   available_count: number of available slots
# Exit codes:
#   0: Check completed successfully (regardless of availability)
#   1: Error checking multidev limit
function check_multidev_limit() {
	if [ -z "${PANTHEON_SITE}" ]; then
		echo -e "${red}Error: PANTHEON_SITE environment variable is required${normal}"
		exit 1
	fi

	echo -e "${yellow}Checking multidev environment availability...${normal}"

	# Get max multidevs allowed for this site
	local max_multidevs
	if ! max_multidevs=$(terminus site:info "${PANTHEON_SITE}" --field="Max Multidevs" 2>&1); then
		echo -e "${red}Error: Failed to get max multidevs for site${normal}"
		echo -e "${red}${max_multidevs}${normal}"
		exit 1
	fi

	# Count current multidevs (exclude dev, test, live)
	local current_multidevs
	if ! current_multidevs=$(terminus multidev:list "${PANTHEON_SITE}" --format=list 2>&1 | grep -cE -v '^(dev|test|live)$'); then
		echo -e "${red}Error: Failed to count current multidevs${normal}"
		exit 1
	fi

	# Calculate available slots
	local available_count=$((max_multidevs - current_multidevs))

	# Output results
	if [ "$available_count" -gt 0 ]; then
		echo -e "${green}✅ You have ${available_count} multidev environment(s) available.${normal}"
		if [ -n "${GITHUB_OUTPUT}" ]; then
			echo "multidev_available=true" >> "${GITHUB_OUTPUT}"
			echo "available_count=${available_count}" >> "${GITHUB_OUTPUT}"
		fi
	else
		echo -e "${red}❌ Multidev limit reached (${current_multidevs}/${max_multidevs}).${normal}"
		if [ -n "${GITHUB_OUTPUT}" ]; then
			echo "multidev_available=false" >> "${GITHUB_OUTPUT}"
			echo "available_count=0" >> "${GITHUB_OUTPUT}"
		fi
	fi
}

# Function to print a help message with instructions for how to add the missing
# permissions to your workflow.
function get_missing_permissions_help() {
	echo ""
	echo -e "❌ [error]: ${red}Missing required GitHub permissions${normal}"
	echo ""
	echo "The following permissions are missing:"
	for perm in "$@"; do
		echo "  - ${perm}"
	done
	echo ""
	echo "Add the following to your workflow:"
	echo ""
	echo "    permissions:"
	echo "      deployments: write"
	echo "      contents: read"
	echo "      pull-requests: read"
	echo ""
	echo "For more information, see:"
	echo "https://github.com/pantheon-systems/push-to-pantheon#permissions"
	echo ""
}

# Set up SSH host keys for Pantheon.
function setup_ssh_hostkeys() {
	echo -e "${yellow}Adding *.pantheon.io *.drush.in *.getpantheon.com and *.panth.io to known hosts and configuring SSH...${normal}"
	mkdir -p ~/.ssh
	chmod 700 ~/.ssh
	printf "%s" "$SSH_KEY" > ~/.ssh/id_rsa
	chmod 600 ~/.ssh/id_rsa
	{
		echo "Host *.pantheon.io *.drush.in *.getpantheon.com *.panth.io"
		echo "StrictHostKeyChecking no"
		echo "HostKeyAlgorithms +ssh-rsa"
	} >> "$HOME/.ssh/config"
	echo -e "${green}✅ SSH host keys configured.${normal}"
}

# Verify that the Terminus Build Tools plugin is installed and available.
function verify_build_tools() {
	echo -e "${yellow}Verifying Build Tools plugin installation...${normal}"

	# Check if Build Tools plugin is installed
	if terminus self:plugin:list --format=list --field=name | grep -q '^terminus-build-tools-plugin$'; then
		# Get version info
		VERSION=$(terminus self:plugin:list --format=json | grep -A 3 '"name": "terminus-build-tools-plugin"' | grep '"installed_version"' | sed 's/.*": "\(.*\)".*/\1/')
		echo -e "${green}✅ Build Tools plugin is installed (version: ${VERSION})${normal}"
	else
		echo -e "${red}❌ Build Tools plugin installation failed. Plugin not found in plugin list.${normal}"
		echo -e "${red}This is required for deployment. Failing workflow.${normal}"
		exit 1
	fi
}

# Prepare the site root by cloning the Pantheon repository, copying 
# files from the specified SITE_ROOT, and setting up the GitHub origin 
# for Build Tools compatibility.
function prepare_site_root() {
	if [ -n "$SITE_ROOT" ]; then
		echo -e "${yellow}Preparing site from relative path:${normal}${bold} ${SITE_ROOT}${normal}"

		# Get the Pantheon site ID
		SITE_ID=$(terminus site:info "${PANTHEON_SITE}" --field=id)

		# Determine which environment to clone from
		# If target is dev, clone from master; otherwise clone from target or source env
		if [ "$PANTHEON_TARGET_ENV" == "dev" ]; then
			CLONE_BRANCH="master"
		else
			# For multidevs, check if it exists, otherwise use source env
			if terminus multidev:list "${PANTHEON_SITE}" --format=list | grep -q "^${PANTHEON_TARGET_ENV}$"; then
				CLONE_BRANCH="${PANTHEON_TARGET_ENV}"
			else
				# Multidev doesn't exist yet, clone from source env
				# Map standard environments to master branch
				if [ "${PANTHEON_SOURCE_ENV}" == "live" ] || [ "${PANTHEON_SOURCE_ENV}" == "dev" ] || [ "${PANTHEON_SOURCE_ENV}" == "test" ]; then
					CLONE_BRANCH="master"
				else
					CLONE_BRANCH="${PANTHEON_SOURCE_ENV}"
				fi # Source env mapping
			fi # Multidev check
		fi # Target env check

		echo -e "${yellow}Cloning Pantheon repository from branch: ${normal}${bold}${CLONE_BRANCH}${normal}"

		# Create a temporary directory for the Pantheon repo
		PANTHEON_REPO_DIR=$(mktemp -d)

		# Clone the Pantheon repository
		git clone --branch "${CLONE_BRANCH}" \
			"ssh://codeserver.dev.${SITE_ID}@codeserver.dev.${SITE_ID}.drush.in:2222/~/repository.git" \
			"${PANTHEON_REPO_DIR}"

		# Copy files from SITE_ROOT to the Pantheon repo (overwriting)
		echo -e "${yellow}Copying files from ${normal}${bold}${SITE_ROOT}${normal}${yellow} to Pantheon repository${normal}"
		rsync -av --delete --exclude='.git' "${SITE_ROOT}/" "${PANTHEON_REPO_DIR}/"

		# Move into the Pantheon repo directory for subsequent steps
		cd "${PANTHEON_REPO_DIR}" || exit

		# Add the GitHub origin for Build Tools compatibility
		echo -e "${yellow}Setting GitHub origin for Build Tools compatibility${normal}"
		if git remote | grep origin; then
			ORIGIN_URL=$(git remote get-url origin)
			if [[ "$ORIGIN_URL" != https://github.com/* ]]; then
				echo -e "${yellow}Updating origin to GitHub URL${normal}"
				git remote remove origin
				if [ -n "${GITHUB_REPOSITORY}" ]; then
					git remote add origin "https://github.com/${GITHUB_REPOSITORY}"
				fi
			fi
		else
			echo -e "${yellow}Adding origin to GitHub URL${normal}"
			if [ -n "${GITHUB_REPOSITORY}" ]; then
				git remote add origin "https://github.com/${GITHUB_REPOSITORY}"
			fi
		fi

		# Stage all changes
		git add -A

		# Export the Pantheon repo path for the next step
		echo "PANTHEON_REPO_DIR=${PANTHEON_REPO_DIR}" >> "$GITHUB_ENV"

	else
		git fetch --unshallow origin
	fi	
}

# Push code to Pantheon, either via Git or Build Tools depending on
# configuration and environment state.
function push_to_pantheon() {
	# If relative_site_root was used, change to the cloned Pantheon repo directory
	if [ -n "$PANTHEON_REPO_DIR" ]; then
		cd "${PANTHEON_REPO_DIR}" || exit
	fi

	# If SKIP_BUILD_TOOLS is true or live environment doesn't exist, push via Git. Otherwise, use Build Tools to create the environment.
	if [ "$SKIP_BUILD_TOOLS" == "true" ] || [ "$LIVE_ENV_EXISTS" == "false" ]; then
		SITE_ID=$(terminus site:info "${PANTHEON_SITE}" --field=id)

		# Are we pushing to a multidev or to dev?
		if [ "$PANTHEON_TARGET_ENV" == "dev" ]; then
			PANTHEON_DESTINATION_BRANCH="master"
			echo -e "${yellow}Target environment is dev, pushing to 'master' branch on Pantheon.${normal}"
		else
			PANTHEON_DESTINATION_BRANCH="${PANTHEON_TARGET_ENV}"
			echo -e "${yellow}Target environment is ${normal}${bold}${PANTHEON_TARGET_ENV}${normal}${yellow}, pushing to branch with the same name on Pantheon.${normal}"

			# Create multidev if it doesn't exist (reuse create_multidev logic)
			export MULTIDEV_NAME="${PANTHEON_TARGET_ENV}"
			export SOURCE_ENV="${PANTHEON_SOURCE_ENV}"
			create_multidev
		fi

		# Ensure repo is not shallow; Pantheon rejects shallow pushes
		if git rev-parse --is-shallow-repository >/dev/null 2>&1 && [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
			echo -e "${bold}Repository is shallow; unshallowing before push.${normal}"
			git fetch --unshallow origin || git fetch --depth=1000000 origin
		fi

		# Commit staged changes if any (from relative_site_root preparation)
		if ! git diff --cached --quiet; then
			git commit -m "${PANTHEON_COMMIT_MESSAGE}"
		fi

		# Add pantheon remote if it doesn't exist
		if ! git remote | grep -q pantheon; then
			git remote add pantheon "ssh://codeserver.dev.${SITE_ID}@codeserver.dev.${SITE_ID}.drush.in:2222/~/repository.git"
		fi

		# Push code to Pantheon
		git push pantheon "HEAD:refs/heads/${PANTHEON_DESTINATION_BRANCH}" --force
		exit 0
	fi

	# For all other pushes, use Build Tools.
	if [ -n "${PANTHEON_CLONE_CONTENT_FLAG}" ]; then
		terminus -n build:env:create "${PANTHEON_SITE}.${PANTHEON_SOURCE_ENV}" "${PANTHEON_TARGET_ENV}" --yes --message="${PANTHEON_COMMIT_MESSAGE}" "${PANTHEON_CLONE_CONTENT_FLAG}"
	else
		terminus -n build:env:create "${PANTHEON_SITE}.${PANTHEON_SOURCE_ENV}" "${PANTHEON_TARGET_ENV}" --yes --message="${PANTHEON_COMMIT_MESSAGE}"
	fi
}

# Function to delete a GitHub environment and all of its associated deployments.
# The GitHub API requires that all deployments be deleted before an environment
# can be deleted.
delete_github_environment() {
	local ENV_NAME=$1
	echo -e "${yellow}Cleaning up GitHub environment: ${normal}${bold}${ENV_NAME}${normal}..."

	# Check if the environment exists before trying to delete it.
	if ! gh api "repos/${GITHUB_REPOSITORY}/environments/${ENV_NAME}" > /dev/null 2>&1; then
		echo -e "${red}GitHub environment ${normal}${bold}${ENV_NAME}${normal}${red} does not exist, skipping deletion.${normal}"
		return
	fi

	# Get the list of deployment IDs for the environment.
	DEPLOYMENT_IDS=$(gh api "repos/${GITHUB_REPOSITORY}/deployments?environment=${ENV_NAME}" --jq '.[].id')

	if [ -n "$DEPLOYMENT_IDS" ]; then
		for DEPLOYMENT_ID in $DEPLOYMENT_IDS; do
		echo -e "${yellow}  - Deleting deployment ID ${normal}${bold}${DEPLOYMENT_ID}${normal}${yellow}...${normal}"
		gh api --method POST "repos/${GITHUB_REPOSITORY}/deployments/${DEPLOYMENT_ID}/statuses" -f state='inactive' -f description='Deployment is being deleted.' > /dev/null
		gh api --method DELETE "repos/${GITHUB_REPOSITORY}/deployments/${DEPLOYMENT_ID}"
		done
	else
		echo -e "${red}  - No deployments found for environment ${normal}${bold}${ENV_NAME}${normal}${red}.${normal}"
	fi

	# Finally, delete the environment now that it is empty.
	echo -e "${yellow}  - Deleting environment ${normal}${bold}${ENV_NAME}${normal}${yellow}...${normal}"
	gh api --method DELETE "repos/${GITHUB_REPOSITORY}/environments/${ENV_NAME}"
}

# Clean up stale Pantheon multidev environments. 
# This includes environments associated with closed PRs as well as old 
# environments matching a specified pattern.
function cleanup() {
	if [ -n "$SITE_ROOT" ]; then
		cd "${SITE_ROOT}" || return
	fi

	echo -e "${yellow}Deleting stale Pantheon PR multidev environments...${normal}"
	# This command will find and delete multidev environments that are 
	# associated with closed or merged pull requests.
	terminus build:env:delete:pr "$PANTHEON_SITE" --yes

	# The block below is intended to delete old environments that are not
	# associated with pull requests. This is useful for cleaning up
	# environments created by manual workflows or other automated processes.
	if [ -z "$DELETE_OLD_MULTIDEVS" ] || [ "$DELETE_OLD_MULTIDEVS" != "true" ]; then
		echo -e "${red}delete_old_environments was not set to true. Skipping deletion of old environments...${normal}"
		exit 0
	fi

	# Age threshold in days - only delete environments older than this
	# Default to 14 days if not specified
	AGE_THRESHOLD_DAYS="${MULTIDEV_AGE_THRESHOLD_DAYS:-14}"
	CURRENT_TIMESTAMP=$(date +%s)
	AGE_THRESHOLD_SECONDS=$((AGE_THRESHOLD_DAYS * 86400))
	echo -e "${yellow}Age threshold: ${normal}${bold}${AGE_THRESHOLD_DAYS} days${normal}"

	# List all environments, filter out the standard dev/test/live, find the ones
	# that match our deletion patterns (both legacy and new), and exclude the current target env.
	# Built-in test suite patterns: *-std, *-cont, *-git, *-term, *-adv
	# Legacy manual deploy pattern: wd-*
	# User-specified pattern: $MULTIDEV_DELETE_PATTERN (optional)
	ALL_ENVS=$(terminus env:list "$PANTHEON_SITE" --format=list)

	# Extract the prefix from PANTHEON_TARGET_ENV to protect all concurrent suite environments
	# e.g., "126-mo-std" -> "126-mo", "pr-123-git" -> "pr-123", "0x-term" -> "0x"
	ENV_PREFIX=""
	if [[ "$PANTHEON_TARGET_ENV" =~ ^(.+)-(std|cont|git|term|adv)$ ]]; then
		ENV_PREFIX="${BASH_REMATCH[1]}"
		echo -e "${yellow}Protecting all environments with prefix: ${normal}${bold}${ENV_PREFIX}-*${normal}"
	fi

	# Start with environments matching suite patterns or legacy wd- pattern
	FILTERED_ENVS=$(echo "$ALL_ENVS" \
		| grep -v '^dev$' \
		| grep -v '^test$' \
		| grep -v '^live$' \
		| grep -E '(^wd-|-std$|-cont$|-git$|-term$|-adv$)')

	# If MULTIDEV_DELETE_PATTERN is set, also include environments matching that pattern
	# (excluding pr- environments which are handled by build:env:delete:pr)
	if [ -n "$MULTIDEV_DELETE_PATTERN" ]; then
		PATTERN_ENVS=$(echo "$ALL_ENVS" \
			| grep -v '^dev$' \
			| grep -v '^test$' \
			| grep -v '^live$' \
			| grep "$MULTIDEV_DELETE_PATTERN" \
			| grep -v '^pr-')
		FILTERED_ENVS=$(echo -e "${FILTERED_ENVS}\n${PATTERN_ENVS}" | sort -u)
	fi

	# Exclude the current target environment and all environments with the same prefix
	CANDIDATE_ENVS=$(echo "$FILTERED_ENVS" \
		| grep -v "^${PANTHEON_TARGET_ENV}$")

	# If we have a prefix, exclude all environments starting with that prefix
	if [ -n "$ENV_PREFIX" ]; then
		CANDIDATE_ENVS=$(echo "$CANDIDATE_ENVS" | grep -v "^${ENV_PREFIX}-")
	fi

	# Filter by age and collect environments with their timestamps for sorting
	OLDEST_ENVIRONMENTS=""
	for ENV in $CANDIDATE_ENVS; do
		# Get the last modified timestamp for this environment
		CREATED_TIMESTAMP=$(terminus env:info "${PANTHEON_SITE}.${ENV}" --field=created 2>/dev/null || echo "0")

		# Calculate age in seconds
		AGE_SECONDS=$((CURRENT_TIMESTAMP - CREATED_TIMESTAMP))

		# Only include if older than threshold
		if [ "$AGE_SECONDS" -gt "$AGE_THRESHOLD_SECONDS" ]; then
			AGE_DAYS=$((AGE_SECONDS / 86400))
			echo -e "${yellow}Found old environment: ${normal}${bold}${ENV}${normal}${yellow} (${AGE_DAYS} days old)${normal}"
			# Add to list with timestamp for sorting (format: timestamp env_name)
			OLDEST_ENVIRONMENTS="${OLDEST_ENVIRONMENTS}${CREATED_TIMESTAMP} ${ENV}"$'\n'
		fi
	done

	# Sort by timestamp (oldest first) and extract just the environment names
	OLDEST_ENVIRONMENTS=$(echo "$OLDEST_ENVIRONMENTS" | grep -v '^$' | sort -n | awk '{print $2}')

	# Exit if there are no environments to delete.
	if [ -z "$OLDEST_ENVIRONMENTS" ] ; then
		echo -e "${red}No old environments matching the pattern found to delete.${normal}"
		exit 0
	fi

	# Go ahead and delete the oldest environments.
	for ENV_TO_DELETE in $OLDEST_ENVIRONMENTS; do
		# Use delete_multidev helper function
		export MULTIDEV_NAME="${ENV_TO_DELETE}"
		delete_multidev

		# Also delete GitHub environment if applicable
		if [ -n "$GITHUB_REPOSITORY" ]; then
			delete_github_environment "$ENV_TO_DELETE"
		else
			echo -e "${red}Skipping GitHub deletion for ${normal}${bold}${ENV_TO_DELETE}${normal}${red} — GITHUB_TOKEN or GITHUB_REPOSITORY not set.${normal}"
		fi
	done
}

# Create a multidev environment from a source environment if it doesn't already exist.
# Requires environment variables:
#   PANTHEON_SITE: The Pantheon site name
#   MULTIDEV_NAME: The name of the multidev to create
#   SOURCE_ENV: The source environment to clone from (default: live)
function create_multidev() {
	if [ -z "${PANTHEON_SITE}" ]; then
		echo -e "${red}Error: PANTHEON_SITE environment variable is required${normal}"
		exit 1
	fi

	if [ -z "${MULTIDEV_NAME}" ]; then
		echo -e "${red}Error: MULTIDEV_NAME environment variable is required${normal}"
		exit 1
	fi

	local source_env="${SOURCE_ENV:-live}"

	echo -e "${yellow}Checking if multidev ${normal}${bold}${MULTIDEV_NAME}${normal}${yellow} exists on site ${normal}${bold}${PANTHEON_SITE}${normal}${yellow}...${normal}"

	# Check if multidev already exists
	if terminus multidev:list "${PANTHEON_SITE}" --format=list | grep -q "^${MULTIDEV_NAME}$"; then
		echo -e "${green}✅ Multidev ${normal}${bold}${MULTIDEV_NAME}${normal}${green} already exists.${normal}"
	else
		echo -e "${yellow}Creating multidev ${normal}${bold}${MULTIDEV_NAME}${normal}${yellow} from ${normal}${bold}${source_env}${normal}${yellow}...${normal}"
		terminus multidev:create "${PANTHEON_SITE}.${source_env}" "${MULTIDEV_NAME}" --yes
		echo -e "${green}✅ Multidev ${normal}${bold}${MULTIDEV_NAME}${normal}${green} created successfully.${normal}"
	fi
}

# Delete a specific multidev environment and its Git branch.
# Requires environment variables:
#   PANTHEON_SITE: The Pantheon site name
#   MULTIDEV_NAME: The name of the multidev to delete
function delete_multidev() {
	if [ -z "${PANTHEON_SITE}" ]; then
		echo -e "${red}Error: PANTHEON_SITE environment variable is required${normal}"
		exit 1
	fi

	if [ -z "${MULTIDEV_NAME}" ]; then
		echo -e "${red}Error: MULTIDEV_NAME environment variable is required${normal}"
		exit 1
	fi

	echo -e "${yellow}Deleting multidev ${normal}${bold}${MULTIDEV_NAME}${normal}${yellow} from site ${normal}${bold}${PANTHEON_SITE}${normal}${yellow}...${normal}"

	# Check if multidev exists before trying to delete
	if terminus env:info "${PANTHEON_SITE}.${MULTIDEV_NAME}" > /dev/null 2>&1; then
		terminus env:delete "${PANTHEON_SITE}.${MULTIDEV_NAME}" --delete-branch --yes
		echo -e "${green}✅ Multidev ${normal}${bold}${MULTIDEV_NAME}${normal}${green} deleted successfully.${normal}"
	else
		echo -e "${yellow}Multidev ${normal}${bold}${MULTIDEV_NAME}${normal}${yellow} does not exist, skipping deletion.${normal}"
	fi
}

main "$@"