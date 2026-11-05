#!/bin/bash

# Tests for check-changelog-placement.sh and run.sh.
#
# Each check-changelog-placement.sh case writes a base and head CHANGELOG, runs
# the check, and compares the exit code; `expect_output` then asserts on what
# the last case printed. The run.sh cases put a fake `gh` first on PATH that
# serves files from a fixture directory.

# Fixture text holds Markdown backticks, which must stay literal.
# shellcheck disable=SC2016

set -uo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-changelog-placement.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

passed=0
failed=0
output=''

pass() { passed=$((passed + 1)); echo "ok   - $1"; }
fail() { failed=$((failed + 1)); echo "FAIL - $1"; printf '       %s\n' "$output"; }

# expect NAME EXIT_CODE [OPTIONS...] -- HEAD_BRANCH
# Reads $work/base.md and $work/head.md.
expect() {
  local name=$1 want=$2
  shift 2
  local options=()
  while [ "$1" != '--' ]; do options+=("$1"); shift; done
  shift
  local branch=$1 got

  output=$("$script" ${options[@]+"${options[@]}"} "$work/base.md" "$work/head.md" CHANGELOG.md "$branch" 2>&1)
  got=$?

  if [ "$got" = "$want" ]; then pass "$name"; else fail "$name (exit $got, want $want)"; fi
}

# expect_output NAME TEXT: the last case printed TEXT, as a fixed string.
expect_output() {
  if grep -qF -- "$2" <<< "$output"; then pass "$1"; else fail "$1 (no \"$2\")"; fi
}

# expect_no_output NAME TEXT: the last case did not print TEXT.
expect_no_output() {
  if grep -qF -- "$2" <<< "$output"; then fail "$1 (printed \"$2\")"; else pass "$1"; fi
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
expect_output '  names the modified section' '- `## 0.5.1` was modified'
expect_output '  annotates the heading line' '::error file=CHANGELOG.md,line=5::`## 0.5.1` was published and is modified. New entries go under `## Upcoming`.'
expect_output '  points at the unreleased heading' 'go under `## Upcoming` at the top'
expect_output '  names the default override label' 'add the `changelog-override` label'
expect 'a custom override label is named' 1 --override-label 'skip-changelog' -- feat/x
expect_output '  names the custom label' 'add the `skip-changelog` label'

released | write_base
released | sed 's/as well/too/' | write_head
expect 'typo fix in a released section fails' 1 -- feat/x

released | write_base
{ echo '## 0.5.1'; echo; echo '- Added `Filter.raw`.'; } | write_head
expect 'removed released section fails' 1 -- feat/x
expect_output '  names the removed section' '- `## 0.5.1+1` was removed'
expect_output '  annotates the file, having no line' '::error file=CHANGELOG.md::`## 0.5.1+1` was published and is removed.'

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
expect_output '  names the misnamed heading' '- `## Unreleased`'
expect_output '  annotates its line' '::error file=CHANGELOG.md,line=1::`## Unreleased` is neither a version nor `## Upcoming`.'
expect_no_output '  reports no other rule' 'already published'
expect_no_output '  offers no override' 'changelog-override'

released | write_base
{ echo '## Upcoming (minor)'; echo; echo '- Added X.'; echo; released; } | write_head
expect 'Upcoming (minor) fails with the default pattern' 1 -- feat/x
expect 'Upcoming (minor) passes with the v2 pattern' 0 --upcoming 'Upcoming \((major|minor)\)' -- feat/x
{ echo '## Upcoming (major)x'; echo; echo '- Added X.'; echo; released; } | write_head
expect 'v2 pattern rejects trailing text' 1 --upcoming 'Upcoming \((major|minor)\)' -- feat/x
expect_output '  describes a pattern by the pattern' 'a heading matching `^(Upcoming \((major|minor)\))$`'

# --- Rule 3: only a release adds a version heading ----------------------------

{ echo '## Upcoming'; echo; echo '- Added X.'; echo; released; } | write_base
{ echo '## 0.5.2'; echo; echo '- Added X.'; echo; released; } | write_head
expect 'release branch renames Upcoming to a version' 0 -- release/v0.5.2
expect 'the same rename on a feature branch fails' 1 -- feat/x
expect_output '  names the premature version' '- `## 0.5.2`'
expect_output '  names the branch' 'adds a version heading on `feat/x`, which is not a release branch:'
expect_output '  names the release prefix' 'cut from a `release/...` branch'
expect_no_output '  offers no override' 'changelog-override'
expect 'a fork (blank branch) gets no release exemption' 1 -- ''
expect_output '  and says forks never count' 'from a fork, and pull requests from forks never count as release branches'
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

released | write_base
{ echo '## v0.5.2'; echo; echo '- X.'; echo; released; } | write_head
expect 'a v-prefixed version is misnamed' 1 -- release/v0.5.2
expect_output '  says how to write a version' 'without a `v` prefix or brackets'

{ echo '## [0.5.1] - 2026-07-22'; echo; echo '- X.'; } | write_base
cp "$work/base.md" "$work/head.md"
expect 'a keep-a-changelog version is misnamed' 1 -- feat/x

# --- Several rules at once ----------------------------------------------------

released | write_base
{ echo '## Unreleased'; echo; echo '- X.'; echo; echo '## 0.5.2'; echo; echo '- Y.'; echo;
  echo '## 0.5.1'; echo; echo '- Added `Filter.raw`.'; } | write_head
expect 'all three rules fail together' 1 -- feat/x
expect_output '  reports the removed section' '- `## 0.5.1+1` was removed'
expect_output '  reports the misnamed heading' '- `## Unreleased`'
expect_output '  reports the premature version' '- `## 0.5.2`'
expect_output '  offers the override for the published section' 'add the `changelog-override` label'
if [ "$(grep -c '^::error ' <<< "$output")" = 3 ]; then pass '  one annotation per finding'
else fail '  one annotation per finding'; fi

released | write_base
{ echo '## 100% done'; echo; echo '- X.'; echo; released; } | write_head
expect 'a heading with % is reported' 1 -- feat/x
expect_output '  escaped in the annotation' '`## 100%25 done` is neither'

# --- Fenced code --------------------------------------------------------------

fenced() {
  cat <<'EOF'
## 0.5.1

- Added `Filter.raw`:

```md
## Usage
```
EOF
}
fenced | write_base
{ echo '## Upcoming'; echo; echo '- Added X.'; echo; fenced; } | write_head
expect 'a ## line inside a code block is not a heading' 0 -- feat/x
{ echo '## Upcoming'; echo; echo '- Added X.'; echo; fenced; echo '  More.'; } | write_head
expect 'an edit after a code block is still caught' 1 -- feat/x

# --- Usage --------------------------------------------------------------------

output=$("$script" only-one-arg 2>&1)
if [ $? = 2 ]; then pass 'wrong arguments exit 2'; else fail 'wrong arguments exit 2'; fi

# --- run.sh -------------------------------------------------------------------
#
# The fake gh answers three calls from $MOCK:
#   pulls/N/files       $MOCK/files.json, filtered by the real jq, or a 403
#                       when $MOCK/forbidden/files exists
#   compare/A...B       $MOCK/merge_base, or a failure when it is missing
#   contents/PATH?ref=R $MOCK/contents/R/PATH, a 404 when it is missing, or a
#                       500 when $MOCK/broken/R exists

run_sh="$(cd "$(dirname "$0")/.." && pwd)/run.sh"
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'EOF'
#!/bin/bash
[ "$1" = api ] || exit 64
endpoint=$2
shift 2
filter=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --jq) filter=$2; shift 2 ;;
    -H) shift 2 ;;
    *) shift ;;
  esac
