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
	- get_commit_message: Generate a context-appropriate commit message for Pantheon deployments.
	- get_target_env: Determine the target environment based on the context of the GitHub Actions workflow.
	- sanitize_pantheon_env_name: Normalise a branch name into a usable Pantheon environment name.
	- resolve_branch_env_name: Resolve the environment name for a branch, avoiding names another branch owns.
	- get_env_owner_branch: Print the branch that owns an environment, if any.
	- validate_pantheon_env_name: Check a name against Pantheon's environment naming rules.
	- get_branch_name: Print the pull request source branch, or the pushed ref.
	- check_missing_permissions: Check for missing GitHub permissions and return a list of any that are missing.
	- get_missing_permissions_help: Print a help message with instructions for how to add the missing permissions to your workflow.
	- check_multidev_limit: Check if there are available multidev slots and output availability status.
	- setup_ssh_hostkeys: Set up SSH host keys for Pantheon.
	- prepare_site_root: Prepare the site root by cloning the Pantheon repository, copying files from the specified SITE_ROOT, and setting up the GitHub origin for Build Tools compatibility.
	- verify_build_tools: Verify that the Terminus Build Tools plugin is installed and available.
	- push_to_pantheon: Push code to Pantheon, either via Git or Build Tools depending on configuration and environment state.
	- cleanup: Clean up stale Pantheon multidev environments. This includes environments associated with closed PRs as well as old environments matching a specified pattern.
	- cleanup_closed_pr_multidevs: Delete pr-* multidevs whose pull request is closed (workaround for terminus-build-tools-plugin#505).
	- resolve_github_environments: Print the GitHub deployment environment(s) that belong to a Pantheon multidev.
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
	if [ "$1" != 'compute_multidev_name' ] && [ "$1" != 'sanitize_pantheon_env_name' ] && [ "$1" != 'resolve_branch_env_name' ] && [ "$1" != 'get_env_owner_branch' ] && [ "$1" != 'validate_pantheon_env_name' ] && [ "$1" != 'get_branch_name' ] && [ "$1" != 'get_commit_message' ] && [ "$1" != 'get_target_env' ] && [ "$1" != 'check_missing_permissions' ] && [ "$1" != 'get_missing_permissions_help' ] && [ "$1" != 'check_multidev_limit' ] && [ "$1" != 'setup_ssh_hostkeys' ] && [ "$1" != 'prepare_site_root' ] && [ "$1" != 'push_to_pantheon' ] && [ "$1" != 'cleanup' ] && [ "$1" != 'cleanup_closed_pr_multidevs' ] && [ "$1" != 'resolve_github_environments' ] && [ "$1" != 'verify_build_tools' ] && [ "$1" != 'create_multidev' ] && [ "$1" != 'delete_multidev' ]; then
		echo -e "${red}Invalid command: $1${normal}"
		echo -e "${help_msg}"
		exit 1
	fi

	# Execute the command with any additional arguments
	COMMAND="$1"
	shift
	"$COMMAND" "$@"
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

# Generate a context-appropriate commit message for Pantheon deployments.
# Uses PANTHEON_COMMIT_MESSAGE if set, otherwise generates a message based on
# the deployment context (PR number or branch name).
# Requires environment variables:
#   PANTHEON_COMMIT_MESSAGE: Custom commit message (optional)
#   PR_NUM: Pull request number (optional, for PR-based deployments)
#   GITHUB_REF: Git reference (optional, for branch-based deployments)
# Outputs the commit message to use for the Pantheon deployment.
function get_commit_message() {
	# Use custom message if provided
	if [ -n "${PANTHEON_COMMIT_MESSAGE}" ]; then
		echo "${PANTHEON_COMMIT_MESSAGE}"
		return 0
	fi

	# Generate default message based on context
	if [ -n "${PR_NUM}" ]; then
		echo "Deploy PR #${PR_NUM} to Pantheon"
	else
		local branch_name="${GITHUB_REF#refs/heads/}"
		echo "Deploy ${branch_name} to Pantheon"
	fi
}

# Print the rules Pantheon applies to a Multidev environment name.
# https://docs.pantheon.io/guides/multidev/multidev-faq
function get_env_name_requirements() {
	echo "  - all lowercase" >&2
	echo "  - only letters, numbers and hyphens" >&2
	echo "  - starts with a letter or number" >&2
	echo "  - maximum of 11 characters" >&2
	echo "  - not one of Pantheon's reserved names: master, settings, team," >&2
	echo "    support, debug, multidev, multi, files, tags, billing" >&2
}

# Turn an arbitrary branch name into a usable Pantheon environment name.
#
# Branch names routinely contain characters Pantheon rejects and run well past its
# 11 character limit, so they are normalised rather than refused: lowercased, any
# unusable character folded to a hyphen, and trimmed to length.
#
# Note that trimming means long branches sharing a prefix converge on one name --
# "feature/login-a" and "feature/login-b" both become "feature-log". Pantheon's
# limit leaves no way around that; a hash suffix would keep them apart but throw
# away the readability that makes branch naming worth using.
#
# Reserved names are not sanitised. Normalising form is one thing; renaming
# "debug" to something else would be inventing a name the caller did not ask for,
# so those are reported instead.
#
# Parameters:
#   $1: The branch name
# Outputs: A name satisfying Pantheon's rules, or nothing if none can be derived
function sanitize_pantheon_env_name() {
	local name="${1}"

	# Lowercase. Done with tr rather than ${name,,} so this still works under the
	# bash 3.2 that ships with macOS.
	name=$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')

	# Fold anything Pantheon will not accept into a hyphen. This is what turns
	# "feat/102-thing" into "feat-102-thing".
	name=$(printf '%s' "${name}" | tr -c 'a-z0-9-' '-')

	# Collapse the runs of hyphens that folding tends to produce.
	while [ "${name}" != "${name//--/-}" ]; do
		name="${name//--/-}"
	done

	# Must begin with a letter or number.
	name="${name#-}"

	# Pantheon allows at most 11 characters.
	name="${name:0:11}"

	# Trimming can leave a trailing hyphen, which carries no meaning.
	name="${name%-}"

	echo "${name}"
}

# Print the branch that owns a candidate environment, if any.
#
# Every deployment this action starts records its source branch, so the
# deployment history doubles as a register of which branch owns which
# environment. Printing nothing means no branch has claimed the name.
#
# This deliberately only knows about environments this action created. An
# environment made by hand is invisible here and will collide, which is the
# expected outcome for a site being driven by this action.
#
# Parameters:
#   $1: Candidate environment name
# Outputs: The owning branch, or nothing
function get_env_owner_branch() {
	local candidate="${1}"

	# Without a repository or gh there is nothing to consult; treat every name as
	# unclaimed so naming still works locally and in tests.
	if [ -z "${candidate}" ] || [ -z "${GITHUB_REPOSITORY}" ] || ! command -v gh > /dev/null 2>&1; then
		return 0
	fi

	gh api "repos/${GITHUB_REPOSITORY}/deployments?environment=${candidate}&per_page=1" \
		--jq '.[0].payload.source_branch // empty' 2>/dev/null || true
}

# Resolve the environment name for a branch, stepping around names that another
# branch already owns.
#
# Pantheon's 11 character limit means long branches that share a prefix sanitise
# to the same name: "feature/login-a" and "feature/login-b" both reduce to
# "feature-log". Rather than let the second branch deploy over the first, trade
# the last character for a digit -- feature-lo0, feature-lo1, and so on.
#
# The branch's own environment is always reused, so re-pushing a branch does not
# allocate a new one. Ten variants is not many, but sites are commonly capped at
# ten Multidevs, so the digits are not the binding limit.
#
# Parameters:
#   $1: The branch name
# Exit codes:
#   0: Resolved; the name is printed
#   1: No usable name can be derived from the branch
#   2: Every variant is owned by another branch
function resolve_branch_env_name() {
	local branch="${1}"
	local base owner candidate i

	base="$(sanitize_pantheon_env_name "${branch}")"
	if [ -z "${base}" ]; then
		return 1
	fi

	owner="$(get_env_owner_branch "${base}")"
	if [ -z "${owner}" ] || [ "${owner}" = "${branch}" ]; then
		echo "${base}"
		return 0
	fi

	for i in 0 1 2 3 4 5 6 7 8 9; do
		candidate="${base:0:10}${i}"
		owner="$(get_env_owner_branch "${candidate}")"
		if [ -z "${owner}" ] || [ "${owner}" = "${branch}" ]; then
			echo "${candidate}"
			return 0
		fi
	done

	return 2
}

# Check a name against Pantheon's environment naming rules.
#
# The previous check here allowed uppercase, underscores and any length, none of
# which Pantheon accepts, so an invalid name passed validation and then failed at
# Terminus with a much less useful message.
#
# Parameters:
#   $1: The environment name to check
# Exit codes:
#   0: Usable
#   1: Does not satisfy the Multidev naming rules
#   2: Reserved by Pantheon
function validate_pantheon_env_name() {
	local name="${1}"

	# dev, test and live are Pantheon's core environments rather than Multidevs,
	# and the Multidev naming rules do not apply to them.
	case "${name}" in
		dev|test|live)
			return 0
			;;
	esac

	# Pantheon refuses to create environments with these names.
	case "${name}" in
		master|settings|team|support|debug|multidev|multi|files|tags|billing)
			return 2
			;;
	esac

	if [[ ! "${name}" =~ ^[a-z0-9][a-z0-9-]{0,10}$ ]]; then
		return 1
	fi

	return 0
}

