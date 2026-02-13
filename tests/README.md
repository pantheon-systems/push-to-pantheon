# BATS Test Suite for Push to Pantheon

This directory contains the BATS (Bash Automated Testing System) test suite for the `scripts/main.sh` deployment script.

## Overview

The test suite provides comprehensive coverage of all 9 core functions in `scripts/main.sh`:

1. **main()** - Command dispatcher and validation
2. **get_target_env()** - Environment name derivation logic
3. **check_missing_permissions()** - GitHub API permission validation
4. **get_missing_permissions_help()** - Help text generation
5. **setup_ssh_hostkeys()** - SSH configuration for Pantheon
6. **verify_build_tools()** - Terminus Build Tools plugin detection
7. **prepare_site_root()** - Pantheon repo cloning and file sync
8. **push_to_pantheon()** - Main deployment logic
9. **cleanup()** - Stale environment deletion

## Test Strategy

**Integration tests over mocks**: Tests run against real Pantheon and GitHub APIs for maximum confidence. This means tests require valid credentials and may be slower, but catch real-world issues.

**Concurrent execution**: Tests are split into two GitHub Actions jobs that run in parallel:
- **Fast Tests**: Tests 01-04 (no Pantheon infrastructure needed, ~30 seconds)
- **Integration Tests**: Tests 05-09 (requires Terminus and test multidevs, ~2-3 minutes)

Within each job, BATS runs test files concurrently using `--jobs 4`.

**Test isolation**: Each workflow run creates dedicated multidev environments using commit hash for uniqueness:
- Main test environment: `bats-{hash}` (e.g., `bats-a1b2` from commit a1b2...)
- Temp test environments: `tmp1-{hash}` (deleted in 06a), `tmp2-{hash}` (deleted in teardown)
- Created fresh from live at test start
- Deleted in the workflow's cleanup step (pattern-based, runs even if tests fail)
- Unique per commit to prevent race conditions when workflows are canceled

## Running Tests Locally

### Prerequisites

1. **Install BATS**:
   ```bash
   # macOS
   brew install bats-core

   # Ubuntu/Debian
   sudo apt-get install bats

   # From source
   git clone https://github.com/bats-core/bats-core.git
   cd bats-core
   ./install.sh /usr/local
   ```

2. **Install Terminus**:
   ```bash
   curl -O https://raw.githubusercontent.com/pantheon-systems/terminus-installer/master/builds/installer.phar
   php installer.phar install
   ```

3. **Install Terminus Build Tools Plugin**:
   ```bash
   terminus self:plugin:install pantheon-systems/terminus-build-tools-plugin
   ```

4. **Install gh CLI** (for permission tests):
   ```bash
   # macOS
   brew install gh

   # Ubuntu/Debian
   sudo apt-get install gh
   ```

5. **Set up environment variables**:
   ```bash
   export PANTHEON_MACHINE_TOKEN="your-machine-token"
   export PANTHEON_SSH_KEY="$(cat ~/.ssh/id_rsa)"
   export GITHUB_TOKEN="your-github-token"
   export GITHUB_REPOSITORY="pantheon-systems/push-to-pantheon"
   export PANTHEON_TEST_SITE="dtp-nearly-empty-site"
   export PANTHEON_TEST_ENV="bats-local"  # Use a unique name for local testing
   ```

### Run All Tests

```bash
bats tests/*.bats
```

### Run Specific Test File

```bash
# Fast tests (no Pantheon infrastructure)
bats tests/01-main.bats
bats tests/02-get_target_env.bats
bats tests/03-permissions.bats
bats tests/04-ssh_setup.bats

# Integration tests (requires Pantheon)
bats tests/05-build_tools.bats
bats tests/06a-create-from-live.bats
bats tests/06b-create-from-dev.bats
bats tests/06c-validation-and-delete.bats
bats tests/07-site_root.bats
bats tests/08-push_pantheon.bats
bats tests/09-cleanup.bats
```

