#!/usr/bin/env bash
# Repeatable smoke test for agentic-eng / install.sh.
#
# Fully offline and deterministic: each scenario builds its own throwaway
# local git repo to act as the "release source" (tags added incrementally,
# to mirror how real releases get published over time), and a throwaway
# "invoker" directory (a git repo whose origin points at that fixture) to
# run agentic-eng from — so its persistent source clone tracks the FIXTURE,
# never the real GitHub remote. Every run uses a fresh throwaway
# $AGENTIC_TOOLKIT_HOME, never the real ~/.kiro.
#
# Usage: ./scripts/smoke-test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTIC_ENG="$REPO_DIR/agentic-eng"
INSTALL_SH="$REPO_DIR/install.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$*" >&2; }

CLEANUP_DIRS=()
cleanup() {
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT

new_tmp_dir() {
  local d
  d="$(mktemp -d)"
  CLEANUP_DIRS+=("$d")
  printf '%s' "$d"
}

git_q() { git -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

init_fixture_repo() {
  local repo="$1"
  mkdir -p "$repo"
  ( cd "$repo" && git_q init && git config user.email test@example.com && git config user.name "Smoke Test" )
}

write_skill() {
  # write_skill <dir> <skill-name> <label>
  local dir="$1" name="$2" label="$3"
  mkdir -p "$dir/toolkit/skills/$name"
  cat > "$dir/toolkit/skills/$name/SKILL.md" <<EOF
---
name: $name
description: fixture test skill, $label
---
Fixture skill body for $label.
EOF
}

write_broken_skill() {
  # frontmatter name deliberately doesn't match the folder name
  local dir="$1" name="$2"
  mkdir -p "$dir/toolkit/skills/$name"
  cat > "$dir/toolkit/skills/$name/SKILL.md" <<'EOF'
---
name: wrong-name-does-not-match-folder
description: deliberately broken fixture
---
broken
EOF
}

# publish_release <repo> <version> <label>
# Commits whatever write_skill/write_broken_skill left staged, sets VERSION,
# tags vVERSION. Call write_skill (or write_broken_skill) first.
publish_release() {
  local repo="$1" version="$2"
  printf '%s\n' "$version" > "$repo/VERSION"
  ( cd "$repo" && git add -A && git_q commit -m "v$version" && git_q tag "v$version" )
}

build_invoker() {
  # An invoker dir: a git repo whose origin points at $1, with a copy of the
  # real agentic-eng script. Running "$invoker/agentic-eng" resolves
  # releases from $1, never the real GitHub remote.
  local origin="$1" dir
  dir="$(new_tmp_dir)/invoker"
  mkdir -p "$dir"
  ( cd "$dir" && git_q init && git_q remote add origin "$origin" )
  cp "$AGENTIC_ENG" "$dir/agentic-eng"
  chmod +x "$dir/agentic-eng"
  printf '%s' "$dir"
}

run() {
  # run <invoker-dir> <home-dir> <args...> -- always returns 0, sets
  # $RUN_OUT and $RUN_EXIT so callers decide what to assert.
  local invoker="$1" home="$2"
  shift 2
  RUN_OUT="$(AGENTIC_TOOLKIT_HOME="$home" "$invoker/agentic-eng" "$@" 2>&1)"
  RUN_EXIT=$?
  return 0
}

skill_file() { printf '%s/.kiro/skills/test-skill/SKILL.md' "$1"; }

#############################################################################
echo "--- scenario: install v1.0.0, update to v1.1.0, rollback, offline rollback ---"
#############################################################################
FIXTURE1="$(new_tmp_dir)/fixture1"
init_fixture_repo "$FIXTURE1"
write_skill "$FIXTURE1" test-skill v1
publish_release "$FIXTURE1" 1.0.0
INVOKER1="$(build_invoker "$FIXTURE1")"
HOME1="$(new_tmp_dir)"

run "$INVOKER1" "$HOME1" install
[ "$RUN_EXIT" -eq 0 ] && ok "install exits 0" || bad "install exited $RUN_EXIT: $RUN_OUT"

grep -q 'fixture test skill, v1' "$(skill_file "$HOME1")" 2>/dev/null \
  && ok "installed skill content matches v1.0.0" \
  || bad "installed skill content does not match v1.0.0"

run "$INVOKER1" "$HOME1" version
printf '%s' "$RUN_OUT" | grep -q 'Installed: 1.0.0' \
  && ok "version reports installed 1.0.0" \
  || bad "version did not report installed 1.0.0: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q 'Up to date' \
  && ok "version reports up to date when no newer tag exists" \
  || bad "version did not report up to date: $RUN_OUT"

BEFORE_COUNT="$(find "$HOME1/.kiro" -type f | wc -l | tr -d ' ')"
run "$INVOKER1" "$HOME1" install
[ "$RUN_EXIT" -eq 0 ] && ok "re-running install with no new release exits 0" || bad "re-running install exited $RUN_EXIT: $RUN_OUT"
AFTER_COUNT="$(find "$HOME1/.kiro" -type f | wc -l | tr -d ' ')"
[ "$BEFORE_COUNT" = "$AFTER_COUNT" ] \
  && ok "idempotent re-run produced no duplicate artifacts ($AFTER_COUNT files, unchanged)" \
  || bad "file count changed across an idempotent re-run: $BEFORE_COUNT -> $AFTER_COUNT"

# A newer release gets published to the SAME remote.
write_skill "$FIXTURE1" test-skill v2
publish_release "$FIXTURE1" 1.1.0

run "$INVOKER1" "$HOME1" version
printf '%s' "$RUN_OUT" | grep -q 'Update available: 1.0.0 -> 1.1.0' \
  && ok "version detects the newer 1.1.0 release" \
  || bad "version did not detect 1.1.0: $RUN_OUT"

run "$INVOKER1" "$HOME1" update
[ "$RUN_EXIT" -eq 0 ] && ok "update exits 0" || bad "update exited $RUN_EXIT: $RUN_OUT"
grep -q 'fixture test skill, v2' "$(skill_file "$HOME1")" 2>/dev/null \
  && ok "update activated 1.1.0's content" \
  || bad "update did not activate 1.1.0's content"
grep -q '^# version: 1.1.0$' "$HOME1/.kiro/.um-agentic-engineering/install-manifest.txt" 2>/dev/null \
  && ok "manifest reflects version 1.1.0 after update" \
  || bad "manifest does not reflect version 1.1.0 after update"
[ -L "$HOME1/.kiro/.um-agentic-engineering/previous" ] \
  && ok "a previous-release pointer exists after an update" \
  || bad "no previous-release pointer after an update"

run "$INVOKER1" "$HOME1" rollback
[ "$RUN_EXIT" -eq 0 ] && ok "rollback exits 0" || bad "rollback exited $RUN_EXIT: $RUN_OUT"
grep -q 'fixture test skill, v1' "$(skill_file "$HOME1")" 2>/dev/null \
  && ok "rollback restored 1.0.0's content" \
  || bad "rollback did not restore 1.0.0's content"

# A second rollback (swap back to 1.1.0) must work with zero network access.
rm -rf "$FIXTURE1"
run "$INVOKER1" "$HOME1" rollback
[ "$RUN_EXIT" -eq 0 ] \
  && ok "rollback succeeds even with the release source deleted (offline)" \
  || bad "rollback failed once the release source was unreachable, but rollback must work offline: $RUN_OUT"
grep -q 'fixture test skill, v2' "$(skill_file "$HOME1")" 2>/dev/null \
  && ok "offline rollback restored 1.1.0's content" \
  || bad "offline rollback did not restore 1.1.0's content"

#############################################################################
echo "--- scenario: version reporting when the release source is unreachable ---"
#############################################################################
FIXTURE2="$(new_tmp_dir)/fixture2"
init_fixture_repo "$FIXTURE2"
write_skill "$FIXTURE2" test-skill v1
publish_release "$FIXTURE2" 1.0.0
INVOKER2="$(build_invoker "$FIXTURE2")"
HOME2="$(new_tmp_dir)"
run "$INVOKER2" "$HOME2" install
rm -rf "$FIXTURE2"
run "$INVOKER2" "$HOME2" version
printf '%s' "$RUN_OUT" | grep -q 'Could not check for updates' \
  && ok "version clearly reports 'could not check' when the release source is unreachable" \
  || bad "version did not distinguish an unreachable source from being up to date: $RUN_OUT"

#############################################################################
echo "--- scenario: a broken release is rejected, prior install stays usable ---"
#############################################################################
FIXTURE3="$(new_tmp_dir)/fixture3"
init_fixture_repo "$FIXTURE3"
write_skill "$FIXTURE3" test-skill v1
publish_release "$FIXTURE3" 1.0.0
INVOKER3="$(build_invoker "$FIXTURE3")"
HOME3="$(new_tmp_dir)"
run "$INVOKER3" "$HOME3" install
[ "$RUN_EXIT" -eq 0 ] || bad "setup: initial install for the broken-release scenario failed: $RUN_OUT"

# A broken release gets published to the SAME remote later.
write_broken_skill "$FIXTURE3" test-skill
publish_release "$FIXTURE3" 1.2.0

run "$INVOKER3" "$HOME3" update
[ "$RUN_EXIT" -ne 0 ] \
  && ok "update rejects a broken/invalid release (exit $RUN_EXIT)" \
  || bad "update exited 0 despite the release failing validation"
printf '%s' "$RUN_OUT" | grep -q 'failed validation' \
  && ok "rejection message explains the release failed validation" \
  || bad "rejection message did not explain why: $RUN_OUT"
grep -q 'fixture test skill, v1' "$(skill_file "$HOME3")" 2>/dev/null \
  && ok "the prior working install (1.0.0) remains active and usable after a rejected update" \
  || bad "the prior working install was disturbed by a rejected update"

#############################################################################
echo "--- scenario: unrelated personal files, uninstall, install.sh bootstrap ---"
#############################################################################
FIXTURE4="$(new_tmp_dir)/fixture4"
init_fixture_repo "$FIXTURE4"
write_skill "$FIXTURE4" test-skill v1
publish_release "$FIXTURE4" 1.0.0
INVOKER4="$(build_invoker "$FIXTURE4")"
HOME4="$(new_tmp_dir)"
mkdir -p "$HOME4/.kiro/skills/my-own-skill"
printf 'untouched\n' > "$HOME4/.kiro/skills/my-own-skill/SKILL.md"

run "$INVOKER4" "$HOME4" install
[ "$(cat "$HOME4/.kiro/skills/my-own-skill/SKILL.md")" = "untouched" ] \
  && ok "a pre-existing, unrelated personal skill is left untouched by install" \
  || bad "install modified a skill directory it did not create"

run "$INVOKER4" "$HOME4" uninstall
[ "$RUN_EXIT" -eq 0 ] || bad "uninstall exited $RUN_EXIT: $RUN_OUT"
if [ ! -e "$HOME4/.kiro/skills/test-skill" ] && [ -f "$HOME4/.kiro/skills/my-own-skill/SKILL.md" ]; then
  ok "uninstall removed exactly what was installed, left the unrelated skill in place"
else
  bad "uninstall removed too much or too little"
fi
[ ! -e "$HOME4/.kiro/steering/um-agentic-engineering-status.md" ] \
  && ok "uninstall removed the generated version-status steering file" \
  || bad "uninstall left the generated version-status steering file behind"

# install.sh (day-zero bootstrap wrapper) should behave like "agentic-eng install".
HOME5="$(new_tmp_dir)"
BOOT_DIR="$(new_tmp_dir)/bootstrap-invoker"
mkdir -p "$BOOT_DIR"
( cd "$BOOT_DIR" && git_q init && git_q remote add origin "$FIXTURE4" )
cp "$AGENTIC_ENG" "$INSTALL_SH" "$BOOT_DIR/"
chmod +x "$BOOT_DIR/agentic-eng" "$BOOT_DIR/install.sh"
BOOT_OUT="$(AGENTIC_TOOLKIT_HOME="$HOME5" "$BOOT_DIR/install.sh" 2>&1)"
BOOT_EXIT=$?
if [ "$BOOT_EXIT" -eq 0 ] && [ -f "$(skill_file "$HOME5")" ]; then
  ok "install.sh (day-zero bootstrap) installs the toolkit same as 'agentic-eng install'"
else
  bad "install.sh did not produce a working install (exit $BOOT_EXIT): $BOOT_OUT"
fi
[ -x "$HOME5/.kiro/.um-agentic-engineering/bin/agentic-eng" ] \
  && ok "install.sh's run also self-installs agentic-eng to the persistent bin dir" \
  || bad "agentic-eng was not self-installed to the persistent bin dir"

#############################################################################
echo "--- scenario: missing/unreachable release source fails cleanly ---"
#############################################################################
HOME6="$(new_tmp_dir)"
BAD_INVOKER="$(new_tmp_dir)/bad-invoker"
mkdir -p "$BAD_INVOKER"
( cd "$BAD_INVOKER" && git_q init && git_q remote add origin "/nonexistent/path/does-not-exist" )
cp "$AGENTIC_ENG" "$BAD_INVOKER/agentic-eng"
chmod +x "$BAD_INVOKER/agentic-eng"
run "$BAD_INVOKER" "$HOME6" install
[ "$RUN_EXIT" -ne 0 ] \
  && ok "install fails cleanly (exit $RUN_EXIT) when the release source is unreachable" \
  || bad "install exited 0 despite an unreachable release source"
[ -z "$(find "$HOME6" -mindepth 1 2>/dev/null)" ] \
  && ok "a failed install leaves no misleading artifacts behind" \
  || bad "a failed install still wrote files under $HOME6"

echo "----------------------------------------"
echo "smoke test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