# Print the current branch name: the pull request's source branch when there is
# one, otherwise the pushed ref.
function get_branch_name() {
	if [ -n "${GITHUB_HEAD_REF}" ]; then
		echo "${GITHUB_HEAD_REF}"
	elif [ -n "${GITHUB_REF}" ]; then
		echo "${GITHUB_REF#refs/heads/}"
	fi
}

# Function to determine the target environment based on the context of the
# GitHub Actions workflow.
function get_target_env() {
	local strategy="${INPUT_TARGET_ENV_STRATEGY:-pr}"

	case "${strategy}" in
		pr|branch) ;;
		*)
			echo -e "${red}Error: Invalid target_env_strategy '${strategy}'${normal}" >&2
			echo -e "${yellow}Supported values are 'pr' (default) and 'branch'.${normal}" >&2
			exit 1
			;;
	esac

	# Pantheon's Dev environment is fed by the master branch, so there is no
	# Multidev to name for a default-branch push and no strategy to apply.
	# push_to_pantheon() maps 'dev' to a push to that branch.
	if [ "${GITHUB_REF}" == "refs/heads/main" ] || [ "${GITHUB_REF}" == "refs/heads/master" ]; then
		TARGET_ENV='dev'
	elif [ "${strategy}" == 'branch' ]; then
		# The strategy is authoritative once chosen: it overrides target_env rather
		# than only filling in when that is blank, so selecting it is enough to
		# change naming without also having to unset an existing target_env.
		local branch_name
		branch_name="$(get_branch_name)"
		if [ -z "${branch_name}" ]; then
			echo -e "${red}Error: Could not determine the branch name${normal}" >&2
			echo -e "${yellow}target_env_strategy is 'branch' but neither GITHUB_HEAD_REF nor GITHUB_REF is set.${normal}" >&2
			exit 1
		fi

		TARGET_ENV="$(resolve_branch_env_name "${branch_name}")"
		case "$?" in
			1)
				echo -e "${red}Error: Could not derive an environment name from branch '${branch_name}'${normal}" >&2
				get_env_name_requirements
				exit 1
				;;
			2)
				echo -e "${red}Error: Every environment name derived from '${branch_name}' is already in use by another branch${normal}" >&2
				echo -e "${yellow}Pantheon allows 11 characters, which leaves ten numbered variants of a${normal}" >&2
				echo -e "${yellow}truncated branch name. Delete an unused Multidev, or use a shorter and more${normal}" >&2
				echo -e "${yellow}distinct branch name.${normal}" >&2
				exit 1
				;;
		esac

		if [ "${TARGET_ENV}" != "${branch_name}" ]; then
			echo -e "${yellow}Branch '${branch_name}' adjusted to '${TARGET_ENV}' to satisfy Pantheon's environment naming rules.${normal}" >&2
		fi
	elif [ -n "${INPUT_TARGET_ENV}" ]; then
		TARGET_ENV="${INPUT_TARGET_ENV}"
	elif [ -n "${PR_NUM}" ]; then
		TARGET_ENV="pr-${PR_NUM}"
	else
		# Previously this exited 1 with no explanation at all.
		echo -e "${red}Error: Could not determine a target environment${normal}" >&2
		echo -e "${yellow}This is not a pull request and the branch is not main or master, so there is${normal}" >&2
		echo -e "${yellow}nothing to derive a name from. Set the target_env input, or set${normal}" >&2
		echo -e "${yellow}target_env_strategy to 'branch' to deploy to a Multidev named after the branch.${normal}" >&2
		exit 1
	fi

	validate_pantheon_env_name "${TARGET_ENV}"
	case "$?" in
		1)
			echo -e "${red}Error: '${TARGET_ENV}' is not a valid Pantheon environment name${normal}" >&2
			get_env_name_requirements
			exit 1
			;;
		2)
			echo -e "${red}Error: '${TARGET_ENV}' is reserved by Pantheon and cannot be used${normal}" >&2
			get_env_name_requirements
			exit 1
			;;
	esac

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
	# Requires pull-requests: write; this GET only confirms read access since
	# there's no non-mutating way to probe for write.
	if [ -n "${PR_NUMBER}" ]; then
		PR_RESPONSE=$(curl -s -w "\n%{http_code}" \
			-H "Authorization: token ${GITHUB_TOKEN}" \
			-H "Accept: application/vnd.github.v3+json" \
			"https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}")
		PR_HTTP_CODE=$(echo "$PR_RESPONSE" | tail -n1)

		if [ "$PR_HTTP_CODE" = "403" ]; then
			MISSING_PERMISSIONS+=("pull-requests: write")
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

	# List current multidevs once; we need both the count and the membership test.
	local multidev_list
	if ! multidev_list=$(terminus multidev:list "${PANTHEON_SITE}" --format=list 2>&1); then
		echo -e "${red}Error: Failed to list current multidevs${normal}"
		echo -e "${red}${multidev_list}${normal}"
		exit 1
	fi

	# Redeploying to an environment that already exists consumes no new slot, so a
	# full site is not a reason to stop. Without this, re-pushing to an existing
	# multidev on a site at capacity would abort a deployment that would have worked.
	if [ -n "${PANTHEON_TARGET_ENV}" ] && echo "${multidev_list}" | grep -qx -- "${PANTHEON_TARGET_ENV}"; then
		echo -e "${green}✅ ${normal}${bold}${PANTHEON_TARGET_ENV}${normal}${green} already exists; no new multidev slot required.${normal}"
		if [ -n "${GITHUB_OUTPUT}" ]; then
			echo "multidev_available=true" >> "${GITHUB_OUTPUT}"
			echo "available_count=0" >> "${GITHUB_OUTPUT}"
		fi
		return 0
	fi

	# Count current multidevs (exclude dev, test, live). grep -c exits non-zero when
	# it matches nothing, which is a legitimate count of zero, so do not treat that
	# as a failure.
	local current_multidevs
	current_multidevs=$(echo "${multidev_list}" | grep -cE -v '^(dev|test|live)$' || true)
	current_multidevs=${current_multidevs:-0}

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
	echo "      pull-requests: write"
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
			export SOURCE_ENV="${PANTHEON_SOURCE_ENV}"
			create_multidev "${PANTHEON_TARGET_ENV}"
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
	# If using relative_site_root, commit staged changes first so Build Tools
	# reads the correct commit instead of old Pantheon repo history
	if [ -n "$PANTHEON_REPO_DIR" ] && ! git diff --cached --quiet; then
		echo -e "${yellow}Committing staged changes before Build Tools deployment${normal}"
		git commit -m "${PANTHEON_COMMIT_MESSAGE}"
	fi

	# Debug: Show CI variables that Build Tools should use
	echo -e "${yellow}CI Environment Variables:${normal}"
	echo "CI_COMMIT_SHA=${CI_COMMIT_SHA}"
	echo "CIRCLE_SHA1=${CIRCLE_SHA1}"
	echo "GITHUB_SHA=${GITHUB_SHA}"
	echo "CI_BUILD_URL=${CI_BUILD_URL}"
	echo "CI_PROJECT_USERNAME=${CI_PROJECT_USERNAME}"
	echo "CI_PROJECT_REPONAME=${CI_PROJECT_REPONAME}"
	echo "PR_NUM=${PR_NUM}"
	echo "Current git HEAD SHA: $(git rev-parse HEAD)"

	# Ensure CI variables are exported for Build Tools
	export CI_COMMIT_SHA
	export CIRCLE_SHA1
	export GITHUB_SHA
	export CI_BUILD_URL
	export CI_PROJECT_USERNAME
	export CI_PROJECT_REPONAME

	# Build the terminus command as an argv array rather than a string. The commit
	# message is user-supplied — plenty of workflows pipe a PR title straight into
	# git_commit_message — so a quote, backtick, $ or backslash in it would be a shell
	# metacharacter if this were assembled into a string and eval'd. See issue #173.
	TERMINUS_CMD=(
		terminus -n build:env:create
		"${PANTHEON_SITE}.${PANTHEON_SOURCE_ENV}"
		"${PANTHEON_TARGET_ENV}"
		--yes
		--message="${PANTHEON_COMMIT_MESSAGE}"
	)

	# Deliberately not passing --pr-id. Build Tools posts a "Visit Site" notification
	# whenever it creates a multidev, and --pr-id aims that at the pull request. This
	# action already reports the environment through GitHub Deployments, with the site
	# as the deployment's env_url, so the comment is redundant and adds one PR comment
	# per suite per push. Without --pr-id the notification is aimed at the commit
	# instead, where the Pantheon-side SHA does not exist on GitHub and the resulting
	# 422 is suppressed below.
	#
	# Build Tools has no option to suppress the notification outright -- its --notify
	# option is documented as deprecated and ignored -- so this is the available lever.

	# Add clone-content flag if set
	if [ -n "${PANTHEON_CLONE_CONTENT_FLAG}" ]; then
		TERMINUS_CMD+=("${PANTHEON_CLONE_CONTENT_FLAG}")
	fi

	# Execute the command with output filtering to suppress non-fatal 422 errors
	# Build Tools tries to comment on commits from Pantheon's git history that may not exist in GitHub
	# These produce "422 Unprocessable Entity" errors that are non-fatal and can be safely suppressed
	set +e
	TEMP_LOG=$(mktemp)
	"${TERMINUS_CMD[@]}" 2>&1 | while IFS= read -r line; do
		# Skip lines containing 422 errors about missing commits
		if echo "$line" | grep -q "422 Unprocessable Entity"; then
			echo "$line" >> "$TEMP_LOG"
			continue
		fi
		if echo "$line" | grep -q "No commit found for SHA"; then
			echo "$line" >> "$TEMP_LOG"
			continue
		fi
		# Show all other lines
		echo "$line"
	done
	EXIT_CODE=${PIPESTATUS[0]}
	set -e

	# Notify if we suppressed any 422 errors
	if [ -s "$TEMP_LOG" ]; then
		SUPPRESSED_COUNT=$(grep -c "422 Unprocessable Entity" "$TEMP_LOG" || echo "0")
		if [ "$SUPPRESSED_COUNT" -gt 0 ]; then
			echo ""
			echo -e "${yellow}Note: Suppressed ${SUPPRESSED_COUNT} non-fatal 422 error(s) from Build Tools GitHub API calls${normal}"
		fi
	fi

	rm -f "$TEMP_LOG"

	# Fail if the command failed
	if [ "$EXIT_CODE" -ne 0 ]; then
		exit "$EXIT_CODE"
	fi
}