### Run Specific Test

```bash
bats tests/01-main.bats -f "no arguments"
```

### Verbose Output

```bash
bats tests/*.bats -t
```

## Test Execution Order

Tests are split into two concurrent jobs:

**Fast Tests** (no Pantheon infrastructure):
1. **01-main.bats** - Command dispatcher
2. **02-get_target_env.bats** - Environment logic
3. **03-permissions.bats** - GitHub API permission validation
4. **04-ssh_setup.bats** - SSH configuration

**Integration Tests** (Pantheon infrastructure required, run concurrently with `--jobs 4`):
5. **05-build_tools.bats** - Terminus plugin detection
6. **06a-create-from-live.bats** - Create multidev from live (uses `tmp1-{hash}`)
7. **06b-create-from-dev.bats** - Create multidev from dev (uses `tmp2-{hash}`)
8. **06c-validation-and-delete.bats** - Validation tests (no environment needed)
9. **07-site_root.bats** - Pantheon repo operations
10. **08-push_pantheon.bats** - Full deployment logic
11. **09-cleanup.bats** - Environment cleanup

This structure ensures:
- Fast feedback from simple tests (~30 seconds)
- Concurrent multidev creation for speed (06a, 06b, 06c run simultaneously)
- Total test time reduced by parallel execution
- Each test file is isolated via setup/teardown

## Test Files

### Simple Function Tests (Phase 2)

- **01-main.bats** - Tests command dispatcher
  - No arguments provided
  - Help command
  - Invalid command
  - Valid command execution

- **02-get_target_env.bats** - Tests environment name derivation
  - INPUT_TARGET_ENV priority
  - PR_NUM formatting
  - main/master branch detection
  - Failure cases

- **03-permissions.bats** - Tests permission checking
  - Valid token detection
  - PR permission check
  - Help text formatting

### Medium Complexity Tests (Phase 3)

- **04-ssh_setup.bats** - Tests SSH configuration
  - Directory/file creation
  - File permissions
  - SSH config content
  - Pantheon host configuration

- **05-build_tools.bats** - Tests Build Tools verification
  - Plugin detection
  - Version extraction
  - Not installed handling

- **06a-create-from-live.bats** - Tests multidev creation from live
  - Creates `tmp1-{hash}` from live environment
  - Tests creation and "already exists" logic
  - Runs concurrently with 06b and 06c

- **06b-create-from-dev.bats** - Tests multidev creation from custom source
  - Creates `tmp2-{hash}` from dev environment
  - Tests custom SOURCE_ENV parameter
  - Runs concurrently with 06a and 06c

- **06c-validation-and-delete.bats** - Tests validation and limits
  - Validation tests for create_multidev and delete_multidev (error handling)
  - check_multidev_limit tests
  - No environment creation needed
  - Runs concurrently with 06a and 06b

### Complex Integration Tests (Phase 4)

- **07-site_root.bats** - Tests Pantheon repo preparation
  - Branch selection logic
  - File copying
  - GitHub origin setup
  - PANTHEON_REPO_DIR export

- **08-push_pantheon.bats** - Tests deployment logic
  - Git-only mode (now uses create_multidev)
  - Build Tools mode
  - Branch targeting
  - Multidev creation

- **09-cleanup.bats** - Tests environment cleanup
  - DELETE_OLD_MULTIDEVS flag
  - Age threshold filtering
  - Prefix protection
  - Pattern matching

## Test Helpers

### helpers/common.bash

Shared utilities for all tests:
- `load_main_script()` - Sources main.sh for testing
- `common_setup()` / `common_teardown()` - Test lifecycle
- `assert_success()` / `assert_failure()` - Exit code assertions
- `assert_output_contains()` - Output validation
- `assert_file_exists()` / `assert_file_perms()` - File assertions

### helpers/pantheon.bash

