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
	if [ "$1" != 'get_target_env' ] && [ "$1" != 'another_command' ]; then
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

main "$@"