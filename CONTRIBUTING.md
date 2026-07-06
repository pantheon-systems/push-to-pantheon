# Contributing to Push to Pantheon

`0.x` is the current default branch and all feature branches merge into this branch. 

## Cutting a release

Releases are **mostly automated** through GitHub workflows, with one required manual step (signing the release PR's version-bump commit — see step 3 below).

### Automated Release Flow

**1. Merge a PR → Release PR is created automatically**

When any PR is merged to the `0.x` branch, the **Auto Release PR** workflow automatically:
- Creates or updates a draft release PR (labeled `release`)
- Auto-increments the patch version (e.g., `0.8.0` → `0.8.1`)
- Updates all action version references in `readme.md`:
  - `pantheon-systems/push-to-pantheon` → new version being released
  - `actions/checkout` → latest major version
  - `actions/cache` → latest major version

**2. Override version if needed (optional)**

By default, the patch version is incremented. For minor or major bumps:
- **Edit the release PR title** to `Release X.Y.Z` (e.g., `Release 0.9.0`), OR
- **Comment on the release PR** with `/version X.Y.Z` (e.g., `/version 0.9.0`)

The workflow automatically updates the release branch with the new version.

**3. Manually sign the version-bump commit (required)**

The org enforces a `required_signatures` ruleset on `0.x`, but the release PR's version-bump commit is created by automation and is **not** GPG/SSH signed — GitHub only auto-signs commits made via a GitHub App installation token, and this repo's automation authenticates with a personal PAT (`GH_PAT`), which doesn't qualify. This means the release PR will show as blocked (merging disabled) until the commit is manually replaced with a signed one:

```bash
git fetch origin release-X.Y.Z
git checkout release-X.Y.Z
git commit --amend --reset-author -S --no-edit
git push --force-with-lease origin release-X.Y.Z
```

This requires commit signing to be configured locally (`user.signingkey` + `commit.gpgsign true`, or SSH signing). Confirm it worked with `git log -1 --format='%G?'` (should print `G` or `U`, not `N`) before pushing. There is currently no fully-automated way around this step — see the PR discussion on [#165](https://github.com/pantheon-systems/push-to-pantheon/pull/165) for why (GitHub App-based signing was considered but not pursued).

**4. Merge release PR → Draft release is created**

When you merge the release PR:
1. Mark the draft PR as **Ready for review**
2. Review and approve
3. Merge to `0.x`
4. The **Create Release** workflow automatically:
   - Creates a git tag
   - Creates a **draft GitHub release** with auto-generated notes
   - Comments on the merged PR with a link to the release

**5. Publish the release**

Navigate to the [Releases page](https://github.com/pantheon-systems/push-to-pantheon/releases) and:
1. Review the draft release notes
2. Edit if needed
3. Click **Publish release**

### Manual Override (Backup)

If the automated workflow fails, you can manually trigger the Create Release workflow:
1. Navigate to Actions → "Create Release"
2. Fill in the version number
3. Submit the form
4. This creates the git tag and draft release

> **Note:** The workflow validates that version references were updated in `readme.md` before creating the release, ensuring consistency.

## Testing changes to the Deploy PR to Pantheon workflow

Because we have implemented a `pull_request_target` trigger for the Deploy PR to Pantheon workflow to allow robots to access secrets and run the deployment, and because `pull_request_target` uses the base branch rather than the PR branch, if you want to test changes to the workflow itself, you can do so by using the `workflow_dispatch` trigger. 

To do this, navigate to the Actions tab and select the "Deploy PR to Pantheon" workflow. You can then manually trigger the workflow. This will allow you to test changes to the workflow without needing to create a pull request.