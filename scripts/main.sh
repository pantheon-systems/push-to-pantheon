#!/bin/bash
set -o pipefail

IFS=$'\n\t'

# Function to safely call tput
safe_tput() {
  tput "$@" 2>/dev/null
}

# Define some global variables for colors.
normal=$(safe_tput sgr0)
bold=$(safe_tput bold)
red=$(safe_tput setaf 1)
green=$(safe_tput setaf 2)
yellow=$(safe_tput setaf 3)

# Main function to execute the script logic.
function main() {
	help_msg="Usage: bash ./scripts/main.sh <command>
	Available commands:
	- get_target_env: Determine the target environment based on the context of the GitHub Actions workflow.
	- check_missing_permissions: Check for missing GitHub permissions and return a list of any that are missing.
	- get_missing_permissions_help: Print a help message with instructions for how to add the missing permissions to your workflow.
	- setup_ssh_hostkeys: Set up SSH host keys for Pantheon.
	- prepare_site_root: Prepare the site root by cloning the Pantheon repository, copying files from the specified SITE_ROOT, and setting up the GitHub origin for Build Tools compatibility.
	- push_to_pantheon: Push code to Pantheon, either via Git or Build Tools depending on configuration and environment state.
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
	if [ "$1" != 'get_target_env' ] && [ "$1" != 'check_missing_permissions' ] && [ "$1" != 'get_missing_permissions_help' ] && [ "$1" != 'setup_ssh_hostkeys' ] && [ "$1" != 'prepare_site_root' ] && [ "$1" != 'push_to_pantheon' ]; then
		echo -e "${red}Invalid command: $1${normal}"
		echo -e "${help_msg}"
		exit 1
	fi

	# Execute the command.
	"$1"
}

# Function to determine the target environment based on the context of the GitHub Actions workflow.
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

# Function to print a help message with instructions for how to add the missing permissions to your workflow.
function get_missing_permissions_help() {
	echo ""
	echo "❌ ERROR: Missing required GitHub permissions"
	echo ""
	echo "The following permissions are missing:"
	for perm in "$1"; do
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
	echo "Host *.pantheon.io *.drush.in *.getpantheon.com *.panth.io" >> "$HOME/.ssh/config"
	echo "StrictHostKeyChecking no" >> "$HOME/.ssh/config"
	echo "HostKeyAlgorithms +ssh-rsa" >> "$HOME/.ssh/config"
	echo -e "${green}✅ SSH host keys configured.${normal}"	
}

