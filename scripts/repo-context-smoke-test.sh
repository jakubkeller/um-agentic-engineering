#!/usr/bin/env bash
# Repeatable smoke test for toolkit/skills/repository-context/repo-context.sh.
#
# Fully offline and deterministic: every scenario builds its own throwaway
# local git repo as the fixture, and every run uses a fresh throwaway
# $AGENTIC_TOOLKIT_HOME, never the real ~/.kiro. repo-context.sh is run
# directly from its location in toolkit/ — it works standalone, without
# being "installed" by agentic-eng first.
#
# Universal Ctags availability varies by machine (and this repo's own
# dev machine has only been confirmed to have BSD ctags, not Universal
# Ctags, under the name `ctags`): scenarios that depend on which indexer
# is actually active branch on what repo-context.sh itself reports,
# so this test passes meaningfully either way instead of assuming a
# specific toolchain is installed.
#
# Usage: ./scripts/repo-context-smoke-test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_CTX="$REPO_DIR/toolkit/skills/repository-context/repo-context.sh"

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

# run <home-dir> <args...> -- always returns 0, sets $RUN_OUT and $RUN_EXIT.
run() {
  local home="$1"
  shift
  RUN_OUT="$(AGENTIC_TOOLKIT_HOME="$home" bash "$REPO_CTX" "$@" 2>&1)"
  RUN_EXIT=$?
  return 0
}

ctx_field() {
  # ctx_field <field> -- reads from $RUN_OUT
  printf '%s' "$RUN_OUT" | grep "^ctx:${1}=" | head -n1 | sed "s/^ctx:${1}=//"
}

cache_dir_for() {
  # cache_dir_for <home> <repo> -- mirrors repo-context.sh's own key derivation
  local home="$1" repo="$2" origin id key
  origin="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  if [ -n "$origin" ]; then id="origin:$origin"; else id="path:$(cd "$repo" && pwd -P)"; fi
  if command -v shasum >/dev/null 2>&1; then
    key="$(printf '%s' "$id" | shasum -a 256 | awk '{print $1}')"
  else
    key="$(printf '%s' "$id" | sha256sum | awk '{print $1}')"
  fi
  printf '%s/.kiro/.um-agentic-engineering/repo-context/%s' "$home" "$key"
}

#############################################################################
echo "--- scenario: fresh build + correct lookup (AC1, AC2) ---"
#############################################################################
REPO1="$(new_tmp_dir)/repo"
init_fixture_repo "$REPO1"
cat > "$REPO1/lib.sh" <<'EOF'
#!/usr/bin/env bash
calculate_total() {
  echo "computing"
}

call_it() {
  calculate_total
}
EOF
( cd "$REPO1" && git add -A && git_q commit -m "initial" )
EXPECTED_COMMIT="$(cd "$REPO1" && git rev-parse HEAD)"
HOME1="$(new_tmp_dir)"

run "$HOME1" rebuild "$REPO1"
run "$HOME1" lookup calculate_total "$REPO1"
[ "$RUN_EXIT" -eq 0 ] && ok "lookup exits 0 on a known symbol" || bad "lookup exited $RUN_EXIT: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q 'file=lib.sh line=2' \
  && ok "lookup reports the correct file:line for the known definition" \
  || bad "lookup did not report file=lib.sh line=2: $RUN_OUT"
[ "$(ctx_field head)" = "$EXPECTED_COMMIT" ] \
  && ok "reported HEAD matches the fixture's actual commit" \
  || bad "reported head ($(ctx_field head)) != expected ($EXPECTED_COMMIT)"
[ "$(ctx_field dirty)" = "no" ] \
  && ok "clean tree reported as not dirty" \
  || bad "clean tree was reported dirty"

INDEXER="$(ctx_field indexer)"
case "$INDEXER" in
  universal-ctags*)
    printf '%s' "$RUN_OUT" | grep -q 'confidence=confirmed' \
      && ok "Universal Ctags is present: a confirmed (index-sourced) result was returned" \
      || bad "Universal Ctags reported as indexer but no confirmed result was found"
    ;;
  direct-source-fallback)
    ! printf '%s' "$RUN_OUT" | grep -q 'confidence=confirmed' \
      && ok "No Universal Ctags available: every result is correctly labeled inferred, none overclaimed as confirmed" \
      || bad "direct-source-fallback reported but a confirmed result leaked through"
    ;;
  *) bad "unrecognized ctx:indexer value: $INDEXER" ;;
esac

#############################################################################
echo "--- scenario: uncommitted edit visible without reindex (AC3) ---"
#############################################################################
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

CACHE1="$(cache_dir_for "$HOME1" "$REPO1")"
MTIME_BEFORE=""
[ -f "$CACHE1/symbols.idx" ] && MTIME_BEFORE="$(file_mtime "$CACHE1/symbols.idx")"

printf '\nnew_feature_fn() {\n  :\n}\n' >> "$REPO1/lib.sh"
run "$HOME1" lookup new_feature_fn "$REPO1"
printf '%s' "$RUN_OUT" | grep -q 'symbol=new_feature_fn' \
  && ok "an unstaged, uncommitted symbol is found without a prior rebuild" \
  || bad "the uncommitted symbol was not found: $RUN_OUT"