# Function to delete a GitHub environment and all of its associated deployments.
# The GitHub API requires that all deployments be deleted before an environment
# can be deleted.
# Find the GitHub deployment environments that belong to a Pantheon multidev.
#
# By default the GitHub deployment environment is named after the Pantheon
# environment, so the name alone is enough. The deployment_environment input
# breaks that assumption on purpose -- several sites deploying the same branch
# need distinct GitHub environments or they collide in the pull request timeline.
# Once the names differ, cleanup can no longer find the environment by name and
# would leave it behind for ever.
#
# The action records the mapping in each deployment's payload, so resolve it from
# there. Candidates are pre-filtered by name to keep this to a couple of API calls
# rather than one per environment on the repository.
#
# Parameters:
#   $1: The Pantheon multidev name
# Outputs: newline-separated GitHub environment names (may be empty)
resolve_github_environments() {
	local pantheon_env="${1}"

	if [ -z "${pantheon_env}" ] || [ -z "${GITHUB_REPOSITORY}" ]; then
		return 0
	fi

	# Fast path: an environment named exactly after the multidev. This is the
	# default arrangement, so most cleanups stop here.
	if gh api "repos/${GITHUB_REPOSITORY}/environments/${pantheon_env}" > /dev/null 2>&1; then
		echo "${pantheon_env}"
		return 0
	fi

	local candidates
	candidates=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/environments" \
		--jq '.environments[].name' 2>/dev/null | grep -F -- "${pantheon_env}" || true)

	if [ -z "${candidates}" ]; then
		return 0
	fi

	# Confirm against the payload rather than trusting the name: "pr-11" is a
	# substring of "pr-114", and a site prefix could collide across sites.
	local candidate payload_env payload_site
	local payload
	for candidate in ${candidates}; do
		# Read both fields from one response. Two calls could disagree if either
		# came back empty, and an empty site is treated as a match below, so a
		# single transient failure would claim an environment belonging to another
		# site.
		payload=$(gh api \
			"repos/${GITHUB_REPOSITORY}/deployments?environment=${candidate}&per_page=1" \
			--jq '[.[0].payload.pantheon_env // "", .[0].payload.pantheon_site // ""] | @tsv' 2>/dev/null || true)
		payload_env=$(printf '%s' "${payload}" | cut -f1)
		payload_site=$(printf '%s' "${payload}" | cut -f2)

		if [ "${payload_env}" = "${pantheon_env}" ] &&
			{ [ -z "${PANTHEON_SITE}" ] || [ -z "${payload_site}" ] || [ "${payload_site}" = "${PANTHEON_SITE}" ]; }; then
			echo "${candidate}"
		fi
	done
}

