#!/bin/bash

# Enforce the structure of one CHANGELOG by comparing its base and head
# revisions.
#
# A heading is either a version number or the unreleased heading (`Upcoming` by
# default), and entries for unreleased work go under the unreleased heading.
# Writing them into a `## <version>` heading is an easy mistake to make: on a
# branch cut from a release commit that heading sits at the top of the file.
#
# Three rules:
#
#   1. A version section present in the base revision must survive unchanged.
#   2. Every heading that is not a version number must match the unreleased
#      heading pattern in full.
#   3. Only a release branch may add a version heading. Elsewhere it means
#      entries were filed under a version that has not shipped. Exempt are a
#      CHANGELOG the PR creates, so a new package can declare its initial
#      version, and a version that a `--released` file already lists, so a merge
#      of a released branch into a long-lived one passes.
#
# Usage:
#   check-changelog-placement.sh [options] BASE_FILE HEAD_FILE DISPLAY_PATH HEAD_BRANCH
#
# Options:
#   --upcoming ERE         Unreleased heading pattern, matched against the whole
#                          heading text. Default: Upcoming
#   --release-prefix STR   Head branches starting with STR may add version
#                          headings. Default: release/
#   --released FILE        A CHANGELOG whose version headings count as
#                          published. Repeatable.
#
# A missing or empty BASE_FILE is treated as a CHANGELOG the PR adds. An empty
# HEAD_BRANCH never counts as a release branch.

# Fast fail the script on failures.
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") [--upcoming ERE] [--release-prefix STR] [--released FILE]... BASE_FILE HEAD_FILE DISPLAY_PATH HEAD_BRANCH" >&2
  exit 2
}

upcoming='Upcoming'
release_prefix='release/'
released_files=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --upcoming) [ "$#" -ge 2 ] || usage; upcoming=$2; shift 2 ;;
    --release-prefix) [ "$#" -ge 2 ] || usage; release_prefix=$2; shift 2 ;;
    --released) [ "$#" -ge 2 ] || usage; released_files+=("$2"); shift 2 ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done

[ "$#" -eq 4 ] || usage

base_file=$1
head_file=$2
display_path=$3
head_branch=$4

[ -f "$head_file" ] || head_file=/dev/null

is_new_changelog=false
if [ ! -s "$base_file" ]; then
  base_file=/dev/null
  is_new_changelog=true
fi

# How the unreleased heading is named in messages: literally when the pattern
# is a plain word, otherwise as the pattern itself.
if [[ $upcoming =~ ^[A-Za-z0-9\ _-]+$ ]]; then
  upcoming_name="\`## $upcoming\`"
else
  upcoming_name="a heading matching \`^($upcoming)\$\`"
fi

# Every `## ` heading in the file, one per line, trimmed.
headings() {
  awk '/^## / {
    heading = substr($0, 4)
    sub(/^[ \t]+/, "", heading)
    sub(/[ \t]+$/, "", heading)
    print heading
  }' "$1"
}

# A released section: `0.4.1`, `1.0.0-beta.1`, `0.4.1 (2026-07-22)`, ...
#
# Two leading numeric components are required, so a prose heading that happens
# to start with a digit (`## 2 quick fixes`) is reported as a misnamed heading
# rather than as a version.
is_version() {
  [[ $1 =~ ^[0-9]+\.[0-9]+ ]]
}

is_upcoming() {
  [[ $1 =~ ^($upcoming)$ ]]
}

has_heading() {
  headings "$1" | grep -qxF -- "$2"
}

is_released_elsewhere() {
  local file
  for file in ${released_files[@]+"${released_files[@]}"}; do
    [ -f "$file" ] && has_heading "$file" "$1" && return 0
  done
  return 1
}

# The lines under the requested heading. Trailing blank lines are dropped so
# spacing alone never fails the check; blank lines inside the body are kept as
# they are, so a real edit is still caught.
section() {
  awk -v want="$2" '
    /^## / {
      heading = substr($0, 4)
      sub(/^[ \t]+/, "", heading)
      sub(/[ \t]+$/, "", heading)
      inside = (heading == want)
      next
    }
    inside {
      if ($0 ~ /^[ \t]*$/) { held[++blanks] = $0; next }
      for (i = 1; i <= blanks; i++) print held[i]
      blanks = 0
      print
    }
  ' "$1"
}

is_release_branch() {
  [ -n "$head_branch" ] && [ -n "$release_prefix" ] && [[ $head_branch == "$release_prefix"* ]]
}

released=''
misnamed=''
premature=''

# Rule 1: no published section may change.
while IFS= read -r heading; do
  if [ -n "$heading" ] && is_version "$heading"; then
    if ! has_heading "$head_file" "$heading"; then
      released+="  - \`## $heading\` was removed"$'\n'
    elif [ "$(section "$base_file" "$heading")" != "$(section "$head_file" "$heading")" ]; then
      released+="  - \`## $heading\` was modified"$'\n'
    fi
  fi
done < <(headings "$base_file")

# Rules 2 and 3, over what the PR proposes.
while IFS= read -r heading; do
  [ -n "$heading" ] || continue

  if ! is_version "$heading"; then
    is_upcoming "$heading" || misnamed+="  - \`## $heading\`"$'\n'
  elif [ "$is_new_changelog" = false ] \
       && ! is_release_branch \
       && ! has_heading "$base_file" "$heading" \
       && ! is_released_elsewhere "$heading"; then
    premature+="  - \`## $heading\`"$'\n'
  fi
done < <(headings "$head_file")

if [ -z "$released" ] && [ -z "$misnamed" ] && [ -z "$premature" ]; then
  echo "$display_path: structure is fine."
  exit 0
fi

echo "::error file=$display_path::CHANGELOG structure check failed"
echo

if [ -n "$released" ]; then
  echo "$display_path changes a section for a version that is already published:"
  echo
  printf '%s' "$released"
  cat <<EOF

Entries for unreleased work go under $upcoming_name at the top of the file.
Add that heading if it is missing, and move the entries there.
EOF
fi

if [ -n "$misnamed" ]; then
  [ -n "$released" ] && echo
  echo "$display_path has a heading that is neither a version nor $upcoming_name:"
  echo
  printf '%s' "$misnamed"
  cat <<EOF

Rename it to $upcoming_name, the only unreleased heading this check accepts.
EOF
fi

if [ -n "$premature" ]; then
  { [ -n "$released" ] || [ -n "$misnamed" ]; } && echo
  echo "$display_path adds a version heading on a branch that is not a release:"
  echo
  printf '%s' "$premature"
  cat <<EOF

Put the entries under $upcoming_name instead. The version heading is created by
the release PR, which is cut from a \`${release_prefix}...\` branch.
EOF
fi

cat <<'EOF'

If the change is deliberate (fixing a typo in an entry that already shipped,
for example), add the override label to the pull request.
EOF
exit 1
