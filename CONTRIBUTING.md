# Contributing to Push to Pantheon

`0.x` is the current default branch and all feature branches merge into this branch. 

## Cutting a release

Cutting a release is a _manual_ process and should be created from the `0.x` branch. This is to ensure that we know exactly what changes are included in the release and when releases are made.

To cut a new release, navigate to the Actions tab and select the "Create Release" workflow. Fill in the required field for the version number, and submit the form. A new Git tag will be created, and the release will be published on GitHub with release notes auto-generated from the merged PRs.