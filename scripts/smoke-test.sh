#!/usr/bin/env bash
# Repeatable smoke test for install.sh.
#
# Exercises the installer against a throwaway home directory (never the
# real $HOME) and checks the guarantees the PBI's acceptance criteria call
# for: a correct first install, idempotent re-install with no duplicate
# artifacts, preservation of unrelated personal files, a clean uninstall,
# and a clean failure when the release source is incomplete.
#
# This checks filesystem-level correctness only. It cannot drive the Kiro
# IDE itself — see docs/SETUP.md for the short manual check that confirms
# the sample skill actually triggers inside Kiro.
#
# Usage: ./scripts/smoke-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_DIR/install.sh"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$*" >&2; }

cleanup_dirs=()
cleanup() {
  for d in "${cleanup_dirs[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT

new_tmp_home() {
  local d
  d="$(mktemp -d)"
  cleanup_dirs+=("$d")
  printf '%s' "$d"
}

# --- 1. fresh install ---
HOME1="$(new_tmp_home)"
if AGENTIC_TOOLKIT_HOME="$HOME1" "$INSTALL_SH" >/dev/null 2>&1; then
  ok "fresh install exits 0"
else
  bad "fresh install exited non-zero"
fi

if [ -f "$HOME1/.kiro/skills/repo-snapshot/SKILL.md" ]; then
  ok "sample skill installed at the documented global path"
else
  bad "sample skill missing at ~/.kiro/skills/repo-snapshot/SKILL.md"
fi

if grep -q '^name: repo-snapshot$' "$HOME1/.kiro/skills/repo-snapshot/SKILL.md" 2>/dev/null; then
  ok "installed SKILL.md frontmatter name matches its folder name"
else
  bad "installed SKILL.md frontmatter name does not match folder name"
fi

if [ -f "$HOME1/.kiro/.um-agentic-engineering/install-manifest.txt" ] \
   && grep -q '^skills/repo-snapshot$' "$HOME1/.kiro/.um-agentic-engineering/install-manifest.txt"; then
  ok "manifest records the installed release and artifact"
else
  bad "manifest missing or does not record the installed artifact"
fi

# --- 2. idempotent re-install ---
BEFORE_COUNT="$(find "$HOME1/.kiro" -type f | wc -l | tr -d ' ')"
if AGENTIC_TOOLKIT_HOME="$HOME1" "$INSTALL_SH" >/dev/null 2>&1; then
  ok "second install exits 0"
else
  bad "second install exited non-zero"
fi
AFTER_COUNT="$(find "$HOME1/.kiro" -type f | wc -l | tr -d ' ')"
if [ "$BEFORE_COUNT" = "$AFTER_COUNT" ]; then
  ok "re-install produced no duplicate artifacts ($AFTER_COUNT files, unchanged)"
else
  bad "file count changed across re-install: $BEFORE_COUNT -> $AFTER_COUNT"
fi

# --- 3. unrelated personal files are left alone ---
HOME2="$(new_tmp_home)"
mkdir -p "$HOME2/.kiro/skills/my-own-skill"
printf 'untouched\n' > "$HOME2/.kiro/skills/my-own-skill/SKILL.md"
AGENTIC_TOOLKIT_HOME="$HOME2" "$INSTALL_SH" >/dev/null 2>&1 || true
if [ "$(cat "$HOME2/.kiro/skills/my-own-skill/SKILL.md")" = "untouched" ]; then
  ok "pre-existing, unrelated skill directory is left untouched"
else
  bad "install.sh modified a skill directory it did not create"
fi

# --- 4. uninstall removes exactly what was installed ---
if AGENTIC_TOOLKIT_HOME="$HOME2" "$INSTALL_SH" --uninstall >/dev/null 2>&1; then
  ok "uninstall exits 0"
else
  bad "uninstall exited non-zero"
fi
if [ ! -e "$HOME2/.kiro/skills/repo-snapshot" ] && [ -f "$HOME2/.kiro/skills/my-own-skill/SKILL.md" ]; then
  ok "uninstall removed the sample skill and left unrelated files in place"
else
  bad "uninstall removed too much or too little"
fi

# --- 5. missing release source fails cleanly, leaves nothing behind ---
BROKEN_DIR="$(mktemp -d)"
cleanup_dirs+=("$BROKEN_DIR")
cp "$INSTALL_SH" "$BROKEN_DIR/install.sh"
chmod +x "$BROKEN_DIR/install.sh"
HOME3="$(new_tmp_home)"
set +e
AGENTIC_TOOLKIT_HOME="$HOME3" "$BROKEN_DIR/install.sh" >/dev/null 2>&1
BROKEN_EXIT=$?
set -e
if [ "$BROKEN_EXIT" -ne 0 ]; then
  ok "install fails (exit $BROKEN_EXIT) when the release source is incomplete"
else
  bad "install exited 0 despite a missing toolkit/ directory"
fi
if [ -z "$(find "$HOME3" -mindepth 1 2>/dev/null)" ]; then
  ok "a failed install leaves no misleading artifacts behind"
else
  bad "a failed install still wrote files under $HOME3"
fi

echo "----------------------------------------"
echo "smoke test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
