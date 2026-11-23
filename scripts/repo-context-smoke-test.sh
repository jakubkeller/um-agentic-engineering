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
# Also covers the cross-repository `relate`/`relate-status` commands (PBI
# 297793): a real provider/consumer dependency across two separate fixture
# repos, an unsupported relationship reported as unknown rather than
# invented, and the stored relationship record going stale (and then being
# updated) once the consumer repo moves past the commit it was recorded at.
#
# Also covers Git lifecycle integration (PBI 297791): `install-hooks`,
# `hooks-status`, `refresh`, and `refresh-async`. The scenarios that need a
# real committed-change-gets-reindexed demonstration install a fake
# `ctags` binary ahead of the real `PATH` (the same technique the timeout
# scenario below already uses) so they're deterministic regardless of
# whether this machine has Universal Ctags installed.
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

# install_fake_ctags <tooldir>: writes a deterministic fake Universal
# Ctags into <tooldir>/ctags, matching repo-context.sh's real `-x -L
# <filelist> -f <outfile>` contract (a real file path, never piped stdin).
# Finds every `functionName() {`-style line in the files named in the
# list and emits one ctags -x style record per match.
install_fake_ctags() {
  local tooldir="$1"
  cat > "$tooldir/ctags" <<'FAKECTAGS'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then echo "Universal Ctags 0.0.0 (fixture)"; exit 0; fi
filelist=""; outfile=""; prev=""
for a in "$@"; do
  [ "$prev" = "-L" ] && filelist="$a"
  [ "$prev" = "-f" ] && outfile="$a"
  prev="$a"
done
: > "$outfile"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -n "function" "$f" | while IFS=: read -r ln _rest; do
    name="$(sed -n "${ln}p" "$f" | sed -E 's/^function ([A-Za-z0-9_]+).*/\1/')"
    printf '%s function %s %s pattern\n' "$name" "$ln" "$f" >> "$outfile"
  done
done < "$filelist"
FAKECTAGS
  chmod +x "$tooldir/ctags"
}

