#!/usr/bin/env bats
# Tests for get_commit_message() function

load helpers/common

setup() {
    common_setup
    load_main_script

    # Clear all environment variables that affect get_commit_message
    unset PANTHEON_COMMIT_MESSAGE
    unset PR_NUM
    unset GITHUB_REF
}

teardown() {
    common_teardown
}

@test "get_commit_message: PANTHEON_COMMIT_MESSAGE set returns that value" {
    export PANTHEON_COMMIT_MESSAGE="Custom commit message"

    run get_commit_message
    assert_success
    [ "$output" = "Custom commit message" ]
}

@test "get_commit_message: PR_NUM set returns PR deployment message" {
    export PR_NUM="123"

    run get_commit_message
    assert_success
    [ "$output" = "Deploy PR #123 to Pantheon" ]
}

@test "get_commit_message: PANTHEON_COMMIT_MESSAGE takes precedence over PR_NUM" {
    export PANTHEON_COMMIT_MESSAGE="Override message"
    export PR_NUM="123"

    run get_commit_message
    assert_success
    [ "$output" = "Override message" ]
}

@test "get_commit_message: GITHUB_REF set returns branch deployment message" {
    export GITHUB_REF="refs/heads/feature-branch"

    run get_commit_message
    assert_success
    [ "$output" = "Deploy feature-branch to Pantheon" ]
}

@test "get_commit_message: PR_NUM takes precedence over GITHUB_REF" {
    export PR_NUM="456"
    export GITHUB_REF="refs/heads/main"

    run get_commit_message
    assert_success
    [ "$output" = "Deploy PR #456 to Pantheon" ]
}

@test "get_commit_message: main branch returns main deployment message" {
    export GITHUB_REF="refs/heads/main"

    run get_commit_message
    assert_success
    [ "$output" = "Deploy main to Pantheon" ]
}

@test "get_commit_message: master branch returns master deployment message" {
    export GITHUB_REF="refs/heads/master"

    run get_commit_message
    assert_success
    [ "$output" = "Deploy master to Pantheon" ]
}

@test "get_commit_message: no env vars returns generic message" {
    run get_commit_message
    assert_success
    # When GITHUB_REF is empty, it should strip "refs/heads/" prefix from empty string
    [ "$output" = "Deploy  to Pantheon" ]
}

# --- multiline / metacharacter handling (issue #173) ---
#
# These live here rather than in 08-push_pantheon.bats because they are about what
# happens to the commit message, and because they need no Pantheon credentials — so
# they run in the fast job on every PR.

@test "get_commit_message: preserves newlines in PANTHEON_COMMIT_MESSAGE" {
    export PANTHEON_COMMIT_MESSAGE="$(printf 'Deploy main to Pantheon\n\nSource-Commit: f1cb9d85d8e0\nCI-Run: 42')"

    run get_commit_message
    assert_success
    [ "$output" = "$(printf 'Deploy main to Pantheon\n\nSource-Commit: f1cb9d85d8e0\nCI-Run: 42')" ]
}

@test "get_commit_message: preserves shell metacharacters" {
    export PANTHEON_COMMIT_MESSAGE='Fix "login" $(id) `id` back\slash'

    run get_commit_message
    assert_success
    [ "$output" = 'Fix "login" $(id) `id` back\slash' ]
}

@test "action.yml: commit message output uses the heredoc form, not key=value" {
    # The single-line form makes the runner read line two of a multiline message as a
    # new key and abort with "Invalid format".
    run grep -n 'echo "message=' "${BATS_TEST_DIRNAME}/../action.yml"
    assert_failure

    run grep -c 'echo "message<<' "${BATS_TEST_DIRNAME}/../action.yml"
    assert_success
}

@test "push_to_pantheon: commit message reaches terminus as one argument, unexecuted" {
    local stub_dir="${TEST_TEMP_DIR}/bin"
    local sentinel="${TEST_TEMP_DIR}/INJECTED"
    mkdir -p "${stub_dir}"

    cat > "${stub_dir}/terminus" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "${ARGV_LOG}"
STUB
    chmod +x "${stub_dir}/terminus"

    export ARGV_LOG="${TEST_TEMP_DIR}/argv.log"
    export PATH="${stub_dir}:${PATH}"
    export PANTHEON_SITE="mysite"
    export PANTHEON_SOURCE_ENV="live"
    export PANTHEON_TARGET_ENV="pr-9"
    export SKIP_BUILD_TOOLS="false"
    export LIVE_ENV_EXISTS="true"
    export PANTHEON_COMMIT_MESSAGE="Deploy \"main\"
Note: \$(touch ${sentinel}) \`touch ${sentinel}\`"

    run bash -c 'source <(sed "$ d" scripts/main.sh) && push_to_pantheon 2>&1 | head -20'
    assert_success

    # The command substitutions embedded in the message must never have run.
    [ ! -e "${sentinel}" ]

    # The whole message must arrive as a single --message= argument.
    assert_file_contains "${ARGV_LOG}" '--message=Deploy "main"'
    assert_file_contains "${ARGV_LOG}" "Note: \$(touch ${sentinel})"
}