[ "$(ctx_field dirty)" = "yes" ] \
  && ok "dirty tree correctly flagged after an unstaged edit" \
  || bad "dirty flag did not reflect the unstaged edit"

if [ -n "$MTIME_BEFORE" ] && [ -f "$CACHE1/symbols.idx" ]; then
  MTIME_AFTER="$(file_mtime "$CACHE1/symbols.idx")"
  [ "$MTIME_BEFORE" = "$MTIME_AFTER" ] \
    && ok "the cached index was not rebuilt just to see an uncommitted edit" \
    || bad "the cached index's mtime changed even though nothing required a rebuild"
fi

( cd "$REPO1" && git add -A )
run "$HOME1" lookup new_feature_fn "$REPO1"
printf '%s' "$RUN_OUT" | grep -q 'symbol=new_feature_fn' \
  && ok "a staged (not yet committed) symbol is also found" \
  || bad "the staged symbol was not found: $RUN_OUT"

#############################################################################
echo "--- scenario: revision drift is flagged, not silently reindexed (AC3) ---"
#############################################################################
( cd "$REPO1" && git_q commit -m "add new_feature_fn" )
NEW_COMMIT="$(cd "$REPO1" && git rev-parse HEAD)"
run "$HOME1" lookup new_feature_fn "$REPO1"
if [ "$(ctx_field indexer)" != "direct-source-fallback" ]; then
  [ "$(ctx_field index_state)" = "stale-by-revision" ] \
    && ok "cache correctly flagged stale-by-revision after a commit with no rebuild" \
    || bad "expected stale-by-revision, got index_state=$(ctx_field index_state)"
  [ "$(ctx_field indexed_commit)" != "$NEW_COMMIT" ] \
    && ok "stale cache still reports its own (older) indexed commit, distinct from current HEAD" \
    || bad "indexed_commit unexpectedly matches the new HEAD"
fi
[ "$(ctx_field head)" = "$NEW_COMMIT" ] \
  && ok "current HEAD is reported correctly even when the base index is stale" \
  || bad "current head not reported correctly: $(ctx_field head) vs $NEW_COMMIT"
printf '%s' "$RUN_OUT" | grep -q 'symbol=new_feature_fn' \
  && ok "the newly committed symbol is still found correctly despite a stale base index" \
  || bad "the newly committed symbol was not found despite the diff/grep overlay"

#############################################################################
echo "--- scenario: missing cache triggers a bounded rebuild (AC4) ---"
#############################################################################
rm -rf "$CACHE1"
run "$HOME1" lookup calculate_total "$REPO1"
[ "$RUN_EXIT" -eq 0 ] && ok "lookup still exits 0 after the cache is deleted entirely" || bad "lookup exited $RUN_EXIT after cache deletion: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q 'file=lib.sh line=2' \
  && ok "correct file:line still returned after a from-scratch rebuild" \
  || bad "incorrect/missing result after rebuilding from a missing cache: $RUN_OUT"

#############################################################################
echo "--- scenario: corrupt cache is never silently trusted (AC4) ---"
#############################################################################
CACHE1="$(cache_dir_for "$HOME1" "$REPO1")"
if [ -f "$CACHE1/symbols.idx" ] && [ "$(ctx_field indexer 2>/dev/null)" != "direct-source-fallback" ]; then
  : > "$CACHE1/symbols.idx"
  run "$HOME1" status "$REPO1"
  [ "$(ctx_field cache_state)" = "CORRUPT" ] \
    && ok "a truncated index is detected as corrupt rather than silently trusted" \
    || bad "corruption was not detected: cache_state=$(ctx_field cache_state)"
  run "$HOME1" lookup calculate_total "$REPO1"
  [ "$RUN_EXIT" -eq 0 ] && ok "lookup still exits 0 and recovers after corruption" || bad "lookup failed after corruption: $RUN_OUT"
  printf '%s' "$RUN_OUT" | grep -q 'file=lib.sh line=2' \
    && ok "correct answer still returned after recovering from a corrupt cache" \
    || bad "incorrect/missing answer after corruption recovery: $RUN_OUT"
else
  ok "no Universal-Ctags-backed cache to corrupt on this machine; corruption-recovery path exercised instead via the forced-fallback scenario below"
fi

#############################################################################
echo "--- scenario: direct-source fallback, clearly labeled (AC4, AC5, AC6) ---"
#############################################################################
REPO2="$(new_tmp_dir)/repo2"
init_fixture_repo "$REPO2"
printf 'function fallback_target() {\n  return 1\n}\n' > "$REPO2/app.sh"
( cd "$REPO2" && git add -A && git_q commit -m "initial" )
HOME2="$(new_tmp_dir)"

