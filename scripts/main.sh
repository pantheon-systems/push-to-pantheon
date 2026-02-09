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
	if [ "$1" != 'some_command' ] && [ "$1" != 'another_command' ]; then
		echo -e "${red}Invalid command: $1${normal}"
		echo -e "${help_msg}"
		exit 1
	fi

	# Execute the command.
	"$1"
}

main "$@"