done
case "$endpoint" in
  */pulls/*/files)
    [ -e "$MOCK/forbidden/files" ] && { echo 'gh: Resource not accessible by integration (HTTP 403)' >&2; exit 1; }
    jq -r "$filter" "$MOCK/files.json" ;;
  */compare/*)
    [ -f "$MOCK/merge_base" ] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
    cat "$MOCK/merge_base" ;;
  */contents/*)
    path=${endpoint#*/contents/}
    ref=${path#*\?ref=}
    path=${path%%\?ref=*}
    if [ -e "$MOCK/broken/$ref" ]; then
      echo '{"message":"Server Error"}'; echo 'gh: Server Error (HTTP 500)' >&2; exit 1
    fi
    file="$MOCK/contents/$ref/$path"
    if [ ! -f "$file" ]; then
      echo '{"message":"Not Found"}'; echo 'gh: Not Found (HTTP 404)' >&2; exit 1
    fi
    cat "$file" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$work/bin/gh"

export MOCK="$work/mock"

# mock_reset: an empty fixture with `main` as the base tip and `fork` as the
# merge base.
mock_reset() {
  rm -rf "$MOCK"
  mkdir -p "$MOCK/contents/main" "$MOCK/contents/fork" "$MOCK/contents/refs/pull/7/head" "$MOCK/broken" "$MOCK/forbidden"
  echo fork > "$MOCK/merge_base"
  echo '[]' > "$MOCK/files.json"
}

# mock_file REF PATH: stdin becomes PATH at REF.
mock_file() { mkdir -p "$(dirname "$MOCK/contents/$1/$2")"; cat > "$MOCK/contents/$1/$2"; }

# mock_files STATUS:PATH...: the files the pull request touches.
mock_files() {
  local entry sep=''
  { printf '['
    for entry in "$@"; do
      printf '%s{"status":"%s","filename":"%s"}' "$sep" "${entry%%:*}" "${entry#*:}"
      sep=','
    done
    printf ']'; } > "$MOCK/files.json"
}

# expect_run NAME EXIT_CODE [VAR=VALUE...]
expect_run() {
  local name=$1 want=$2 got
  shift 2
  output=$(env PATH="$work/bin:$PATH" GH_TOKEN=t REPO=o/r PR=7 BASE_SHA=main \
             HEAD_BRANCH=feat/x "$@" "$run_sh" 2>&1)
  got=$?
  if [ "$got" = "$want" ]; then pass "run.sh: $name"; else fail "run.sh: $name (exit $got, want $want)"; fi
}

mock_reset
mock_files modified:packages/a/CHANGELOG.md
released | mock_file fork packages/a/CHANGELOG.md
{ echo '## 0.6.0'; echo; echo '- Shipped.'; echo; released; } | mock_file main packages/a/CHANGELOG.md
{ echo '## Upcoming'; echo; echo '- Added X.'; echo; released; } | mock_file refs/pull/7/head packages/a/CHANGELOG.md
expect_run 'a branch behind its base compares against the merge base' 0
echo main > "$MOCK/merge_base"
expect_run 'the same branch against the base tip would fail' 1
expect_output '  as a removed version' '- `## 0.6.0` was removed'

mock_reset
mock_files modified:packages/a/CHANGELOG.md
released | mock_file fork packages/a/CHANGELOG.md
released | sed 's/as well/too/' | mock_file main packages/a/CHANGELOG.md
{ echo '## Upcoming'; echo; echo '- Added X.'; echo; released; } | mock_file refs/pull/7/head packages/a/CHANGELOG.md
expect_run 'a published section edited on the base after the branch point passes' 0
echo main > "$MOCK/merge_base"
expect_run 'the same branch against the base tip would fail' 1
expect_output '  as a modified version' '- `## 0.5.1+1` was modified'
rm "$MOCK/merge_base"
expect_run 'a failing compare fails the run' 1
expect_output '  saying why' 'Could not find where pull request #7 branched off'

mock_reset
mock_files modified:CHANGELOG.md
released | mock_file fork CHANGELOG.md
released | sed 's/as well/too/' | mock_file refs/pull/7/head CHANGELOG.md
expect_run 'a violation fails the run' 1
expect_run 'the override label skips the check' 0 OVERRIDE=true
expect_output '  and says so' 'The override label is set'
expect_run 'the label name reaches the message' 1 OVERRIDE_LABEL=skip-changelog
expect_output '  as given' 'add the `skip-changelog` label'

mock_reset
mock_files removed:packages/gone/CHANGELOG.md modified:packages/a/README.md
expect_run 'a removed CHANGELOG is skipped' 0
expect_output '  leaving nothing to check' 'This PR touches no CHANGELOG.md.'

mock_reset
mock_files modified:changelog.md
{ echo '## 0.0.1'; } | mock_file fork changelog.md
{ echo '## 0.0.1'; echo '- Edited.'; } | mock_file refs/pull/7/head changelog.md
expect_run 'a lowercase changelog is not matched by default' 0
expect_run 'changelog-file-name matches it' 1 CHANGELOG_NAME=changelog.md

mock_reset
mock_files added:packages/new/CHANGELOG.md
{ echo '## 0.0.1'; echo; echo '- Initial release.'; } | mock_file refs/pull/7/head packages/new/CHANGELOG.md
expect_run 'a 404 on the base is a new CHANGELOG' 0

mock_reset
mock_files modified:CHANGELOG.md
released | mock_file fork CHANGELOG.md
expect_run 'a 404 on the head fails the run' 1
expect_output '  annotating the file with the likely cause' '::error file=CHANGELOG.md::Could not fetch CHANGELOG.md at refs/pull/7/head. The workflow needs `permissions: contents: read`.'

mock_reset
mock_files modified:CHANGELOG.md
touch "$MOCK/broken/fork"
{ echo '## Upcoming'; echo; released; } | mock_file refs/pull/7/head CHANGELOG.md
expect_run 'a 500 on the base fails the run' 1
expect_no_output '  without blaming permissions' 'The workflow needs'

mock_reset
expect_run 'a push event fails the run' 1 PR= EVENT=push
expect_output '  naming the event' '::error::Verify Changelog Placement only runs on pull_request or pull_request_target events, not push.'

mock_reset
touch "$MOCK/forbidden/files"
expect_run 'a 403 listing the files fails the run' 1
expect_output '  naming the permission' '::error::Could not list the files of pull request #7. The workflow needs `permissions: pull-requests: read`.'
expect_output '  with gh'"'"'s own error' 'Resource not accessible by integration (HTTP 403)'

mock_reset
mock_files modified:CHANGELOG.md
{ echo '## Upcoming (major)'; echo; released; } | mock_file fork CHANGELOG.md
{ echo '## Upcoming (major)'; echo; echo '## 0.5.2'; echo; echo '- Y.'; echo; released; } \
  | mock_file refs/pull/7/head CHANGELOG.md
{ echo '## 0.5.2'; echo; echo '- Y.'; echo; released; } | mock_file main CHANGELOG.md
v2=(UPCOMING='Upcoming \((major|minor)\)')
expect_run 'a version from released-from passes' 0 "${v2[@]}" RELEASED_FROM=main
expect_run 'a missing released-from branch is no exemption' 1 "${v2[@]}" RELEASED_FROM=gone
expect_run 'released-from ignores blank lines and spaces' 0 "${v2[@]}" RELEASED_FROM=$'\n  main  \n'

echo
echo "$passed passed, $failed failed"
[ "$failed" = 0 ]