# Prepare the site root by cloning the Pantheon repository, copying files from the specified SITE_ROOT, and setting up the GitHub origin for Build Tools compatibility.
function prepare_site_root() {
	if [ -n "$SITE_ROOT" ]; then
		echo "Preparing site from relative path: ${SITE_ROOT}"

		# Get the Pantheon site ID
		SITE_ID=$(terminus site:info ${PANTHEON_SITE} --field=id)

		# Determine which environment to clone from
		# If target is dev, clone from master; otherwise clone from target or source env
		if [ "$PANTHEON_TARGET_ENV" == "dev" ]; then
			CLONE_BRANCH="master"
		else
			# For multidevs, check if it exists, otherwise use source env
			if terminus multidev:list ${PANTHEON_SITE} --format=list | grep -q "^${PANTHEON_TARGET_ENV}$"; then
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

		echo "Cloning Pantheon repository from branch: ${CLONE_BRANCH}"

		# Create a temporary directory for the Pantheon repo
		PANTHEON_REPO_DIR=$(mktemp -d)

		# Clone the Pantheon repository
		git clone --branch ${CLONE_BRANCH} \
			ssh://codeserver.dev.${SITE_ID}@codeserver.dev.${SITE_ID}.drush.in:2222/~/repository.git \
			${PANTHEON_REPO_DIR}

		# Copy files from SITE_ROOT to the Pantheon repo (overwriting)
		echo "Copying files from ${SITE_ROOT} to Pantheon repository"
		rsync -av --delete --exclude='.git' ${SITE_ROOT}/ ${PANTHEON_REPO_DIR}/

		# Move into the Pantheon repo directory for subsequent steps
		cd ${PANTHEON_REPO_DIR}

		# Add the GitHub origin for Build Tools compatibility
		echo "Setting GitHub origin for Build Tools compatibility"
		if git remote | grep origin; then
			ORIGIN_URL=$(git remote get-url origin)
			if [[ "$ORIGIN_URL" != https://github.com/* ]]; then
				echo "Updating origin to GitHub URL"
				git remote remove origin
				git remote add origin https://github.com/${{ github.repository }}
			fi
		else
			echo "Adding origin to GitHub URL"
			git remote add origin https://github.com/${{ github.repository }}
		fi

		# Stage all changes
		git add -A

		# Export the Pantheon repo path for the next step
		echo "PANTHEON_REPO_DIR=${PANTHEON_REPO_DIR}" >> $GITHUB_ENV

	else
		git fetch --unshallow origin
	fi	
}

# Push code to Pantheon, either via Git or Build Tools depending on configuration and environment state.
function push_to_pantheon() {
	# If relative_site_root was used, change to the cloned Pantheon repo directory
	if [ -n "$PANTHEON_REPO_DIR" ]; then
		cd ${PANTHEON_REPO_DIR}
	fi

	# If SKIP_BUILD_TOOLS is true or live environment doesn't exist, push via Git. Otherwise, use Build Tools to create the environment.
	if [ "$SKIP_BUILD_TOOLS" == "true" ] || [ "$LIVE_ENV_EXISTS" == "false" ]; then
		SITE_ID=$(terminus site:info ${PANTHEON_SITE} --field=id)

		# Are we pushing to a multidev or to dev?
		if [ "$PANTHEON_TARGET_ENV" == "dev" ]; then
			PANTHEON_DESTINATION_BRANCH="master"
			echo "Target environment is dev, pushing to 'master' branch on Pantheon."
		else
			PANTHEON_DESTINATION_BRANCH="${PANTHEON_TARGET_ENV}"
			echo "Target environment is ${PANTHEON_TARGET_ENV}, pushing to branch with the same name on Pantheon."

			# Check if a multidev already exists for this PR.
			if terminus multidev:list ${PANTHEON_SITE} --format=list | grep -q "^${PANTHEON_TARGET_ENV}$"; then
				echo "Multidev environment ${PANTHEON_TARGET_ENV} already exists. Pushing code to existing environment."
			else
				echo "Creating new multidev environment: ${PANTHEON_TARGET_ENV}"
				terminus multidev:create ${PANTHEON_SITE}.${PANTHEON_SOURCE_ENV} ${PANTHEON_TARGET_ENV} --yes
			fi
		fi

		# Ensure repo is not shallow; Pantheon rejects shallow pushes
		if git rev-parse --is-shallow-repository >/dev/null 2>&1 && [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
			echo "Repository is shallow; unshallowing before push."
			git fetch --unshallow origin || git fetch --depth=1000000 origin
		fi

		# Commit staged changes if any (from relative_site_root preparation)
		if ! git diff --cached --quiet; then
			git commit -m "${PANTHEON_COMMIT_MESSAGE}"
		fi

		# Add pantheon remote if it doesn't exist
		if ! git remote | grep -q pantheon; then
			git remote add pantheon ssh://codeserver.dev.${SITE_ID}@codeserver.dev.${SITE_ID}.drush.in:2222/~/repository.git
		fi

		# Push code to Pantheon
		git push pantheon HEAD:refs/heads/${PANTHEON_DESTINATION_BRANCH} --force
		exit 0
	fi

	# For all other pushes, use Build Tools.
	terminus -n build:env:create ${PANTHEON_SITE}.${PANTHEON_SOURCE_ENV} ${PANTHEON_TARGET_ENV} --yes --message="${PANTHEON_COMMIT_MESSAGE}" ${PANTHEON_CLONE_CONTENT_FLAG}	
}

main "$@"