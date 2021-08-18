# Verify Semantic Changelog Update

This is a [Github Action](https://github.com/features/actions) that ensures your PR contains a changelog entry for all the user facing changes.
For more info check [Conventional Commits spec](https://www.conventionalcommits.org/).

This is helpful when you're using [semantic-release](https://github.com/semantic-release/semantic-release) with the Conventional Commits preset.

## Example config

```yml
name: 'Verify Semantic Changelog Update'
on:
  pull_request_target:
    types:
      - opened
      - edited
      - synchronize
    branches:
      - master

jobs:
  main:
    runs-on: ubuntu-latest
    steps:
      # Please look up the latest version from
      # https://github.com/GetStream/verify-semantic-changelog-update/releases
      - uses: GetStream/verify-semantic-changelog-update@X.X.X
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Configuration

The action works without configuration, however you can provide options for customization.

```yml
        with:
          # Configure which types should be verified.
          # Default: fix, feat, *! (Any breaking change type)
          types: |
            fix
            feat
          # Configure which scopes are allowed along with their path.
          # Default: Only checks for the top-level changelog entry
          scopes: |
            {
              "ui": "packages/ui",
              "core": "packages/core"
            }
          # Configure the changelog file path/name.
          # Default: changelog.md
          path: |
            changelog.md
```

## Event triggers

There are two events that can be used as triggers for this action, each with different characteristics:

1. [`pull_request_target`](https://docs.github.com/en/actions/reference/events-that-trigger-workflows#pull_request_target): This allows the action to be used in a fork-based workflow, where e.g. you want to accept pull requests in a public repository. In this case, the configuration from the main branch of your repository will be used for the check. This means that you need to have this configuration in the main branch for the action to run at all (e.g. it won't run within a PR that adds the action initially). Also if you change the configuration in a PR, the changes will not be reflected for the current PR – only subsequent ones after the changes are in the main branch.
2. [`pull_request`](https://docs.github.com/en/actions/reference/events-that-trigger-workflows#pull_request): This configuration uses the latest configuration that is available in the current branch. It will only work if the branch is based in the repository itself. If this configuration is used and a pull request from a fork is opened, you'll encounter an error as the Github token environment parameter is not available. This option is viable if all contributors have write access to the repository.