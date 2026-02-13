#!/usr/bin/env bats
# Tests for setup_ssh_hostkeys() function

load helpers/common

setup() {
    common_setup
    load_main_script

    # Create a test SSH key for testing
    export SSH_KEY="-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAtestkey123456789testkey123456789testkey123456789
testkey123456789testkey123456789testkey123456789testkey123456789test
key123456789testkey123456789testkey123456789testkey123456789testkey
-----END RSA PRIVATE KEY-----"
}

teardown() {
    common_teardown
}

@test "setup_ssh_hostkeys: creates .ssh directory with 700 permissions" {
    run setup_ssh_hostkeys
    assert_success
    assert_file_exists "${HOME}/.ssh"
    assert_file_perms "${HOME}/.ssh" "700"
}

@test "setup_ssh_hostkeys: creates id_rsa with SSH_KEY content and 600 permissions" {
    run setup_ssh_hostkeys
    assert_success
    assert_file_exists "${HOME}/.ssh/id_rsa"
    assert_file_perms "${HOME}/.ssh/id_rsa" "600"
    assert_file_contains "${HOME}/.ssh/id_rsa" "BEGIN RSA PRIVATE KEY"
}

@test "setup_ssh_hostkeys: adds Pantheon hosts to config" {
    run setup_ssh_hostkeys
    assert_success
    assert_file_exists "${HOME}/.ssh/config"
    assert_file_contains "${HOME}/.ssh/config" "*.pantheon.io"
    assert_file_contains "${HOME}/.ssh/config" "*.drush.in"
    assert_file_contains "${HOME}/.ssh/config" "*.getpantheon.com"
    assert_file_contains "${HOME}/.ssh/config" "*.panth.io"
}

@test "setup_ssh_hostkeys: config contains StrictHostKeyChecking no" {
    run setup_ssh_hostkeys
    assert_success
    assert_file_contains "${HOME}/.ssh/config" "StrictHostKeyChecking no"
}

@test "setup_ssh_hostkeys: config contains HostKeyAlgorithms +ssh-rsa" {
    run setup_ssh_hostkeys
    assert_success
    assert_file_contains "${HOME}/.ssh/config" "HostKeyAlgorithms +ssh-rsa"
}

@test "setup_ssh_hostkeys: success message displayed" {
    run setup_ssh_hostkeys
    assert_success
    assert_output_contains "SSH host keys configured"
}
