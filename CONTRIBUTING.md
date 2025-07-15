# Contributing to Push to Pantheon

`0.x` is the current default branch and all feature branches merge into this branch. 

## Cutting a release

Cutting a release is a _manual_ process and should be created from the `0.x` branch. This is to ensure that we know exactly what changes are included in the release and when releases are made.

### Prepare first
Before cutting a release, we must first _prepare_ the release. Currently, preparing the release simply creates a GitHub Pull Request that updates the version number in the `readme.md` file to bump the examples to the latest version. 

To prepare a release, navigate to the Actions tab and select the pinned "Prepare Release" workflow. Fill in the required field for the new version number, and submit the form. This will create a pull request that updates the version number in the `readme.md` file.

Once this pull request is approved and merged, a new release can be cut.

### Create the release
To cut a new release, navigate to the Actions tab and select the pinned "Create Release" workflow. Fill in the required field for the version number, and submit the form. This workflow will check the `readme.md` file for the new version number. If the last release version is still referenced in the `readme.md` file, the workflow will fail. If the last release version is not found, a new Git tag will be created, and the release will be published on GitHub with release notes auto-generated from the merged PRs.

## Testing changes to the Deploy PR to Pantheon workflow

Because we have implemented a `pull_request_target` trigger for the Deploy PR to Pantheon workflow to allow robots to access secrets and run the deployment, and because `pull_request_target` uses the base branch rather than the PR branch, if you want to test changes to the workflow itself, you can do so by using the `workflow_dispatch` trigger. 

To do this, navigate to the Actions tab and select the "Deploy PR to Pantheon" workflow. You can then manually trigger the workflow. This will allow you to test changes to the workflow without needing to create a pull request.