#!/bin/bash

# Tests for check-changelog-placement.sh. Each case writes a base and head
# CHANGELOG, runs the check, and compares the exit code.

# Fixture text holds Markdown backticks, which must stay literal.
# shellcheck disable=SC2016

set -uo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-changelog-placement.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

passed=0
failed=0

# expect NAME EXIT_CODE [OPTIONS...] -- HEAD_BRANCH
# Reads $work/base.md and $work/head.md.
expect() {
  local name=$1 want=$2
  shift 2
  local options=()
  while [ "$1" != '--' ]; do options+=("$1"); shift; done
  shift
  local branch=$1 output got

  output=$("$script" ${options[@]+"${options[@]}"} "$work/base.md" "$work/head.md" CHANGELOG.md "$branch" 2>&1)
  got=$?

  if [ "$got" = "$want" ]; then
    passed=$((passed + 1))
    echo "ok   - $name"
  else
    failed=$((failed + 1))
    echo "FAIL - $name (exit $got, want $want)"
    printf '       %s\n' "$output"
  fi
}

write_base() { cat > "$work/base.md"; }
write_head() { cat > "$work/head.md"; }

released() {
  cat <<'EOF'
## 0.5.1+1

- `equatable` now resolves to 3.x as well.

## 0.5.1

- Added `Filter.raw`.
EOF
}

# --- Rule 1: published sections stay as they are -----------------------------

released | write_base
{ echo '## Upcoming'; echo; echo '- Added `inFlight`.'; echo; released; } | write_head
expect 'entry under Upcoming passes' 0 -- feat/x

released | write_base
cat <<'EOF' | write_head
## 0.5.1+1

- `equatable` now resolves to 3.x as well.

## 0.5.1

- Added `Filter.raw`.
- Added `InFlightCache.inFlight`.
EOF
expect 'entry added under a released version fails' 1 -- feat/x

released | write_base
released | sed 's/as well/too/' | write_head
expect 'typo fix in a released section fails' 1 -- feat/x

released | write_base
{ echo '## 0.5.1'; echo; echo '- Added `Filter.raw`.'; } | write_head
expect 'removed released section fails' 1 -- feat/x

released | write_base
{ released; echo; echo; } | write_head
expect 'trailing blank lines are not a change' 0 -- feat/x

{ echo '## 0.6.2'; echo; echo '- Fixed a crash.'; } | write_base
{ echo '## Upcoming'; echo; echo '- Added X.'; echo; echo '## 0.6.2'; echo; echo '- Fixed a crash.'; } | write_head
expect 'adding Upcoming above the top released version passes' 0 -- feat/x

# --- Rule 2: the unreleased heading is named one way --------------------------

released | write_base
{ echo '## Unreleased'; echo; echo '- Added X.'; echo; released; } | write_head
expect 'Unreleased fails with the default pattern' 1 -- feat/x

released | write_base
{ echo '## Upcoming (minor)'; echo; echo '- Added X.'; echo; released; } | write_head
expect 'Upcoming (minor) fails with the default pattern' 1 -- feat/x
expect 'Upcoming (minor) passes with the v2 pattern' 0 --upcoming 'Upcoming \((major|minor)\)' -- feat/x
{ echo '## Upcoming (major)x'; echo; echo '- Added X.'; echo; released; } | write_head
expect 'v2 pattern rejects trailing text' 1 --upcoming 'Upcoming \((major|minor)\)' -- feat/x

# --- Rule 3: only a release adds a version heading ----------------------------

{ echo '## Upcoming'; echo; echo '- Added X.'; echo; released; } | write_base
{ echo '## 0.5.2'; echo; echo '- Added X.'; echo; released; } | write_head
expect 'release branch renames Upcoming to a version' 0 -- release/v0.5.2
expect 'the same rename on a feature branch fails' 1 -- feat/x
expect 'a fork (blank branch) gets no release exemption' 1 -- ''
expect 'custom release prefix is honoured' 0 --release-prefix 'rel-' -- rel-0.5.2

: | write_base
{ echo '## 0.0.1'; echo; echo '- Initial release.'; } | write_head
expect 'new CHANGELOG may declare its first version' 0 -- feat/new-package

{ echo '## Upcoming (major)'; echo; echo '- Breaking X.'; echo; released; } | write_base
{ echo '## Upcoming (major)'; echo; echo '- Breaking X.'; echo; echo '## 0.5.2'; echo; echo '- Fixed Y.'; echo; released; } | write_head
{ echo '## 0.5.2'; echo; echo '- Fixed Y.'; echo; released; } > "$work/main.md"
expect 'merge PR adding a version from released-from passes' 0 \
  --upcoming 'Upcoming \((major|minor)\)' --released "$work/main.md" -- chore/merge-main
expect 'the same merge PR without released-from fails' 1 \
  --upcoming 'Upcoming \((major|minor)\)' -- chore/merge-main
expect 'a missing released-from file is ignored' 1 \
  --upcoming 'Upcoming \((major|minor)\)' --released "$work/absent.md" -- chore/merge-main

# --- Headings that only look like versions ------------------------------------

released | write_base
{ echo '## 2 quick fixes'; echo; echo '- X.'; echo; released; } | write_head
expect 'a prose heading starting with a digit is misnamed' 1 -- feat/x

# --- Usage --------------------------------------------------------------------

"$script" only-one-arg > /dev/null 2>&1
if [ $? = 2 ]; then passed=$((passed + 1)); echo 'ok   - wrong arguments exit 2'
else failed=$((failed + 1)); echo 'FAIL - wrong arguments exit 2'; fi

echo
echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
