#!/usr/bin/env bats
# Tests for the clone_files / clone_database inputs of create_multidev() (issue #198).
#
# These stub `terminus` so they can assert the exact multidev:create arguments
# without creating real environments. Real creation is covered in 06a and 06b.

load helpers/common

setup() {
    common_setup
    load_main_script

    export PANTHEON_SITE="my-site"
    export SOURCE_ENV="live"
    unset PANTHEON_CLONE_FILES PANTHEON_CLONE_DATABASE

    CALLS="${TEST_TEMP_DIR}/terminus_calls"
    : > "${CALLS}"
    export CALLS

    # Records each call. multidev:list returns no environments, so
    # create_multidev always takes the creation path.
    terminus() {
        local IFS=' '
        echo "$*" >> "${CALLS}"
        return 0
    }
}

teardown() {
    unset PANTHEON_CLONE_FILES PANTHEON_CLONE_DATABASE SOURCE_ENV
    common_teardown
}

create_call() {
    grep '^multidev:create ' "${CALLS}"
}

@test "create_multidev: clones database and files by default" {
    run create_multidev "pr-1"
    assert_success
    [ "$(create_call)" = "multidev:create my-site.live pr-1 --yes" ]
}

@test "create_multidev: explicit true values keep the default behavior" {
    export PANTHEON_CLONE_FILES="true"
    export PANTHEON_CLONE_DATABASE="true"
    run create_multidev "pr-1"
    assert_success
    [ "$(create_call)" = "multidev:create my-site.live pr-1 --yes" ]
}

@test "create_multidev: clone_files false passes --no-files" {
    export PANTHEON_CLONE_FILES="false"
    run create_multidev "pr-1"
    assert_success
    [ "$(create_call)" = "multidev:create my-site.live pr-1 --no-files --yes" ]
    assert_output_contains "Not cloning from"
    assert_output_contains "files"
}

@test "create_multidev: both false report database and files as skipped" {
    export PANTHEON_CLONE_FILES="false"
    export PANTHEON_CLONE_DATABASE="false"
    run create_multidev "pr-1"
    assert_success
    assert_output_contains "database and files"
}

@test "create_multidev: clone_database false passes --no-db" {
    export PANTHEON_CLONE_DATABASE="false"
    run create_multidev "pr-1"
    assert_success
    [ "$(create_call)" = "multidev:create my-site.live pr-1 --no-db --yes" ]
}

@test "create_multidev: both false pass --no-db and --no-files" {
    export PANTHEON_CLONE_FILES="false"
    export PANTHEON_CLONE_DATABASE="false"
    run create_multidev "pr-1"
    assert_success
    [ "$(create_call)" = "multidev:create my-site.live pr-1 --no-db --no-files --yes" ]
}

@test "create_multidev: flags are not used when the multidev already exists" {
    export PANTHEON_CLONE_FILES="false"
    terminus() {
        local IFS=' '
        echo "$*" >> "${CALLS}"
        if [ "$1" = "multidev:list" ]; then
            echo "pr-1"
        fi
        return 0
    }
    run create_multidev "pr-1"
    assert_success
    assert_output_contains "already exists"
    [ -z "$(create_call)" ]
}
