#!/bin/bash

# Runs check-changelog-placement.sh over every CHANGELOG.md a pull request
# touches. Called by action.yml; every input arrives as an environment variable:
#
#   GH_TOKEN        token for the GitHub API
#   REPO            owner/name of the base repository
#   PR              pull request number
#   BASE_SHA        tip of the base branch
#   HEAD_BRANCH     head branch, blank for a pull request from a fork
#   OVERRIDE        `true` skips the check
#   OVERRIDE_LABEL  name of the label that sets OVERRIDE, for the message
#   CHANGELOG_NAME  file name of a changelog, matched exactly
#   UPCOMING        unreleased heading pattern
#   RELEASE_PREFIX  head branch prefix that may add version headings
#   RELEASED_FROM   branches whose CHANGELOG versions count as published, one
#                   per line

set -euo pipefail

: "${GH_TOKEN:?}" "${REPO:?}" "${PR:?}" "${BASE_SHA:?}"

if [ "${OVERRIDE:-false}" = 'true' ]; then
  echo 'The override label is set; skipping the placement check.'
  exit 0
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# Deleted changelogs are skipped: a PR that removes a package is not filing
# entries in the wrong place, and it keeps every remaining path guaranteed to
# exist at the head revision.
export CHANGELOG_NAME=${CHANGELOG_NAME:-CHANGELOG.md}
changelogs=$(gh api "repos/$REPO/pulls/$PR/files" --paginate \
  --jq '.[] | select(.status != "removed")
            | .filename
            | select((split("/") | last) == env.CHANGELOG_NAME)')

if [ -z "$changelogs" ]; then
  echo "This PR touches no $CHANGELOG_NAME."
  exit 0
fi

# `refs/pull/N/head` rather than the head SHA: for a PR from a fork the head
# commit lives in the fork, but this ref always resolves in the base repo.
head_ref="refs/pull/$PR/head"

# The base copy is read where the PR branched off, not at the tip of the base
# branch. A version the base branch released since then is missing from the
# head, and comparing against the tip would report it as removed.
if ! merge_base=$(gh api "repos/$REPO/compare/$BASE_SHA...$head_ref" \
                    --jq .merge_base_commit.sha) || [ -z "$merge_base" ]; then
  echo "::error::Could not find where pull request #$PR branched off."
  exit 1
fi

released_from=()
while IFS= read -r branch; do
  branch=$(echo "$branch" | xargs)
  [ -n "$branch" ] && released_from+=("$branch")
done <<< "${RELEASED_FROM:-}"

# Fetches $1 at revision $2 into $3. The PR's CHANGELOG is fetched as data and
# only ever read by the check.
#
# A 404 is only a real answer where $4 says the file may be absent. Every other
# failure (auth, rate limit, transient 5xx, and a 404 on the head revision of a
# file the PR demonstrably touches) must fail the job: an empty file looks like
# a brand-new changelog and would wave a real violation through.
fetch() {
  local path=$1 rev=$2 dest=$3 allow_missing=$4 err
  err="$work_dir/err"

  if gh api "repos/$REPO/contents/$path?ref=$rev" \
       -H 'Accept: application/vnd.github.raw' > "$dest" 2>"$err"; then
    return 0
  fi

  # gh writes the error body to stdout, so $dest holds JSON, not content.
  if [ "$allow_missing" = 'true' ] && grep -q '(HTTP 404)' "$err"; then
    : > "$dest"
    return 0
  fi

  echo "::error::Could not fetch $path at $rev"
  cat "$err" >&2
  return 1
}

status=0
while IFS= read -r path; do
  base="$work_dir/base.md"
  head="$work_dir/head.md"
  args=(--upcoming "${UPCOMING:-Upcoming}"
        --release-prefix "${RELEASE_PREFIX:-release/}"
        --override-label "${OVERRIDE_LABEL:-changelog-override}")

  if ! fetch "$path" "$merge_base" "$base" true \
     || ! fetch "$path" "$head_ref" "$head" false; then
    status=1
    continue
  fi

  i=0
  for branch in ${released_from[@]+"${released_from[@]}"}; do
    i=$((i + 1))
    released="$work_dir/released-$i.md"
    if ! fetch "$path" "$branch" "$released" true; then
      status=1
      continue 2
    fi
    args+=(--released "$released")
  done

  "$script_dir/check-changelog-placement.sh" "${args[@]}" \
    "$base" "$head" "$path" "${HEAD_BRANCH:-}" || status=1
done <<< "$changelogs"

exit $status
