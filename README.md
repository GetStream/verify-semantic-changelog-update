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
2. [`pull_request`](https://docs.github.com/en/actions/reference/events-that-trigger-workflows#pull_request): This configuration uses the latest configuration that is available in the current branch. For a pull request from a fork, `GITHUB_TOKEN` is read-only, which is enough for this action.

## Changelog placement

`placement/` is a second action in this repository. Where the action above
checks that a CHANGELOG was updated, this one checks *where* the new entries
went. It fails a pull request that:

1. changes or removes a section for a version that the CHANGELOG already had
   where the pull request branched off,
2. has a `##` heading that is neither a version number nor the unreleased
   heading (`Upcoming` by default), or
3. adds a version heading from a branch that is not a release branch.

Every file named exactly `CHANGELOG.md` (or `changelog-file-name`) that the
pull request adds or modifies is checked, in any directory. A CHANGELOG the
pull request deletes is skipped, and one it creates may declare its first
version.

A version heading starts with `MAJOR.MINOR`: `## 1.2.0`, `## 1.2.0-beta.1`,
`## 1.2.0+1` and `## 1.2.0 (2026-07-22)` are all versions. `## v1.2.0` and
`## [1.2.0] - 2026-07-22` are not, and fail as misnamed headings. `##` lines
inside fenced code blocks are not headings.

```yml
on:
  pull_request_target:
    types: [opened, edited, synchronize, labeled, unlabeled]

permissions:
  contents: read
  pull-requests: read

jobs:
  changelog_placement:
    runs-on: ubuntu-latest
    steps:
      # Pin to a commit SHA: on pull_request_target the action runs with the
      # base repository's token.
      - uses: GetStream/verify-semantic-changelog-update/placement@<sha>
        with:
          # Needs to read the pull request and its files.
          # Default: the workflow's GITHUB_TOKEN
          github-token: ${{ secrets.GITHUB_TOKEN }}
          # Extended regular expression, matched against the whole heading text.
          # Default: Upcoming
          upcoming-heading: 'Upcoming \((major|minor)\)'
          # Head branches that may add version headings. Default: release/
          release-branch-prefix: 'release/'
          # Branches, one per line, whose CHANGELOG versions count as published,
          # so merging a released branch into a long-lived one passes.
          # Default: none
          released-from: |
            main
          # A pull request with this label skips the check.
          # Default: changelog-override
          override-label: 'changelog-override'
          # File name of a changelog, matched exactly. Default: CHANGELOG.md
          changelog-file-name: 'CHANGELOG.md'
```

The pull request's CHANGELOG is only fetched and read as data; the check
itself always runs from this repository. A pull request from a fork never
counts as a release branch, so it cannot add a version heading.

Run the tests with `placement/test/run.sh`.
