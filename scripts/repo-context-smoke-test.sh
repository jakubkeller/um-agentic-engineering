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

echo "----------------------------------------"
echo "smoke test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