delete_github_environment() {
	local PANTHEON_ENV=$1

	# Callers pass the Pantheon multidev name. The GitHub environment usually shares
	# that name, but not when deployment_environment is set, so resolve it.
	local RESOLVED
	RESOLVED=$(resolve_github_environments "${PANTHEON_ENV}")

	if [ -z "${RESOLVED}" ]; then
		echo -e "${red}No GitHub environment found for ${normal}${bold}${PANTHEON_ENV}${normal}${red}, skipping deletion.${normal}"
		return
	fi

	local ENV_NAME
	for ENV_NAME in ${RESOLVED}; do
		delete_one_github_environment "${ENV_NAME}"
	done
}

# Delete a single GitHub deployment environment and all of its deployments.
# The GitHub API requires that all deployments be deleted before an environment
# can be deleted.
delete_one_github_environment() {
	local ENV_NAME=$1
	echo -e "${yellow}Cleaning up GitHub environment: ${normal}${bold}${ENV_NAME}${normal}..."

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

	# Finally, try to delete the now-empty environment.
	#
	# This usually fails, and that is expected. Deleting an environment needs
	# administration: write, which this action deliberately does not request -- it
	# runs under pull_request_target with fork-authored code, and repository
	# administration is far too much to hand that. Removing the deployments above is
	# the part that matters, because that is what clears the pull request timeline;
	# the empty environment is cosmetic.
	#
	# Report it plainly instead of failing. Previously the API error was neither
	# checked nor surfaced, so every run claimed to delete environments it had not
	# touched.
	echo -e "${yellow}  - Deleting environment ${normal}${bold}${ENV_NAME}${normal}${yellow}...${normal}"
	local delete_error
	if delete_error=$(gh api --method DELETE "repos/${GITHUB_REPOSITORY}/environments/${ENV_NAME}" 2>&1); then
		echo -e "${green}  - Environment ${normal}${bold}${ENV_NAME}${normal}${green} deleted.${normal}"
		return 0
	fi

	echo -e "${yellow}  - Kept environment ${normal}${bold}${ENV_NAME}${normal}${yellow} (its deployments were removed).${normal}"

	# Explain the cause once per run rather than for every environment.
	if [ -z "${GITHUB_ENV_DELETE_EXPLAINED}" ]; then
		echo -e "${yellow}    Deleting a GitHub environment requires administration: write, which this${normal}"
		echo -e "${yellow}    action does not request. Empty environments are left in place by design.${normal}"
		echo -e "${yellow}    API said: ${delete_error}${normal}"
		GITHUB_ENV_DELETE_EXPLAINED=1
	fi
}