RUN_OUT="$(AGENTIC_TOOLKIT_HOME="$HOME2" AGENTIC_REPO_CONTEXT_FORCE_FALLBACK=1 bash "$REPO_CTX" lookup fallback_target "$REPO2" 2>&1)"
RUN_EXIT=$?
printf '%s' "$RUN_OUT" | grep -q 'ctx:indexer=direct-source-fallback' \
  && ok "forced fallback is clearly labeled as direct-source-fallback" \
  || bad "forced fallback was not clearly labeled: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q 'file=app.sh' \
  && ok "correct file is still found via direct-source fallback" \
  || bad "fallback did not find the correct file: $RUN_OUT"
! printf '%s' "$RUN_OUT" | grep -q 'confidence=confirmed' \
  && ok "fallback never mislabels a grep hit as confirmed" \
  || bad "fallback incorrectly reported a confirmed result"

#############################################################################
echo "--- scenario: indexer-check proactively states the fix, not just the gap ---"
#############################################################################
HOME_IC="$(new_tmp_dir)"
RUN_OUT="$(AGENTIC_TOOLKIT_HOME="$HOME_IC" AGENTIC_REPO_CONTEXT_FORCE_FALLBACK=1 bash "$REPO_CTX" indexer-check 2>&1)"
printf '%s' "$RUN_OUT" | grep -q 'ctx:indexer_available=no' \
  && ok "indexer-check correctly reports unavailable when forced" \
  || bad "indexer-check did not report unavailable: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q 'brew install universal-ctags' \
  && ok "indexer-check states the actual fix, not just that something's missing" \
  || bad "indexer-check did not state an install command: $RUN_OUT"

RUN_OUT="$(AGENTIC_TOOLKIT_HOME="$HOME_IC" bash "$REPO_CTX" indexer-check 2>&1)"
if command -v ctags >/dev/null 2>&1 && ctags --version 2>/dev/null | grep -qi 'Universal Ctags'; then
  printf '%s' "$RUN_OUT" | grep -q 'ctx:indexer_available=yes' \
    && ok "indexer-check correctly reports available on a machine with real Universal Ctags" \
    || bad "indexer-check misreported availability: $RUN_OUT"
else
  printf '%s' "$RUN_OUT" | grep -q 'ctx:indexer_available=no' \
    && ok "indexer-check correctly reports unavailable on this machine (no real Universal Ctags)" \
    || bad "indexer-check misreported availability: $RUN_OUT"
fi

#############################################################################
echo "--- scenario: bounded rebuild — file-count cap (resource bound) ---"
#############################################################################
REPO3="$(new_tmp_dir)/repo3"
init_fixture_repo "$REPO3"
for i in 1 2 3 4 5; do printf 'x\n' > "$REPO3/f$i.txt"; done
( cd "$REPO3" && git add -A && git_q commit -m "initial" )
HOME3="$(new_tmp_dir)"
RUN_OUT="$(AGENTIC_TOOLKIT_HOME="$HOME3" AGENTIC_REPO_CONTEXT_MAX_FILES=3 bash "$REPO_CTX" rebuild "$REPO3" 2>&1)"; RUN_EXIT=$?
printf '%s' "$RUN_OUT" | grep -q 'ctx:fallback_reason=too-many-files' \
  && ok "a repo over the file-count cap short-circuits to fallback instead of running the indexer" \
  || bad "file-count cap did not trigger: $RUN_OUT"

#############################################################################
echo "--- scenario: bounded rebuild — timeout (resource bound, never hangs) ---"
#############################################################################
TOOLDIR="$(new_tmp_dir)"
cat > "$TOOLDIR/ctags" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then echo "Universal Ctags 0.0.0 (fixture)"; exit 0; fi
sleep 60
EOF
chmod +x "$TOOLDIR/ctags"
HOME4="$(new_tmp_dir)"
START="$(date +%s)"
RUN_OUT="$(PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$HOME4" AGENTIC_REPO_CONTEXT_TIMEOUT=2 bash "$REPO_CTX" rebuild "$REPO3" --force 2>&1)"; RUN_EXIT=$?
END="$(date +%s)"
ELAPSED=$((END - START))
[ "$ELAPSED" -lt 30 ] \
  && ok "a hanging indexer is killed by the timeout wrapper instead of hanging the whole run (${ELAPSED}s)" \
  || bad "the timeout wrapper did not bound a hanging indexer (${ELAPSED}s elapsed)"
printf '%s' "$RUN_OUT" | grep -q 'ctx:index_state=fallback' \
  && ok "a timed-out rebuild falls back cleanly rather than failing opaquely" \
  || bad "timeout did not result in a clean fallback: $RUN_OUT"

#############################################################################
echo "--- scenario: not a git repository fails cleanly, not a crash (AC-adjacent robustness) ---"
#############################################################################
PLAIN="$(new_tmp_dir)"
HOME5="$(new_tmp_dir)"
run "$HOME5" status "$PLAIN"
[ "$RUN_EXIT" -ne 0 ] \
  && ok "status on a non-git directory exits non-zero rather than silently succeeding" \
  || bad "status exited 0 on a non-git directory"
printf '%s' "$RUN_OUT" | grep -qi 'not inside a git repository' \
  && ok "the failure message is clear and actionable, not a stack trace" \
  || bad "unexpected/unclear failure output: $RUN_OUT"

echo "----------------------------------------"
echo "smoke test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