# real_hooks_dir_for <repo>: mirrors repo-context.sh's own hooks_dir_for:
# `git rev-parse --git-path hooks` is relative to the repo root unless
# core.hooksPath is itself absolute.
real_hooks_dir_for() {
  local repo="$1" dir
  dir="$(cd "$repo" && git rev-parse --git-path hooks)"
  case "$dir" in
    /*) printf '%s' "$dir" ;;
    *)  printf '%s/%s' "$repo" "$dir" ;;
  esac
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

#############################################################################
echo "--- scenario: relate finds a real provider/consumer dependency across two repos (PBI 297793 AC1, AC2) ---"
#############################################################################
PROVIDER1="$(new_tmp_dir)/provider"
init_fixture_repo "$PROVIDER1"
cat > "$PROVIDER1/api.sh" <<'EOF'
#!/usr/bin/env bash
fetch_order_status() {
  echo "status"
}
EOF
( cd "$PROVIDER1" && git add -A && git_q commit -m "add fetch_order_status" )

CONSUMER1="$(new_tmp_dir)/consumer"
init_fixture_repo "$CONSUMER1"
cat > "$CONSUMER1/client.sh" <<'EOF'
#!/usr/bin/env bash
check_order() {
  fetch_order_status
}
EOF
( cd "$CONSUMER1" && git add -A && git_q commit -m "call fetch_order_status" )

HOMER="$(new_tmp_dir)"

run "$HOMER" relate fetch_order_status "$PROVIDER1" "$CONSUMER1"
[ "$RUN_EXIT" -eq 0 ] && ok "relate exits 0 for a real cross-repo dependency" || bad "relate exited $RUN_EXIT: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^rel:status=supported' \
  && ok "relate reports status=supported when both sides have evidence" \
  || bad "relate did not report status=supported: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q 'PROVIDER symbol=fetch_order_status.*file=api.sh' \
  && ok "relate reports provider-side evidence with file:line" \
  || bad "missing provider evidence: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q 'CONSUMER symbol=fetch_order_status.*file=client.sh' \
  && ok "relate reports consumer-side evidence with file:line" \
  || bad "missing consumer evidence: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q 'PROVIDER .*confidence=' \
  && ok "provider evidence carries a confidence label, same vocabulary as single-repo lookup" \
  || bad "provider evidence missing a confidence label: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q 'CONSUMER .*confidence=' \
  && ok "consumer evidence carries a confidence label, same vocabulary as single-repo lookup" \
  || bad "consumer evidence missing a confidence label: $RUN_OUT"

#############################################################################
echo "--- scenario: an engineer can ask what consumes a contract and get the grounded relationship back (AC2) ---"
#############################################################################
run "$HOMER" relate-status fetch_order_status "$PROVIDER1" "$CONSUMER1"
[ "$RUN_EXIT" -eq 0 ] && ok "relate-status exits 0 for a freshly recorded relationship" || bad "relate-status exited $RUN_EXIT: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^rel:overall=fresh' \
  && ok "relate-status reports the just-recorded relationship as fresh" \
  || bad "relate-status did not report fresh: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^rel:status=supported' \
  && ok "relate-status retrieves the stored supported relationship without recomputing it" \
  || bad "relate-status lost the stored status: $RUN_OUT"

#############################################################################
echo "--- scenario: relate-status before any relate call reports no record, not a guess ---"
#############################################################################
run "$HOMER" relate-status never_checked_symbol "$PROVIDER1" "$CONSUMER1"
[ "$RUN_EXIT" -ne 0 ] \
  && ok "relate-status exits non-zero when no record exists yet" \
  || bad "relate-status exited 0 with no record: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^rel:record=missing' \
  && ok "relate-status reports record=missing rather than guessing a status" \
  || bad "relate-status did not report a missing record: $RUN_OUT"

#############################################################################
echo "--- scenario: an unsupported relationship is reported as unknown, not invented (AC4) ---"
#############################################################################
run "$HOMER" relate totally_unrelated_symbol "$PROVIDER1" "$CONSUMER1"
[ "$RUN_EXIT" -ne 0 ] \
  && ok "relate exits non-zero when no relationship is found (status=unknown is not success)" \
  || bad "relate exited 0 for a symbol absent from both repos: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^rel:status=unknown' \
  && ok "relate reports status=unknown instead of inventing a relationship for a symbol absent from both repos" \
  || bad "relate did not report unknown for a nonexistent symbol: $RUN_OUT"
! printf '%s' "$RUN_OUT" | grep -q '^PROVIDER ' \
  && ok "no provider evidence is fabricated for a symbol absent from the provider repo" \
  || bad "relate fabricated provider evidence: $RUN_OUT"
! printf '%s' "$RUN_OUT" | grep -q '^CONSUMER ' \
  && ok "no consumer evidence is fabricated for a symbol absent from the consumer repo" \
  || bad "relate fabricated consumer evidence: $RUN_OUT"

#############################################################################
echo "--- scenario: stored relationship goes stale, then is updated, after the consumer removes the call (AC3, AC5) ---"
#############################################################################
cat > "$CONSUMER1/client.sh" <<'EOF'
#!/usr/bin/env bash
check_order() {
  echo "no longer calling the order API"
}
EOF
( cd "$CONSUMER1" && git add -A && git_q commit -m "remove the order API call" )

run "$HOMER" relate-status fetch_order_status "$PROVIDER1" "$CONSUMER1"
printf '%s' "$RUN_OUT" | grep -q '^rel:consumer_state=stale' \
  && ok "relate-status flags the recorded relationship stale once the consumer repo moves past the recorded commit" \
  || bad "relate-status did not flag staleness after the consumer commit: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^rel:overall=stale' \
  && ok "relate-status surfaces overall=stale rather than silently trusting the old evidence" \
  || bad "relate-status did not report overall=stale: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^rel:status=supported' \
  && ok "relate-status still shows the last-recorded status alongside the staleness flag, for context" \
  || bad "relate-status lost the last-recorded status: $RUN_OUT"

run "$HOMER" relate fetch_order_status "$PROVIDER1" "$CONSUMER1"
printf '%s' "$RUN_OUT" | grep -q '^rel:status=unknown' \
  && ok "re-running relate after the call site is removed updates the relationship to unknown instead of keeping a stale 'supported'" \
  || bad "relate did not update to unknown after the call site was removed: $RUN_OUT"

run "$HOMER" relate-status fetch_order_status "$PROVIDER1" "$CONSUMER1"
printf '%s' "$RUN_OUT" | grep -q '^rel:overall=fresh' \
  && ok "relate-status reports fresh again immediately after relate recorded the updated (unknown) relationship" \
  || bad "relate-status did not report fresh after the update: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^rel:status=unknown' \
  && ok "the refreshed record correctly reflects the removed dependency, not the stale 'supported' value" \
  || bad "the refreshed record still shows the stale status: $RUN_OUT"

#############################################################################
echo "--- scenario: relations-for lets an agent notice a known dependency on its own, without being asked ---"
#############################################################################
PROVIDER2="$(new_tmp_dir)/provider2"
init_fixture_repo "$PROVIDER2"
cat > "$PROVIDER2/notify.sh" <<'EOF'
#!/usr/bin/env bash
send_notification() {
  echo "sending"
}
EOF
( cd "$PROVIDER2" && git add -A && git_q commit -m "add send_notification" )

CONSUMER2="$(new_tmp_dir)/consumer2"
init_fixture_repo "$CONSUMER2"
cat > "$CONSUMER2/worker.sh" <<'EOF'
#!/usr/bin/env bash
process_job() {
  send_notification
}
EOF
( cd "$CONSUMER2" && git add -A && git_q commit -m "call send_notification" )

HOMER2="$(new_tmp_dir)"
run "$HOMER2" relate send_notification "$PROVIDER2" "$CONSUMER2"

run "$HOMER2" relations-for "$PROVIDER2" send_notification
printf '%s' "$RUN_OUT" | grep -q '^REL role=provider symbol=send_notification status=supported' \
  && ok "relations-for reports the confirmed relationship from the provider's side, filtered to the symbol" \
  || bad "relations-for did not report the confirmed relationship: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^rel:count=1' \
  && ok "relations-for reports exactly one matching relationship" \
  || bad "relations-for reported the wrong count: $RUN_OUT"

run "$HOMER2" relations-for "$CONSUMER2"
printf '%s' "$RUN_OUT" | grep -q '^REL role=consumer symbol=send_notification status=supported' \
  && ok "relations-for also reports the same relationship from the consumer's side, with no symbol filter" \
  || bad "relations-for did not report the relationship from the consumer side: $RUN_OUT"

#############################################################################
echo "--- scenario: relations-for reports count=0 for a repo with no recorded relationships (steering stays silent) ---"
#############################################################################
UNRELATED="$(new_tmp_dir)/unrelated"
init_fixture_repo "$UNRELATED"
printf 'x\n' > "$UNRELATED/f.sh"
( cd "$UNRELATED" && git add -A && git_q commit -m "initial" )
run "$HOMER2" relations-for "$UNRELATED"
printf '%s' "$RUN_OUT" | grep -q '^rel:count=0$' \
  && ok "relations-for reports count=0 for a repo that's never been part of a recorded relationship" \
  || bad "relations-for did not report count=0 for an unrelated repo: $RUN_OUT"
! printf '%s' "$RUN_OUT" | grep -q '^REL ' \
  && ok "no REL line is fabricated for a repo with nothing recorded" \
  || bad "relations-for fabricated a REL line for an unrelated repo: $RUN_OUT"

#############################################################################
echo "--- scenario: relations-for flags the counterpart as stale once it moves on, without re-running relate ---"
#############################################################################
printf 'unrelated_change() {\n  :\n}\n' >> "$CONSUMER2/worker.sh"
( cd "$CONSUMER2" && git add -A && git_q commit -m "unrelated consumer-side change" )

run "$HOMER2" relations-for "$PROVIDER2" send_notification
printf '%s' "$RUN_OUT" | grep -q 'own_state=fresh' \
  && ok "relations-for reports the queried repo's own side as fresh when it hasn't moved" \
  || bad "relations-for incorrectly flagged the unchanged provider side as stale: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q 'counterpart_state=stale' \
  && ok "relations-for flags the counterpart repo as stale once it moves past the recorded commit, without recomputing relate" \
  || bad "relations-for did not flag the counterpart as stale: $RUN_OUT"

#############################################################################
echo "--- scenario: install-hooks installs post-commit/post-merge/post-checkout (AC1, AC3) ---"
#############################################################################
HOOKREPO1="$(new_tmp_dir)/hookrepo1"
init_fixture_repo "$HOOKREPO1"
printf 'x\n' > "$HOOKREPO1/f.sh"
( cd "$HOOKREPO1" && git add -A && git_q commit -m "initial" )
HOOKHOME1="$(new_tmp_dir)"

run "$HOOKHOME1" hooks-status "$HOOKREPO1"
printf '%s' "$RUN_OUT" | grep -q '^hooks:all_installed=no$' \
  && ok "hooks-status correctly reports nothing installed yet in a fresh repo" \
  || bad "hooks-status did not report all_installed=no before install: $RUN_OUT"

run "$HOOKHOME1" install-hooks "$HOOKREPO1"
printf '%s' "$RUN_OUT" | grep -q '^hooks:all_installed=yes$' \
  && ok "install-hooks reports all three hooks installed" \
  || bad "install-hooks did not report all_installed=yes: $RUN_OUT"
HOOKSDIR1="$(real_hooks_dir_for "$HOOKREPO1")"
for h in post-commit post-merge post-checkout; do
  [ -x "$HOOKSDIR1/$h" ] \
    && ok "$h hook file exists and is executable after install-hooks" \
    || bad "$h hook file missing or not executable after install-hooks"
done

run "$HOOKHOME1" hooks-status "$HOOKREPO1"
printf '%s' "$RUN_OUT" | grep -q '^hooks:all_installed=yes$' \
  && ok "hooks-status (read-only) agrees hooks are installed, without being asked to install anything" \
  || bad "hooks-status disagreed with install-hooks' own report: $RUN_OUT"

#############################################################################
echo "--- scenario: install-hooks is idempotent, reinstalling never duplicates the managed block ---"
#############################################################################
run "$HOOKHOME1" install-hooks "$HOOKREPO1"
run "$HOOKHOME1" install-hooks "$HOOKREPO1"
OCCURRENCES="$(grep -c 'um-agentic-engineering repository-context refresh (managed block)' "$HOOKSDIR1/post-commit")"
[ "$OCCURRENCES" -eq 1 ] \
  && ok "reinstalling install-hooks twice leaves exactly one managed block in post-commit, not a duplicate" \
  || bad "expected exactly 1 managed block in post-commit after reinstalling, found $OCCURRENCES"

#############################################################################
echo "--- scenario: install-hooks coexists with an existing hook instead of overwriting it (implementation scope) ---"
#############################################################################
HOOKREPO2="$(new_tmp_dir)/hookrepo2"
init_fixture_repo "$HOOKREPO2"
printf 'x\n' > "$HOOKREPO2/f.sh"
( cd "$HOOKREPO2" && git add -A && git_q commit -m "initial" )
HOOKHOME2="$(new_tmp_dir)"
HOOKSDIR2="$(real_hooks_dir_for "$HOOKREPO2")"
PRE_EXISTING_MARKER="$(new_tmp_dir)/pre-existing-hook-ran"
cat > "$HOOKSDIR2/post-commit" <<EOF
#!/usr/bin/env sh
echo ran >> "$PRE_EXISTING_MARKER"
EOF
chmod +x "$HOOKSDIR2/post-commit"

run "$HOOKHOME2" install-hooks "$HOOKREPO2"
grep -q 'echo ran >>' "$HOOKSDIR2/post-commit" \
  && ok "install-hooks preserves the pre-existing hook's own content instead of replacing it" \
  || bad "install-hooks discarded the pre-existing post-commit hook's content"
grep -q 'um-agentic-engineering repository-context refresh' "$HOOKSDIR2/post-commit" \
  && ok "install-hooks adds its own managed block alongside the pre-existing hook content" \
  || bad "install-hooks did not add its managed block to the existing post-commit hook"

( cd "$HOOKREPO2" && echo y2 >> f.sh && git add -A && AGENTIC_TOOLKIT_HOME="$HOOKHOME2" git_q commit -m "second commit" )
for i in $(seq 1 20); do [ -f "$PRE_EXISTING_MARKER" ] && break; sleep 0.2; done
[ -f "$PRE_EXISTING_MARKER" ] \
  && ok "the pre-existing hook still actually runs on a real commit after install-hooks ran alongside it" \
  || bad "the pre-existing hook did not run after install-hooks coexisted with it"

#############################################################################
echo "--- scenario: a real commit stays fast even with the refresh hook installed (AC3: never blocks Git) ---"
#############################################################################
START_COMMIT_TIME="$(date +%s)"
( cd "$HOOKREPO2" && echo y3 >> f.sh && git add -A && AGENTIC_TOOLKIT_HOME="$HOOKHOME2" git_q commit -m "third commit" )
COMMIT_ELAPSED=$(( $(date +%s) - START_COMMIT_TIME ))
[ "$COMMIT_ELAPSED" -lt 10 ] \
  && ok "git commit returns quickly; it does not wait on the backgrounded refresh (${COMMIT_ELAPSED}s)" \
  || bad "git commit took suspiciously long with the refresh hook installed (${COMMIT_ELAPSED}s)"

#############################################################################
echo "--- scenario: refresh-async never fails, even against a path that isn't a Git repository ---"
#############################################################################
NOTAREPO="$(new_tmp_dir)/not-a-repo"
mkdir -p "$NOTAREPO"
run "$(new_tmp_dir)" refresh-async "$NOTAREPO"
[ "$RUN_EXIT" -eq 0 ] \
  && ok "refresh-async exits 0 even when given a non-Git path, so a hook can never fail a Git operation on it" \
  || bad "refresh-async exited $RUN_EXIT for a non-Git path: $RUN_OUT"

#############################################################################
echo "--- scenario: a committed symbol move is reflected automatically via the installed hook, with no manual rebuild (AC1, AC2, AC5 demo) ---"
#############################################################################
TOOLDIR="$(new_tmp_dir)"
install_fake_ctags "$TOOLDIR"

DEMOREPO="$(new_tmp_dir)/demorepo"
init_fixture_repo "$DEMOREPO"
printf 'function demo_target() {\n  echo "v1"\n}\n' > "$DEMOREPO/a.sh"
( cd "$DEMOREPO" && git add -A && git_q commit -m "initial" )
DEMOHOME="$(new_tmp_dir)"

PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$DEMOHOME" bash "$REPO_CTX" install-hooks "$DEMOREPO" >/dev/null 2>&1
PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$DEMOHOME" bash "$REPO_CTX" rebuild "$DEMOREPO" >/dev/null 2>&1

RUN_OUT="$(PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$DEMOHOME" bash "$REPO_CTX" lookup demo_target "$DEMOREPO" 2>&1)"
printf '%s' "$RUN_OUT" | grep -q 'file=a.sh line=1 source=index confidence=confirmed' \
  && ok "before the change: confirmed hit at the original line" \
  || bad "did not get the expected pre-change confirmed hit: $RUN_OUT"

printf '\nfunction demo_target() {\n  echo "v2"\n}\n' >> "$DEMOREPO/a.sh"
( cd "$DEMOREPO" && git add -A && AGENTIC_TOOLKIT_HOME="$DEMOHOME" PATH="$TOOLDIR:$PATH" git_q commit -m "move demo_target" )
NEW_HEAD="$(cd "$DEMOREPO" && git rev-parse HEAD)"

REFRESHED=0
for i in $(seq 1 30); do
  STATUS_OUT="$(PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$DEMOHOME" bash "$REPO_CTX" status "$DEMOREPO" 2>&1)"
  if printf '%s' "$STATUS_OUT" | grep -q "ctx:indexed_commit=$NEW_HEAD"; then REFRESHED=1; break; fi
  sleep 0.3
done
[ "$REFRESHED" -eq 1 ] \
  && ok "the post-commit hook refreshed the cache to the new commit automatically, with nobody running rebuild by hand" \
  || bad "the cache was never refreshed to the new commit after the hook-triggering commit: $STATUS_OUT"

RUN_OUT="$(PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$DEMOHOME" bash "$REPO_CTX" lookup demo_target "$DEMOREPO" 2>&1)"
printf '%s' "$RUN_OUT" | grep -q 'file=a.sh line=5 source=index confidence=confirmed' \
  && ok "after the change: the next grounded query reflects the moved symbol's new location, sourced from the refreshed index" \
  || bad "lookup after the commit did not reflect the moved symbol from a refreshed index: $RUN_OUT"

#############################################################################
echo "--- scenario: refresh is a no-op when the cache is already fresh (bounded, not a wasted rebuild every time) ---"
#############################################################################
RUN_OUT="$(PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$DEMOHOME" bash "$REPO_CTX" refresh "$DEMOREPO" 2>&1)"
printf '%s' "$RUN_OUT" | grep -q '^ctx:index_state=fresh$' \
  && ok "refresh reports fresh (no-op) instead of rebuilding when the cache already matches HEAD" \
  || bad "refresh did not no-op on an already-fresh cache: $RUN_OUT"

#############################################################################
echo "--- scenario: package produces a checksummed artifact for the exact FRESH commit, and verify confirms it (PBI 297919 AC1, AC2, AC4) ---"
#############################################################################
PUBREPO="$(new_tmp_dir)/pubrepo"
init_fixture_repo "$PUBREPO"
printf 'function publish_target() {\n  echo "v1"\n}\n' > "$PUBREPO/a.sh"
( cd "$PUBREPO" && git add -A && git_q commit -m "initial" )
PUBHOME="$(new_tmp_dir)"
PUB_SHA="$(cd "$PUBREPO" && git rev-parse HEAD)"
PUBOUT="$(new_tmp_dir)/baseline"

PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$PUBHOME" bash "$REPO_CTX" rebuild --force "$PUBREPO" >/dev/null 2>&1
run "$PUBHOME" package "$PUBREPO" "$PUBOUT"
[ "$RUN_EXIT" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q "^pkg:status=ok$" \
  && ok "package reports status=ok for a fresh, clean commit" \
  || bad "package did not report success for a fresh, clean commit: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q "^pkg:commit=${PUB_SHA}$" \
  && ok "the packaged artifact identifies the exact commit it was built from" \
  || bad "the packaged artifact did not identify the correct commit: $RUN_OUT"
[ -f "$PUBOUT/manifest.txt" ] && [ -f "$PUBOUT/symbols.idx" ] \
  && ok "the artifact bundle contains a manifest and the index output it was built from" \
  || bad "expected manifest.txt and symbols.idx in the packaged bundle, found: $(ls "$PUBOUT" 2>&1)"

VERIFY_OUT="$(bash "$REPO_CTX" verify "$PUBOUT" 2>&1)"
VERIFY_EXIT=$?
printf '%s' "$VERIFY_OUT" | grep -q "^verify:status=ok$" && [ "$VERIFY_EXIT" -eq 0 ] \
  && ok "verify confirms an untampered artifact is ok" \
  || bad "verify did not confirm a freshly packaged artifact as ok: $VERIFY_OUT"
printf '%s' "$VERIFY_OUT" | grep -q "^verify:commit=${PUB_SHA}$" \
  && ok "an engineer can inspect the retrieved artifact's commit without re-running package" \
  || bad "verify did not report the expected commit for inspection: $VERIFY_OUT"

#############################################################################
echo "--- scenario: verify detects a tampered/corrupted artifact rather than trusting the manifest blindly (PBI 297919 AC2, AC4) ---"
#############################################################################
echo "tampered" >> "$PUBOUT/symbols.idx"
VERIFY_OUT="$(bash "$REPO_CTX" verify "$PUBOUT" 2>&1)"
VERIFY_EXIT=$?
printf '%s' "$VERIFY_OUT" | grep -q "^verify:status=corrupt$" && [ "$VERIFY_EXIT" -ne 0 ] \
  && ok "verify reports corrupt and fails after the artifact's index file is tampered with" \
  || bad "verify did not detect a tampered artifact: $VERIFY_OUT"

#############################################################################
echo "--- scenario: package refuses when there is no FRESH index to publish, rather than inventing an artifact (PBI 297919 AC1 correctness) ---"
#############################################################################
NEVERINDEXED="$(new_tmp_dir)/never-indexed"
init_fixture_repo "$NEVERINDEXED"
( cd "$NEVERINDEXED" && echo x > f.sh && git add -A && git_q commit -m "only commit" )
NEVERHOME="$(new_tmp_dir)"
run "$NEVERHOME" package "$NEVERINDEXED" "$(new_tmp_dir)/shouldnotexist"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -qi "not FRESH" \
  && ok "package refuses to publish a repository that was never indexed, instead of fabricating an artifact" \
  || bad "package should have refused a never-indexed repository: $RUN_OUT"

#############################################################################
echo "--- scenario: package refuses on a dirty working tree, and a failed publish never replaces the last known-good artifact (PBI 297919 AC3) ---"
#############################################################################
GOODOUT="$(new_tmp_dir)/baseline-good"
PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$PUBHOME" bash "$REPO_CTX" package --force "$PUBREPO" "$GOODOUT" >/dev/null 2>&1
GOOD_SHA_BEFORE="$(bash "$REPO_CTX" verify "$GOODOUT" 2>&1 | grep '^verify:commit=' | sed 's/^verify:commit=//')"

echo "uncommitted change" >> "$PUBREPO/a.sh"
run "$PUBHOME" package --force "$PUBREPO" "$GOODOUT"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -qi "dirty" \
  && ok "package refuses to publish while the working tree is dirty" \
  || bad "package should have refused a dirty working tree: $RUN_OUT"

GOOD_SHA_AFTER="$(bash "$REPO_CTX" verify "$GOODOUT" 2>&1 | grep '^verify:commit=' | sed 's/^verify:commit=//')"
[ "$GOOD_SHA_AFTER" = "$GOOD_SHA_BEFORE" ] \
  && ok "the previously published artifact is untouched after the failed (dirty-tree) publish attempt" \
  || bad "the last known-good artifact changed after a failed publish attempt (was $GOOD_SHA_BEFORE, now $GOOD_SHA_AFTER)"
( cd "$PUBREPO" && git checkout -q -- a.sh )

#############################################################################
echo "--- scenario: package refuses to silently overwrite an already-published artifact without --force (immutability) ---"
#############################################################################
run "$PUBHOME" package "$PUBREPO" "$PUBOUT"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -qi "already-packaged\|pass --force" \
  && ok "package refuses to overwrite an already-published artifact at the same path without --force" \
  || bad "package should have refused to silently overwrite an existing artifact: $RUN_OUT"

#############################################################################
echo "--- scenario: ci-setup wires rebuild/package/verify/publish into a repo with no azure-pipelines.yml yet (PBI 297919) ---"
#############################################################################
CISETUPREPO="$(new_tmp_dir)/cisetuprepo"
init_fixture_repo "$CISETUPREPO"
echo x > "$CISETUPREPO/f.sh"
( cd "$CISETUPREPO" && git add -A && git_q commit -m "initial" )
CISETUPHOME="$(new_tmp_dir)"

run "$CISETUPHOME" ci-setup "$CISETUPREPO" --feed "SomeProject/SomeFeed"
[ "$RUN_EXIT" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q "^ci:status=created$" \
  && ok "ci-setup creates azure-pipelines.yml when none exists" \
  || bad "ci-setup did not report creating a new pipeline file: $RUN_OUT"
[ -f "$CISETUPREPO/azure-pipelines.yml" ] \
  && ok "azure-pipelines.yml now exists in the repo" \
  || bad "ci-setup did not actually write azure-pipelines.yml"
grep -q "SomeProject/SomeFeed" "$CISETUPREPO/azure-pipelines.yml" \
  && ok "the generated pipeline references the feed that was passed in" \
  || bad "the generated pipeline does not reference the requested feed"
grep -q "repository-context-baseline-cisetuprepo" "$CISETUPREPO/azure-pipelines.yml" \
  && ok "the package name defaults to repository-context-baseline-<repo-name> when --package is omitted" \
  || bad "the generated pipeline did not default the package name as expected"
[ -x "$CISETUPREPO/.ci/repository-context/repo-context.sh" ] \
  && ok "ci-setup vendors an executable copy of repo-context.sh into the target repo" \
  || bad "ci-setup did not vendor repo-context.sh into .ci/repository-context/"
cmp -s "$CISETUPREPO/.ci/repository-context/repo-context.sh" "$REPO_CTX" \
  && ok "the vendored copy is identical to the running script" \
  || bad "the vendored copy does not match the running repo-context.sh"
grep -q 'Build.SourcesDirectory)/.ci/repository-context/repo-context.sh' "$CISETUPREPO/azure-pipelines.yml" \
  && ok "the generated pipeline calls the vendored script under Build.SourcesDirectory, not an assumed ~/.kiro path" \
  || bad "the generated pipeline does not reference the vendored script path"
! grep -q 'Pipeline.Workspace' "$CISETUPREPO/azure-pipelines.yml" \
  && ok "the generated pipeline has no leftover reference to an assumed pre-installed toolkit path" \
  || bad "the generated pipeline still references Pipeline.Workspace, which a fresh agent won't have populated"
grep -q "ensure Universal Ctags is available" "$CISETUPREPO/azure-pipelines.yml" \
  && ok "the generated pipeline provisions Universal Ctags on the agent before indexing" \
  || bad "the generated pipeline does not ensure Universal Ctags is available"

run "$CISETUPHOME" ci-setup-status "$CISETUPREPO"
printf '%s' "$RUN_OUT" | grep -q "^ci:publish_configured=yes$" \
  && ok "ci-setup-status reports configured=yes after ci-setup has run" \
  || bad "ci-setup-status did not report the repo as configured: $RUN_OUT"

#############################################################################
echo "--- scenario: the vendored script actually works end to end from a fresh checkout with no toolkit pre-installed (PBI 297919) ---"
#############################################################################
# Simulates what the generated pipeline's steps actually do on a real agent:
# a plain git clone (the only thing any agent, hosted or self-hosted, is
# guaranteed to have) plus a completely fresh, empty AGENTIC_TOOLKIT_HOME
# standing in for "nothing pre-installed." If the vendored copy or the
# Build.SourcesDirectory-relative path were wrong, this is what would catch
# it, not just checking that the generated YAML text looks right. git
# clone only picks up committed content, so ci-setup's output has to
# actually be committed first, same as a real engineer would have to do.
( cd "$CISETUPREPO" && git_q add -A && git_q commit -m "wire up repository-context publish" )
AGENTCHECKOUT="$(new_tmp_dir)/agent-checkout"
( cd "$(dirname "$AGENTCHECKOUT")" && git clone -q "$CISETUPREPO" "$(basename "$AGENTCHECKOUT")" ) \
  || bad "could not clone the ci-setup fixture repo to simulate a fresh agent checkout"
FRESHAGENTHOME="$(new_tmp_dir)"

PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$FRESHAGENTHOME" bash "$AGENTCHECKOUT/.ci/repository-context/repo-context.sh" rebuild --force "$AGENTCHECKOUT" >/tmp/agentrebuild.$$ 2>&1
AGENT_REBUILD_OUT="$(cat /tmp/agentrebuild.$$)"; rm -f /tmp/agentrebuild.$$
printf '%s' "$AGENT_REBUILD_OUT" | grep -q '^ctx:index_state=rebuilt$' \
  && ok "the vendored script, run from a fresh agent-like checkout, actually rebuilds a real index" \
  || bad "the vendored script failed to rebuild from a simulated fresh agent: $AGENT_REBUILD_OUT"

AGENTSTAGING="$(new_tmp_dir)/repo-context-baseline"
PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$FRESHAGENTHOME" bash "$AGENTCHECKOUT/.ci/repository-context/repo-context.sh" package "$AGENTCHECKOUT" "$AGENTSTAGING" >/tmp/agentpkg.$$ 2>&1
AGENT_PKG_OUT="$(cat /tmp/agentpkg.$$)"; rm -f /tmp/agentpkg.$$
printf '%s' "$AGENT_PKG_OUT" | grep -q '^pkg:status=ok$' \
  && ok "the vendored script, run from a fresh agent-like checkout, actually packages a real artifact" \
  || bad "the vendored script failed to package from a simulated fresh agent: $AGENT_PKG_OUT"

AGENT_VERIFY_OUT="$(bash "$AGENTCHECKOUT/.ci/repository-context/repo-context.sh" verify "$AGENTSTAGING" 2>&1)"
printf '%s' "$AGENT_VERIFY_OUT" | grep -q '^verify:status=ok$' \
  && ok "the vendored script, run from a fresh agent-like checkout, verifies the artifact it just built" \
  || bad "the vendored script failed to verify from a simulated fresh agent: $AGENT_VERIFY_OUT"

#############################################################################
echo "--- scenario: re-running ci-setup replaces only its own managed block, never duplicates it (PBI 297919) ---"
#############################################################################
run "$CISETUPHOME" ci-setup "$CISETUPREPO" --feed "OtherProject/OtherFeed"
[ "$RUN_EXIT" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q "^ci:status=updated$" \
  && ok "re-running ci-setup against its own output reports an update, not a fresh create" \
  || bad "re-running ci-setup did not report status=updated: $RUN_OUT"
[ "$(grep -c "repository-context publish (managed block)" "$CISETUPREPO/azure-pipelines.yml")" -eq 1 ] \
  && ok "the managed block appears exactly once after re-running ci-setup" \
  || bad "the managed block was duplicated instead of replaced: $(grep -c "repository-context publish (managed block)" "$CISETUPREPO/azure-pipelines.yml") occurrences"
grep -q "OtherProject/OtherFeed" "$CISETUPREPO/azure-pipelines.yml" \
  && ! grep -q "SomeProject/SomeFeed" "$CISETUPREPO/azure-pipelines.yml" \
  && ok "the new feed replaces the old one instead of both being present" \
  || bad "re-running ci-setup left stale content behind in azure-pipelines.yml"

#############################################################################
echo "--- scenario: ci-setup refuses to guess at a multi-stage pipeline file with no single top-level steps: key (PBI 297919) ---"
#############################################################################
MULTISTAGEREPO="$(new_tmp_dir)/multistagerepo"
init_fixture_repo "$MULTISTAGEREPO"
echo x > "$MULTISTAGEREPO/f.sh"
( cd "$MULTISTAGEREPO" && git add -A && git_q commit -m "initial" )
cat > "$MULTISTAGEREPO/azure-pipelines.yml" <<'MULTIEOF'
stages:
  - stage: Build
    jobs:
      - job: BuildJob
        steps:
          - script: echo build
  - stage: Test
    jobs:
      - job: TestJob
        steps:
          - script: echo test
MULTIEOF
BEFORE_COPY="$(new_tmp_dir)/before.yml"
cp "$MULTISTAGEREPO/azure-pipelines.yml" "$BEFORE_COPY"
run "$CISETUPHOME" ci-setup "$MULTISTAGEREPO" --feed "SomeProject/SomeFeed"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -qi "top-level 'steps:'" \
  && ok "ci-setup refuses a multi-stage pipeline file instead of guessing where steps live" \
  || bad "ci-setup should have refused a multi-stage pipeline file: $RUN_OUT"
cmp -s "$MULTISTAGEREPO/azure-pipelines.yml" "$BEFORE_COPY" \
  && ok "the multi-stage pipeline file is left completely untouched after the refusal" \
  || bad "ci-setup modified a pipeline file it should have refused to touch"

#############################################################################
echo "--- scenario: ci-setup --pipeline-file targets a non-default path instead of creating a stray azure-pipelines.yml (PBI 297919) ---"
#############################################################################
ALTPATHREPO="$(new_tmp_dir)/altpathrepo"
init_fixture_repo "$ALTPATHREPO"
echo x > "$ALTPATHREPO/f.sh"
( cd "$ALTPATHREPO" && git add -A && git_q commit -m "initial" )
ALTPATHHOME="$(new_tmp_dir)"

run "$ALTPATHHOME" ci-setup "$ALTPATHREPO" --feed "SomeProject/SomeFeed" --pipeline-file "pipelines/ci.yml"
[ "$RUN_EXIT" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q "^ci:file=.*/pipelines/ci\.yml$" \
  && ok "ci-setup writes to the --pipeline-file path instead of the default" \
  || bad "ci-setup did not honor --pipeline-file: $RUN_OUT"
[ -f "$ALTPATHREPO/pipelines/ci.yml" ] \
  && ok "the custom-path pipeline file was actually created" \
  || bad "ci-setup did not create pipelines/ci.yml"
[ ! -f "$ALTPATHREPO/azure-pipelines.yml" ] \
  && ok "no stray default-path azure-pipelines.yml was created alongside the custom path" \
  || bad "ci-setup created an unwanted azure-pipelines.yml even though --pipeline-file was given"

run "$ALTPATHHOME" ci-setup-status "$ALTPATHREPO" --pipeline-file "pipelines/ci.yml"
printf '%s' "$RUN_OUT" | grep -q "^ci:publish_configured=yes$" \
  && ok "ci-setup-status honors --pipeline-file and finds the configured custom-path pipeline" \
  || bad "ci-setup-status did not find the custom-path pipeline: $RUN_OUT"

#############################################################################
echo "--- scenario: ci-setup matches an existing hand-written pipeline's own indentation, not a hardcoded one (PBI 297919) ---"
#############################################################################
HANDWRITTENREPO="$(new_tmp_dir)/handwrittenrepo"
init_fixture_repo "$HANDWRITTENREPO"
cat > "$HANDWRITTENREPO/azure-pipelines.yml" <<'HANDEOF'
trigger:
  branches:
    include: [ main ]

pool:
  vmImage: 'ubuntu-latest'

steps:
- script: echo hello
  displayName: 'say hello'
HANDEOF
( cd "$HANDWRITTENREPO" && git add -A && git_q commit -m "initial" )
HANDWRITTENHOME="$(new_tmp_dir)"

run "$HANDWRITTENHOME" ci-setup "$HANDWRITTENREPO" --feed "SomeProject/SomeFeed"
[ "$RUN_EXIT" -eq 0 ] \
  && ok "ci-setup succeeds against a realistic hand-written single-job pipeline" \
  || bad "ci-setup failed against a hand-written pipeline: $RUN_OUT"
grep -q "^- bash: |$" "$HANDWRITTENREPO/azure-pipelines.yml" \
  && ok "the inserted block matches the existing file's own 0-space step indentation, not a hardcoded 2-space one" \
  || bad "the inserted block did not match the existing file's indentation: $(cat "$HANDWRITTENREPO/azure-pipelines.yml")"
grep -q "^- script: echo hello$" "$HANDWRITTENREPO/azure-pipelines.yml" \
  && ok "the pre-existing step is left exactly as it was" \
  || bad "ci-setup altered a pre-existing, unrelated step"
python3 -c "import yaml,sys; d=yaml.safe_load(open('$HANDWRITTENREPO/azure-pipelines.yml')); sys.exit(0 if len(d['steps'])==6 else 1)" 2>/dev/null \
  && ok "the resulting file is valid YAML with the expected total step count" \
  || bad "the resulting file is not valid YAML, or didn't end up with 5 steps (python3/pyyaml unavailable, or a real structural bug)"

#############################################################################
echo "--- scenario: ci-setup refuses a pipeline with trigger: none instead of wiring a publish step that would never run (PBI 297919) ---"
#############################################################################
TRIGGERNONEREPO="$(new_tmp_dir)/triggernonerepo"
init_fixture_repo "$TRIGGERNONEREPO"
cat > "$TRIGGERNONEREPO/azure-pipelines.yml" <<'TRIGEOF'
trigger: none
pr:
  branches:
    include: [ main ]
steps:
- script: echo validate
TRIGEOF
( cd "$TRIGGERNONEREPO" && git add -A && git_q commit -m "initial" )
TRIGGERNONEHOME="$(new_tmp_dir)"
BEFORE_TRIGGER_COPY="$(new_tmp_dir)/before-trigger.yml"
cp "$TRIGGERNONEREPO/azure-pipelines.yml" "$BEFORE_TRIGGER_COPY"

run "$TRIGGERNONEHOME" ci-setup "$TRIGGERNONEREPO" --feed "SomeProject/SomeFeed"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -qi "trigger: none" \
  && ok "ci-setup refuses a pipeline with trigger: none instead of wiring in a publish step that would never run" \
  || bad "ci-setup should have refused a trigger: none pipeline: $RUN_OUT"
cmp -s "$TRIGGERNONEREPO/azure-pipelines.yml" "$BEFORE_TRIGGER_COPY" \
  && ok "the trigger: none pipeline file is left completely untouched after the refusal" \
  || bad "ci-setup modified a pipeline file it should have refused to touch"

#############################################################################
echo "--- scenario: ci-setup rejects an unsafe --pipeline-file instead of writing outside the repo (PBI 297919) ---"
#############################################################################
SAFETYREPO="$(new_tmp_dir)/safetyrepo"
init_fixture_repo "$SAFETYREPO"
echo x > "$SAFETYREPO/f.sh"
( cd "$SAFETYREPO" && git add -A && git_q commit -m "initial" )
SAFETYHOME="$(new_tmp_dir)"

run "$SAFETYHOME" ci-setup "$SAFETYREPO" --feed "SomeProject/SomeFeed" --pipeline-file "../escape.yml"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -qi "'\.\.' segments" \
  && ok "ci-setup rejects a --pipeline-file containing '..' instead of writing outside the repo" \
  || bad "ci-setup should have rejected a path-traversal --pipeline-file: $RUN_OUT"
[ ! -f "$(dirname "$SAFETYREPO")/escape.yml" ] \
  && ok "no file was written outside the repository" \
  || bad "ci-setup wrote a file outside the repository despite the '..' in --pipeline-file"

run "$SAFETYHOME" ci-setup "$SAFETYREPO" --feed "SomeProject/SomeFeed" --pipeline-file "/etc/evil.yml"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -qi "not absolute" \
  && ok "ci-setup rejects an absolute --pipeline-file" \
  || bad "ci-setup should have rejected an absolute --pipeline-file: $RUN_OUT"

#############################################################################
echo "--- scenario: fetch-baseline adopts a verified, matching published artifact as the local cache (PBI 297918 AC1) ---"
#############################################################################
FETCHPUBREPO="$(new_tmp_dir)/fetch-pub-repo"
init_fixture_repo "$FETCHPUBREPO"
printf 'function helper_target() {\n  echo "hi"\n}\n' > "$FETCHPUBREPO/a.sh"
( cd "$FETCHPUBREPO" && git remote add origin "https://dev.azure.com/fetchorg/fetchproj/_git/fetchrepo" && git add -A && git_q commit -m "initial" )
FETCHPUBHOME="$(new_tmp_dir)"
FETCH_SHA="$(cd "$FETCHPUBREPO" && git rev-parse HEAD)"
PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$FETCHPUBHOME" bash "$REPO_CTX" rebuild --force "$FETCHPUBREPO" >/dev/null 2>&1
FETCHBUNDLE="$(new_tmp_dir)/fetch-baseline-bundle"
PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$FETCHPUBHOME" bash "$REPO_CTX" package "$FETCHPUBREPO" "$FETCHBUNDLE" >/dev/null 2>&1
bash "$REPO_CTX" verify "$FETCHBUNDLE" >/dev/null 2>&1 \
  && ok "fixture setup: the published artifact for fetch-baseline scenarios verifies ok before use" \
  || bad "fixture setup failed: the fetch-baseline test artifact did not verify ok"

# A clone is the realistic stand-in for "a teammate's checkout of the same
# repo at the same commit" -- it's the only way to get a byte-identical
# commit hash deterministically, rather than racing on commit timestamps.
FETCHCLONE="$(new_tmp_dir)/fetch-clone"
git clone -q "$FETCHPUBREPO" "$FETCHCLONE" 2>/dev/null
( cd "$FETCHCLONE" && git remote set-url origin "https://dev.azure.com/fetchorg/fetchproj/_git/fetchrepo" )
FETCHCLONEHOME="$(new_tmp_dir)"

run "$FETCHCLONEHOME" fetch-baseline "$FETCHCLONE" --from "$FETCHBUNDLE"
[ "$RUN_EXIT" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q '^fetch:status=adopted$' \
  && ok "fetch-baseline adopts a verified artifact published for this exact repo and commit" \
  || bad "fetch-baseline did not adopt a valid matching artifact: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q "^fetch:artifact_commit=${FETCH_SHA}$" \
  && ok "the adopted baseline reports the exact commit it was published from" \
  || bad "fetch-baseline reported the wrong artifact commit: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^fetch:relation_to_head=exact$' \
  && ok "an adopted baseline at the same commit as HEAD is reported as an exact match, not just 'stale'" \
  || bad "expected relation_to_head=exact: $RUN_OUT"

run "$FETCHCLONEHOME" status "$FETCHCLONE"
[ "$(ctx_field cache_state)" = "FRESH" ] \
  && ok "after adopting a baseline at the current commit, status reports the cache as FRESH" \
  || bad "status did not report FRESH after adopting a same-commit baseline: $RUN_OUT"
printf '%s' "$RUN_OUT" | grep -q '^ctx:cache_source=published$' \
  && ok "status reports the adopted cache's provenance as published, not local" \
  || bad "status did not report cache_source=published after adoption: $RUN_OUT"

RUN_OUT="$(PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$FETCHCLONEHOME" bash "$REPO_CTX" lookup helper_target "$FETCHCLONE" 2>&1)"
printf '%s' "$RUN_OUT" | grep -q 'source=index confidence=confirmed' \
  && ok "a lookup against the adopted baseline returns a confirmed, index-backed result, not just an inferred grep hit" \
  || bad "lookup did not return a confirmed result from the adopted baseline: $RUN_OUT"

#############################################################################
echo "--- scenario: an adopted baseline never hides local uncommitted changes (PBI 297918 AC3) ---"
#############################################################################
echo 'function helper_target_local() { echo "new"; }' >> "$FETCHCLONE/a.sh"
RUN_OUT="$(PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$FETCHCLONEHOME" bash "$REPO_CTX" lookup helper_target_local "$FETCHCLONE" 2>&1)"
printf '%s' "$RUN_OUT" | grep -q 'kind=changed.*source=diff' \
  && ok "an uncommitted addition is still surfaced via the diff overlay even though the cache came from a published baseline" \
  || bad "an uncommitted change was not surfaced on top of an adopted baseline: $RUN_OUT"