# Delete multidevs whose associated pull request is already closed.
#
# Workaround for terminus-build-tools-plugin#505: build:env:delete:pr walks the
# GitHub "list pull requests" endpoint through WebAPI::pagedRequest(), which never
# re-reads the Link header after the first follow-up request and so always stops at
# page 2. On repos with more than ~200 pull requests the older closed PRs are never
# seen, their pr-* multidevs are never deleted, and the site eventually hits its
# multidev cap. See https://github.com/pantheon-systems/push-to-pantheon/issues/172
#
# Rather than paginate the whole repo, we invert the lookup: take the pr-N multidevs
# that actually exist and ask GitHub about those PR numbers directly. That is one API
# call per multidev, bounded by the site's multidev limit, instead of one per page of
# repo history.
#
# Remove this once #512 lands upstream and Build Tools ships a release with the fix.
#
# Parameters:
#   $1: (optional) newline-separated environment list; fetched if omitted
# Requires environment variables:
#   PANTHEON_SITE: The Pantheon site name
#   GITHUB_REPOSITORY: owner/repo used to resolve PR state
#   PANTHEON_TARGET_ENV: The environment being deployed to, never deleted
function cleanup_closed_pr_multidevs() {
	if [ -z "${GITHUB_REPOSITORY}" ]; then
		echo -e "${yellow}Skipping closed-PR sweep — GITHUB_REPOSITORY is not set.${normal}"
		return 0
	fi

	local all_envs="${1}"
	if [ -z "${all_envs}" ]; then
		all_envs=$(terminus multidev:list "${PANTHEON_SITE}" --format=list 2>/dev/null || echo "")
	fi

	local pr_envs
	pr_envs=$(echo "${all_envs}" | grep -E '^pr-[0-9]+$' || true)

	if [ -z "${pr_envs}" ]; then
		echo -e "${yellow}No pr-* multidevs left to check.${normal}"
		return 0
	fi

	echo ""
	echo -e "${yellow}Checking pr-* multidevs Build Tools may have missed...${normal}"

	local stale_envs=""
	local env pr_num pr_state
	for env in ${pr_envs}; do
		if [ "${env}" = "${PANTHEON_TARGET_ENV}" ]; then
			continue
		fi

		pr_num="${env#pr-}"

		if ! pr_state=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${pr_num}" --jq '.state' 2>/dev/null); then
			# A PR we cannot resolve (deleted, transferred, token scope) is not
			# evidence the environment is stale, so leave it alone.
			echo -e "${yellow}  Could not resolve PR #${pr_num} — keeping ${normal}${bold}${env}${normal}${yellow}.${normal}"
			continue
		fi

		if [ "${pr_state}" = "closed" ]; then
			echo -e "${yellow}  PR #${pr_num} is closed — ${normal}${bold}${env}${normal}${yellow} is stale.${normal}"
			stale_envs="${stale_envs}${env}"$'\n'
		fi
	done

	stale_envs=$(echo "${stale_envs}" | grep -v '^$' || true)

	if [ -z "${stale_envs}" ]; then
		echo -e "${green}✅ No stale closed-PR multidevs found.${normal}"
		return 0
	fi

	echo -e "${yellow}Deleting ${normal}${bold}$(echo "${stale_envs}" | wc -l | tr -d ' ')${normal}${yellow} stale closed-PR multidev(s)...${normal}"

	local max_parallel="${CLEANUP_MAX_PARALLEL:-5}"
	local pids=()

	for env in ${stale_envs}; do
		(
			delete_multidev "${env}" || true
			delete_github_environment "${env}" || true
		) &
		pids+=($!)

		if [ ${#pids[@]} -ge "${max_parallel}" ]; then
			wait "${pids[@]}"
			pids=()
		fi
	done

	if [ ${#pids[@]} -gt 0 ]; then
		wait "${pids[@]}"
	fi

	echo -e "${green}✅ Closed-PR sweep complete.${normal}"
}

# Clean up stale Pantheon multidev environments. 
# This includes environments associated with closed PRs as well as old 
# environments matching a specified pattern.
function cleanup() {
	if [ -n "$SITE_ROOT" ]; then
		cd "${SITE_ROOT}" || return
	fi

	# Check early if we should skip cleanup entirely
	# This prevents unnecessary API calls when cleanup is not enabled
	if [ -z "$DELETE_OLD_MULTIDEVS" ] || [ "$DELETE_OLD_MULTIDEVS" != "true" ]; then
		# Still run PR cleanup and current run cleanup, but skip age-based cleanup
		if [ -z "$ENV_PREFIX" ]; then
			echo -e "${red}delete_old_environments was not set to true. Skipping cleanup...${normal}"
			exit 0
		fi
	fi

	# Export CI variables so Build Tools knows which GitHub repo to check
	export CI_PROJECT_USERNAME
	export CI_PROJECT_REPONAME
	export GITHUB_TOKEN

	echo -e "${yellow}Deleting stale Pantheon PR multidev environments...${normal}"
	# This command will find and delete multidev environments that are
	# associated with closed or merged pull requests.
	terminus build:env:delete:pr "$PANTHEON_SITE" --yes

	# Get all multidevs for cleanup operations
	ALL_ENVS=$(terminus multidev:list "${PANTHEON_SITE}" --format=list 2>/dev/null || echo "")

	# Catch the closed-PR multidevs Build Tools leaves behind on repos with a lot of
	# pull request history. See cleanup_closed_pr_multidevs() for the upstream bug.
	cleanup_closed_pr_multidevs "${ALL_ENVS}"

	# Track environments deleted in the current run to exclude them from age-based cleanup
	DELETED_CURRENT_RUN_ENVS=""

	# Always delete test suite environments from the current run when ENV_PREFIX is set
	if [ -n "$ENV_PREFIX" ]; then
		echo ""
		echo -e "${yellow}Cleaning up test environments from current run...${normal}"

		if [ -z "${ALL_ENVS}" ]; then
			echo -e "${yellow}No multidevs found${normal}"
		else
			# Find test suite environments (ending in -std, -cont, -git, -term, -adv)
			TEST_SUITE_ENVS=$(echo "${ALL_ENVS}" | grep -E -- '-(std|cont|git|term|adv)$' || true)

			# Delete environments from this run (regardless of age)
			CURRENT_RUN_ENVS=$(echo "${TEST_SUITE_ENVS}" | grep "^${ENV_PREFIX}-" || true)

			if [ -n "${CURRENT_RUN_ENVS}" ]; then
				# Track these for exclusion from age-based cleanup
				DELETED_CURRENT_RUN_ENVS="${CURRENT_RUN_ENVS}"
				echo ""
				echo -e "${yellow}Deleting environments from current run (${ENV_PREFIX}-*):${normal}"

				# Parallel deletion with max concurrent limit
				MAX_PARALLEL="${CLEANUP_MAX_PARALLEL:-5}"
				PIDS=()

				for env in ${CURRENT_RUN_ENVS}; do
					if [ -n "${env}" ]; then
						echo -e "${yellow}  Deleting ${normal}${bold}${env}${normal}${yellow}...${normal}"

						# Delete in background
						(
							delete_multidev "${env}" || true
						) &
						PIDS+=($!)

						# Wait if we hit the parallel limit
						if [ ${#PIDS[@]} -ge "${MAX_PARALLEL}" ]; then
							wait "${PIDS[@]}"
							PIDS=()
						fi
					fi
				done

				# Wait for remaining background jobs
				if [ ${#PIDS[@]} -gt 0 ]; then
					wait "${PIDS[@]}"
				fi
			else
				echo -e "${yellow}No current run environments found matching ${ENV_PREFIX}-*${normal}"
			fi
		fi
	fi

	# The block below is intended to delete old environments that are not
	# associated with pull requests. This is useful for cleaning up
	# environments created by manual workflows or other automated processes.

	# Refresh ALL_ENVS after current run deletions to avoid checking deleted environments
	echo ""
	echo -e "${yellow}Refreshing environment list after current run cleanup...${normal}"
	ALL_ENVS=$(terminus multidev:list "${PANTHEON_SITE}" --format=list 2>/dev/null || echo "")

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
		| grep -E -- '(^wd-|-std$|-cont$|-git$|-term$|-adv$)')

	# If MULTIDEV_DELETE_PATTERN is set, also include environments matching that pattern
	# (excluding pr- environments which are handled by build:env:delete:pr)
	if [ -n "$MULTIDEV_DELETE_PATTERN" ]; then
		PATTERN_ENVS=$(echo "$ALL_ENVS" \
			| grep -v '^dev$' \
			| grep -v '^test$' \
			| grep -v '^live$' \
			| grep -F "${MULTIDEV_DELETE_PATTERN}" \
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

	# Exclude environments we just deleted in the current run to avoid race conditions
	# where Terminus hasn't updated its list yet
	if [ -n "$DELETED_CURRENT_RUN_ENVS" ]; then
		for deleted_env in $DELETED_CURRENT_RUN_ENVS; do
			CANDIDATE_ENVS=$(echo "$CANDIDATE_ENVS" | grep -v "^${deleted_env}$")
		done
	fi

	# Filter by age and collect environments with their timestamps for sorting
	OLDEST_ENVIRONMENTS=""
	for ENV in $CANDIDATE_ENVS; do
		# Get the last modified timestamp for this environment
		CREATED_TIMESTAMP=$(terminus env:info "${PANTHEON_SITE}.${ENV}" --field=created 2>/dev/null || echo "0")

		# Skip if timestamp is invalid (environment was deleted or doesn't exist)
		if [ "$CREATED_TIMESTAMP" = "0" ] || [ -z "$CREATED_TIMESTAMP" ]; then
			echo -e "${yellow}Skipping ${normal}${bold}${ENV}${normal}${yellow} (invalid or missing timestamp)${normal}"
			continue
		fi

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
		echo ""
		echo -e "${green}✅ No old environments found older than ${AGE_THRESHOLD_DAYS} days. Cleanup complete.${normal}"
		exit 0
	fi

	echo -e "${yellow}Found ${normal}${bold}$(echo "$OLDEST_ENVIRONMENTS" | wc -w | tr -d ' ')${normal}${yellow} old environment(s) to delete${normal}"

	# Go ahead and delete the oldest environments (in parallel)
	MAX_PARALLEL="${CLEANUP_MAX_PARALLEL:-5}"
	PIDS=()

	for ENV_TO_DELETE in $OLDEST_ENVIRONMENTS; do
		# Delete in background
		(
			delete_multidev "${ENV_TO_DELETE}"

			# Also delete GitHub environment if applicable
			if [ -n "$GITHUB_REPOSITORY" ]; then
				delete_github_environment "$ENV_TO_DELETE"
			else
				echo -e "${red}Skipping GitHub deletion for ${normal}${bold}${ENV_TO_DELETE}${normal}${red} — GITHUB_TOKEN or GITHUB_REPOSITORY not set.${normal}"
			fi
		) &
		PIDS+=($!)

		# Wait if we hit the parallel limit
		if [ ${#PIDS[@]} -ge "${MAX_PARALLEL}" ]; then
			wait "${PIDS[@]}"
			PIDS=()
		fi
	done

	# Wait for remaining background jobs
	if [ ${#PIDS[@]} -gt 0 ]; then
		wait "${PIDS[@]}"
	fi

	echo ""
	echo -e "${green}✅ Age-based cleanup complete.${normal}"
}

# Create a multidev environment from a source environment if it doesn't already exist.
# Parameters:
#   $1: MULTIDEV_NAME - The name of the multidev to create
# Requires environment variables:
#   PANTHEON_SITE: The Pantheon site name
#   SOURCE_ENV: The source environment to clone from (default: live)
function create_multidev() {
	local MULTIDEV_NAME="${1}"

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
		if terminus multidev:create "${PANTHEON_SITE}.${source_env}" "${MULTIDEV_NAME}" --yes; then
			echo -e "${green}✅ Multidev ${normal}${bold}${MULTIDEV_NAME}${normal}${green} created successfully.${normal}"
		elif terminus multidev:list "${PANTHEON_SITE}" --format=list | grep -q "^${MULTIDEV_NAME}$"; then
			# Lost a race with something else creating the same environment. The only
			# legitimate reason the create can fail and still leave us in a good state.
			echo -e "${green}✅ Multidev ${normal}${bold}${MULTIDEV_NAME}${normal}${green} now exists; created concurrently.${normal}"
		else
			# Do not soften this. The existence check ran immediately above, so
			# "may already exist" was never a real possibility here -- the create
			# genuinely failed. Reporting it as a note let callers carry on: the BATS
			# workflow's setup step passed without a test environment, and the whole
			# integration suite then ran against an environment that was not there.
			echo -e "${red}❌ Error: failed to create multidev ${normal}${bold}${MULTIDEV_NAME}${normal}${red} from ${normal}${bold}${source_env}${normal}${red}.${normal}"
			exit 1
		fi
	fi
}

# Delete a specific multidev environment and its Git branch.
# Parameters:
#   $1: MULTIDEV_NAME - The name of the multidev to delete
# Requires environment variables:
#   PANTHEON_SITE: The Pantheon site name
function delete_multidev() {
	local MULTIDEV_NAME="${1}"

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