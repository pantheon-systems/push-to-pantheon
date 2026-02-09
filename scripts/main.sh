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
	if [ "$1" != 'get_target_env' ] && [ "$1" != 'check_missing_permissions' ] && [ "$1" != 'get_missing_permissions_help' ]; then
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

main "$@"