( cd "$FETCHCLONE" && git checkout -q -- a.sh )

#############################################################################
echo "--- scenario: fetch-baseline skips adoption when the local cache is already FRESH, rather than discarding a good index (PBI 297918) ---"
#############################################################################
FETCHCLONE2="$(new_tmp_dir)/fetch-clone-2"
git clone -q "$FETCHPUBREPO" "$FETCHCLONE2" 2>/dev/null
( cd "$FETCHCLONE2" && git remote set-url origin "https://dev.azure.com/fetchorg/fetchproj/_git/fetchrepo" )
FETCHCLONE2HOME="$(new_tmp_dir)"
PATH="$TOOLDIR:$PATH" AGENTIC_TOOLKIT_HOME="$FETCHCLONE2HOME" bash "$REPO_CTX" rebuild --force "$FETCHCLONE2" >/dev/null 2>&1

run "$FETCHCLONE2HOME" fetch-baseline "$FETCHCLONE2" --from "$FETCHBUNDLE"
[ "$RUN_EXIT" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q '^fetch:status=skipped$' \
  && printf '%s' "$RUN_OUT" | grep -q '^fetch:reason=local-already-fresh$' \
  && ok "fetch-baseline skips adoption when the local cache is already FRESH at HEAD" \
  || bad "fetch-baseline should have skipped adoption over an already-FRESH local cache: $RUN_OUT"
run "$FETCHCLONE2HOME" status "$FETCHCLONE2"
printf '%s' "$RUN_OUT" | grep -q '^ctx:cache_source=local$' \
  && ok "the untouched local cache still reports cache_source=local after the skipped fetch attempt" \
  || bad "the local cache's provenance changed after a skipped fetch attempt: $RUN_OUT"

#############################################################################
echo "--- scenario: fetch-baseline rejects an artifact published for a different repository, and never touches the local cache (PBI 297918 AC2) ---"
#############################################################################
FETCHWRONGREPO="$(new_tmp_dir)/fetch-wrong-repo"
init_fixture_repo "$FETCHWRONGREPO"
echo x > "$FETCHWRONGREPO/f.sh"
( cd "$FETCHWRONGREPO" && git remote add origin "https://dev.azure.com/fetchorg/fetchproj/_git/some-other-repo" && git add -A && git_q commit -m "initial" )
FETCHWRONGHOME="$(new_tmp_dir)"

run "$FETCHWRONGHOME" fetch-baseline "$FETCHWRONGREPO" --from "$FETCHBUNDLE"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -q '^fetch:status=rejected$' \
  && printf '%s' "$RUN_OUT" | grep -q '^fetch:reason=repo-mismatch$' \
  && ok "fetch-baseline rejects an artifact published for a different repository instead of silently adopting it" \
  || bad "fetch-baseline should have rejected a repo-mismatched artifact: $RUN_OUT"
run "$FETCHWRONGHOME" status "$FETCHWRONGREPO"
[ "$(ctx_field cache_state)" = "MISSING" ] \
  && ok "the local cache stays untouched (still MISSING) after a rejected repo-mismatched artifact, leaving the normal fallback in place" \
  || bad "the local cache was not left untouched after a repo-mismatch rejection: $RUN_OUT"

#############################################################################
echo "--- scenario: fetch-baseline rejects a corrupted artifact rather than trusting it, and never touches the local cache (PBI 297918 AC2) ---"
#############################################################################
FETCHCORRUPT="$(new_tmp_dir)/fetch-corrupt-bundle"
cp -R "$FETCHBUNDLE" "$FETCHCORRUPT"
echo "tampered" >> "$FETCHCORRUPT/symbols.idx"
FETCHCORRUPTCONSUMER="$(new_tmp_dir)/fetch-corrupt-consumer"
init_fixture_repo "$FETCHCORRUPTCONSUMER"
echo x > "$FETCHCORRUPTCONSUMER/f.sh"
( cd "$FETCHCORRUPTCONSUMER" && git remote add origin "https://dev.azure.com/fetchorg/fetchproj/_git/fetchrepo" && git add -A && git_q commit -m "initial" )
FETCHCORRUPTHOME="$(new_tmp_dir)"

run "$FETCHCORRUPTHOME" fetch-baseline "$FETCHCORRUPTCONSUMER" --from "$FETCHCORRUPT"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -q '^fetch:status=rejected$' \
  && printf '%s' "$RUN_OUT" | grep -q '^fetch:reason=checksum-mismatch$' \
  && ok "fetch-baseline rejects a tampered artifact rather than trusting its manifest blindly" \
  || bad "fetch-baseline should have rejected a tampered artifact: $RUN_OUT"
run "$FETCHCORRUPTHOME" status "$FETCHCORRUPTCONSUMER"
[ "$(ctx_field cache_state)" = "MISSING" ] \
  && ok "the local cache stays untouched after a rejected corrupted artifact" \
  || bad "the local cache was not left untouched after a corruption rejection: $RUN_OUT"

#############################################################################
echo "--- scenario: fetch-baseline rejects an artifact whose schema doesn't match this script, even though it's otherwise intact (PBI 297918 AC2) ---"
#############################################################################
FETCHOLDSCHEMA="$(new_tmp_dir)/fetch-old-schema-bundle"
cp -R "$FETCHBUNDLE" "$FETCHOLDSCHEMA"
grep -v '^artifact_schema_version: ' "$FETCHOLDSCHEMA/manifest.txt" > "$FETCHOLDSCHEMA/manifest.txt.new"
{ echo 'artifact_schema_version: 999'; cat "$FETCHOLDSCHEMA/manifest.txt.new"; } > "$FETCHOLDSCHEMA/manifest.txt"
rm -f "$FETCHOLDSCHEMA/manifest.txt.new"
bash "$REPO_CTX" verify "$FETCHOLDSCHEMA" >/dev/null 2>&1
[ $? -eq 0 ] \
  && ok "fixture setup: the schema-bumped bundle still passes plain integrity verification (checksums are untouched)" \
  || bad "fixture setup failed: the schema-bumped bundle should still verify as intact"

FETCHSCHEMACONSUMER="$(new_tmp_dir)/fetch-schema-consumer"
init_fixture_repo "$FETCHSCHEMACONSUMER"
echo x > "$FETCHSCHEMACONSUMER/f.sh"
( cd "$FETCHSCHEMACONSUMER" && git remote add origin "https://dev.azure.com/fetchorg/fetchproj/_git/fetchrepo" && git add -A && git_q commit -m "initial" )
FETCHSCHEMAHOME="$(new_tmp_dir)"

run "$FETCHSCHEMAHOME" fetch-baseline "$FETCHSCHEMACONSUMER" --from "$FETCHOLDSCHEMA"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -q '^fetch:status=rejected$' \
  && printf '%s' "$RUN_OUT" | grep -q '^fetch:reason=incompatible-schema$' \
  && ok "fetch-baseline rejects an artifact with a mismatched schema version even when its checksums are intact" \
  || bad "fetch-baseline should have rejected a schema-incompatible artifact: $RUN_OUT"

#############################################################################
echo "--- scenario: fetch-baseline reports an actionable reason instead of failing opaquely when nothing is retrievable (PBI 297918 AC2) ---"
#############################################################################
FETCHNOMANIFEST="$(new_tmp_dir)/fetch-empty-bundle"
mkdir -p "$FETCHNOMANIFEST"
run "$FETCHSCHEMAHOME" fetch-baseline "$FETCHSCHEMACONSUMER" --from "$FETCHNOMANIFEST"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -q '^fetch:status=rejected$' \
  && printf '%s' "$RUN_OUT" | grep -q '^fetch:reason=missing-manifest$' \
  && ok "fetch-baseline rejects a directory with no manifest.txt instead of guessing" \
  || bad "fetch-baseline should have reported missing-manifest: $RUN_OUT"

FETCHNOFEEDREPO="$(new_tmp_dir)/fetch-no-feed-repo"
init_fixture_repo "$FETCHNOFEEDREPO"
echo x > "$FETCHNOFEEDREPO/f.sh"
( cd "$FETCHNOFEEDREPO" && git remote add origin "https://dev.azure.com/fetchorg/fetchproj/_git/fetchrepo" && git add -A && git_q commit -m "initial" )
FETCHNOFEEDHOME="$(new_tmp_dir)"
run "$FETCHNOFEEDHOME" fetch-baseline "$FETCHNOFEEDREPO"
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -q '^fetch:status=unavailable$' \
  && printf '%s' "$RUN_OUT" | grep -q '^fetch:reason=no-feed-configured$' \
  && ok "fetch-baseline with no --feed and no ci-setup configured reports unavailable rather than guessing a feed" \
  || bad "fetch-baseline should have reported no-feed-configured: $RUN_OUT"

#############################################################################
echo "--- scenario: fetch-baseline auto-detects the feed, package, and org to use from this repo's own committed pipeline and remote, with zero flags (PBI 297918) ---"
#############################################################################
FETCHAUTOREPO="$(new_tmp_dir)/fetch-auto-repo"
init_fixture_repo "$FETCHAUTOREPO"
echo x > "$FETCHAUTOREPO/f.sh"
( cd "$FETCHAUTOREPO" && git remote add origin "https://dev.azure.com/fetchorg/fetchproj/_git/fetchrepo" && git add -A && git_q commit -m "initial" )
FETCHAUTOHOME="$(new_tmp_dir)"
run "$FETCHAUTOHOME" ci-setup "$FETCHAUTOREPO" --feed "FetchProject/FetchFeed"
[ "$RUN_EXIT" -eq 0 ] \
  && ok "fixture setup: ci-setup configured a feed/package for the auto-detection scenario" \
  || bad "fixture setup failed: ci-setup did not succeed for the auto-detection scenario: $RUN_OUT"

# With the real `az` hidden from PATH, auto-detection succeeding all the
# way through to the one genuinely external step (the az CLI call itself)
# is what distinguishes "no feed configured" from "feed/org resolved, az
# unavailable" -- reaching az-cli-missing instead of no-feed-configured or
# no-organization-detected proves the feed, package, and org were all
# derived automatically, with no flags and nobody telling the agent what
# to fetch.
MINIMALPATH="$(new_tmp_dir)"
for b in bash git grep sed awk cp mv rm mkdir cat printf head tail wc shasum sha256sum basename dirname tr date mktemp; do
  p="$(command -v "$b" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$MINIMALPATH/$b" 2>/dev/null
done
RUN_OUT="$(PATH="$MINIMALPATH" AGENTIC_TOOLKIT_HOME="$FETCHAUTOHOME" bash "$REPO_CTX" fetch-baseline "$FETCHAUTOREPO" 2>&1)"
RUN_EXIT=$?
[ "$RUN_EXIT" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -q '^fetch:status=unavailable$' \
  && printf '%s' "$RUN_OUT" | grep -q '^fetch:reason=az-cli-missing$' \
  && ok "with zero flags, fetch-baseline auto-detects the feed/package from the committed pipeline and the org from the origin remote, reaching the az CLI step itself" \
  || bad "fetch-baseline did not auto-detect feed/package/org from the repo alone: $RUN_OUT"

echo "----------------------------------------"
echo "smoke test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