Pantheon-specific helpers:
- `get_test_site()` - Get test site name
- `get_test_env()` - Get test environment name
- `multidev_exists()` - Check multidev existence
- `setup_test_ssh_key()` - Configure SSH from env var

## Test Fixtures

### fixtures/test-site/

Minimal test site for `prepare_site_root()` testing:
- `index.php` - Sample PHP file
- `README.md` - Sample documentation

## CI Integration

Tests run automatically via `.github/workflows/bats-tests.yml`:

- **Triggers**: Pushes/PRs affecting `scripts/**` or `tests/**`
- **Jobs**: Two concurrent jobs (Fast Tests and Integration Tests)
- **Environment**: Creates commit hash-based multidevs:
  - Main: `bats-{hash}` (e.g., `bats-a1b2`)
  - Temp: `tmp1-{hash}` (06a), `tmp2-{hash}` (06b)
- **Parallelism**: `--jobs 4` for concurrent test file execution
- **Cleanup**: Pattern-based cleanup in `always()` step (backstop only)
- **Required**: Tests must pass before merging to `0.x` branch

## Writing New Tests

1. **Choose the right test file**: Group related tests by function
2. **Use helpers**: Load `helpers/common` and `helpers/pantheon`
3. **Setup/teardown**: Use `common_setup()` and `common_teardown()`
4. **Skip when needed**: Use `skip "reason"` if prerequisites missing
5. **Clear assertions**: Use descriptive assertion messages
6. **Test both paths**: Positive and negative test cases

### Example Test

```bash
#!/usr/bin/env bats

load helpers/common

setup() {
    common_setup
    load_main_script

    # Clear any environment variables that might affect tests
    unset REQUIRED_VAR
}

teardown() {
    common_teardown
}

@test "my_function: basic case works" {
    export REQUIRED_VAR="value"

    run my_function
    assert_success
    assert_output_contains "expected output"
}

@test "my_function: fails without required var" {
    # REQUIRED_VAR already unset in setup()

    run my_function
    assert_failure
}
```

## Test Isolation

Each test is isolated to prevent pollution between tests:

**File system isolation:**
- `common_setup()` creates a temporary directory (`TEST_TEMP_DIR`)
- `HOME` is set to the temp directory for SSH config isolation
- All temp files are cleaned up in `common_teardown()`

**Environment variable isolation:**
- `common_teardown()` unsets all test-specific environment variables
- Each test's `setup()` should explicitly unset variables before setting them
- This ensures no variables leak between tests

**Pantheon environment isolation:**
- All tests in a workflow run share one PR-specific multidev (e.g., `bats-123`)
- Multidev is created fresh from live at workflow start
- Multidev is deleted at workflow end (runs even if tests fail)
- Different PRs get different multidevs, enabling concurrent test runs

**Execution order:**
- Tests run serially (BATS default), not in parallel
- Numbered prefixes ensure logical order (simple → complex)
- Each test should be independent and not rely on previous test state

## Troubleshooting

### Tests fail locally but pass in CI

- Check environment variables are set correctly
- Verify Terminus and plugins are installed
- Ensure test multidev exists and is accessible

### Permission denied errors

- Check PANTHEON_SSH_KEY is set and valid
- Verify SSH key has access to dtp-nearly-empty-site
- Ensure file permissions in test temp dir

### Multidev conflicts

- Use unique PANTHEON_TEST_ENV locally
- CI uses `bats-{pr-num}` or `bats-{branch}` automatically
- Check multidev doesn't exist before running tests

## Contributing

When adding new functionality to `scripts/main.sh`:

1. Write tests FIRST (TDD approach recommended)
2. Add both positive and negative test cases
3. Use integration tests (real Pantheon/GitHub calls)
4. Run tests locally before pushing
5. Verify tests pass in CI

## Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [Terminus Documentation](https://pantheon.io/docs/terminus)
- [GitHub Actions Documentation](https://docs.github.com/actions)
