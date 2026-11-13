#!/usr/bin/env bash
# repo-context.sh — source-grounded repository symbol/reference lookup for
# the `repository-context` Kiro skill (see SKILL.md in this same directory).
#
# Usage:
#   repo-context.sh status  [repo_root]            Report cache freshness (read-only, never rebuilds).
#   repo-context.sh rebuild [repo_root] [--force]  Bounded rebuild-or-fallback (force always rebuilds).
#   repo-context.sh lookup  <symbol> [repo_root]   Find a symbol's definition/references with evidence.
#   repo-context.sh diff    [repo_root]            Show working-tree status/diff overlay only.
#   repo-context.sh relate  <symbol> <provider_repo> <consumer_repo>
#                                                   Check one named symbol for real evidence on BOTH
#                                                   sides of two different repositories (a provider's
#                                                   definition/reference and a consumer's reference to
#                                                   the same name), and persist a lightweight relationship
#                                                   record of the result.
#   repo-context.sh relate-status <symbol> <provider_repo> <consumer_repo>
#                                                   Report whether a previously recorded relationship
#                                                   (from `relate`) is still fresh, without recomputing it.
#   repo-context.sh indexer-check                  Report whether Universal Ctags is available (no repo needed).
#   repo-context.sh --help
#
# repo_root defaults to the git repo enclosing the current directory.
#
# Indexing: shells out to Universal Ctags when positively detected (not just
# "something named ctags is on PATH" — macOS ships a BSD ctags under that
# name that this script must not mistake for the real thing). Everything
# else — including every reference/relationship hit, always — comes from a
# plain `grep -w` scan, so every result line carries a `confidence` field:
# `confirmed` only for a ctags-sourced definition, `inferred` otherwise.
#
# Cache: ${AGENTIC_TOOLKIT_HOME:-$HOME}/.kiro/.um-agentic-engineering/repo-context/<key>/,
# a plain directory of flat text files (metadata.txt + symbols.idx) — never
# inside the repo being analyzed, never a database/daemon/watcher.
#
# Cross-repo relationships (`relate`/`relate-status`) reuse this exact same
# evidence model across two repo roots instead of one, and persist a
# lightweight record — never a graph, never a second indexer — under
# ${AGENTIC_TOOLKIT_HOME:-$HOME}/.kiro/.um-agentic-engineering/repo-relations/<key>/.
#
# Env vars:
#   AGENTIC_TOOLKIT_HOME            Redirect cache under a throwaway home (see scripts/smoke-test.sh's use of the same variable for agentic-eng).
#   AGENTIC_REPO_CONTEXT_MAX_FILES  Bounded-rebuild file-count cap (default 20000).
#   AGENTIC_REPO_CONTEXT_TIMEOUT    Bounded-rebuild timeout in seconds (default 15).
#   AGENTIC_REPO_CONTEXT_FORCE_FALLBACK=1  Force direct-source fallback even if Universal Ctags is present (deterministic testing hook).
set -uo pipefail

CACHE_SCHEMA_VERSION=1
RELATION_SCHEMA_VERSION=1
DEFAULT_MAX_FILES=20000
DEFAULT_TIMEOUT=15

info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

digest_string() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  fi
}

cache_home() {
  printf '%s/.kiro/.um-agentic-engineering/repo-context' "${AGENTIC_TOOLKIT_HOME:-$HOME}"
}

repo_root_of() {
  local explicit="${1:-}"
  local dir="${explicit:-$PWD}"
  ( cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}

resolve_root_or_fail() {
  local explicit="${1:-}" root
  root="$(repo_root_of "$explicit")"
  if [ -z "$root" ]; then
    warn "Not inside a git repository (or repo_root does not point into one): ${explicit:-$PWD}"
    return 1
  fi
  printf '%s' "$root"
}

repo_identity() {
  local root="$1" origin
  origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
  if [ -n "$origin" ]; then
    printf 'origin:%s' "$origin"
  else
    printf 'path:%s' "$(cd "$root" && pwd -P)"
  fi
}

cache_key() { digest_string "$(repo_identity "$1")"; }
cache_dir_for() { printf '%s/%s' "$(cache_home)" "$(cache_key "$1")"; }

read_field() {
  local file="$1" key="$2" line
  [ -f "$file" ] || return 1
  line="$(grep "^${key}: " "$file" 2>/dev/null | head -n1)"
  [ -n "$line" ] || return 1
  printf '%s' "$line" | sed "s/^${key}: //"
}

candidate_files() {
  local root="$1"
  ( cd "$root" && git ls-files && git ls-files --others --exclude-standard ) | LC_ALL=C sort -u
}

candidate_file_count() { candidate_files "$1" | wc -l | tr -d ' '; }

has_universal_ctags() {
  [ "${AGENTIC_REPO_CONTEXT_FORCE_FALLBACK:-0}" = "1" ] && return 1
  command -v ctags >/dev/null 2>&1 || return 1
  ctags --version 2>/dev/null | grep -qi 'Universal Ctags'
}

ctags_version_string() {
  ctags --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

# run_with_timeout <seconds> <command...> — portable bash timeout wrapper
# (macOS ships no GNU `timeout`). Kills the command's whole process GROUP on
# expiry, not just its own pid — a command that forks a helper (as this
# script's own smoke test does, to simulate a hanging indexer) would
# otherwise leave an orphaned descendant running past the bound, still
# holding our stdout pipe open. `set -m` makes bash put the backgrounded
# job in its own process group so `kill -- -$pid` can reach the whole tree
# without touching this script's own process group.
run_with_timeout() {
  local secs="$1"; shift
  local had_monitor=0
  case "$-" in *m*) had_monitor=1 ;; esac
  set -m
  "$@" &
  local pid=$!
  [ "$had_monitor" -eq 1 ] || set +m
  ( sleep "$secs"; kill -9 -- "-$pid" 2>/dev/null; kill -9 "$pid" 2>/dev/null ) &
  local watcher=$!
  local status=0
  wait "$pid" 2>/dev/null || status=$?
  kill -9 -- "-$watcher" 2>/dev/null
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  return "$status"
}

# determine_state <root> <cache_dir> -> sets STATE to one of:
#   NO_COMMITS | MISSING | CORRUPT | FRESH | STALE_REVISION
determine_state() {
  local root="$1" cache_dir="$2"
  local meta="$cache_dir/metadata.txt" idx="$cache_dir/symbols.idx"
  local head
  head="$(git -C "$root" rev-parse HEAD 2>/dev/null)"
  if [ -z "$head" ]; then
    STATE="NO_COMMITS"
    return 0
  fi

  if [ ! -f "$meta" ]; then
    STATE="MISSING"
    return 0
  fi

  local schema commit indexer symcount actual_count
  schema="$(read_field "$meta" schema_version 2>/dev/null || true)"
  commit="$(read_field "$meta" commit 2>/dev/null || true)"
  indexer="$(read_field "$meta" indexer 2>/dev/null || true)"
  symcount="$(read_field "$meta" symbol_count 2>/dev/null || true)"

  if [ -z "$schema" ] || [ -z "$commit" ] || [ -z "$indexer" ] || [ -z "$symcount" ]; then
    STATE="CORRUPT"
    return 0
  fi
  if [ "$schema" != "$CACHE_SCHEMA_VERSION" ]; then
    STATE="CORRUPT"
    return 0
  fi
  if printf '%s' "$indexer" | grep -q '^universal-ctags'; then
    if [ ! -f "$idx" ]; then
      STATE="CORRUPT"
      return 0
    fi
    actual_count="$(wc -l < "$idx" | tr -d ' ')"
    if [ "$actual_count" != "$symcount" ]; then
      STATE="CORRUPT"
      return 0
    fi
  fi

  if [ "$commit" = "$head" ]; then
    STATE="FRESH"
  else
    STATE="STALE_REVISION"
  fi
}

# build_index <root> <cache_dir> -> sets BUILD_OK (1/0), BUILD_INDEXER, BUILD_REASON.
# Bounded: skips ctags above a file-count cap, and kills it on timeout.
# Never writes a partial/bad cache — builds in a sibling temp dir first.
build_index() {
  local root="$1" cache_dir="$2"
  local max_files="${AGENTIC_REPO_CONTEXT_MAX_FILES:-$DEFAULT_MAX_FILES}"
  local timeout="${AGENTIC_REPO_CONTEXT_TIMEOUT:-$DEFAULT_TIMEOUT}"
  local count commit dirty origin

  mkdir -p "$(cache_home)"
  count="$(candidate_file_count "$root")"
  commit="$(git -C "$root" rev-parse HEAD 2>/dev/null)"
  if [ -z "$commit" ]; then
    BUILD_OK=0
    BUILD_REASON="no-commits"
    return 0
  fi
  dirty="no"
  [ -n "$(git -C "$root" status --short 2>/dev/null)" ] && dirty="yes"
  origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
  [ -z "$origin" ] && origin="none"

  BUILD_OK=1
  BUILD_INDEXER="direct-source-fallback"
  BUILD_REASON=""

  if [ "$count" -gt "$max_files" ]; then
    BUILD_OK=0
    BUILD_REASON="too-many-files"
  elif ! has_universal_ctags; then
    BUILD_OK=0
    BUILD_REASON="indexer-unavailable"
    [ "${AGENTIC_REPO_CONTEXT_FORCE_FALLBACK:-0}" = "1" ] && BUILD_REASON="forced"
  fi

  [ "$BUILD_OK" -eq 0 ] && return 0

  local staging
  staging="$(mktemp -d "$(cache_home)/.staging.XXXXXX")" || {
    BUILD_OK=0
    BUILD_REASON="rebuild-failed"
    return 0
  }

  if ! ( cd "$root" && candidate_files "$root" | run_with_timeout "$timeout" ctags -x -L - -f "$staging/symbols.idx" ) \
     || [ ! -f "$staging/symbols.idx" ]; then
    rm -rf "$staging"
    BUILD_OK=0
    BUILD_REASON="rebuild-failed"
    return 0
  fi

  local symbol_count version
  symbol_count="$(wc -l < "$staging/symbols.idx" | tr -d ' ')"
  version="$(ctags_version_string)"
  BUILD_INDEXER="universal-ctags ${version:-unknown}"

  {
    printf 'repo_path: %s\n' "$(cd "$root" && pwd -P)"
    printf 'origin_url: %s\n' "$origin"
    printf 'commit: %s\n' "$commit"
    printf 'dirty_at_index: %s\n' "$dirty"
    printf 'indexer: %s\n' "$BUILD_INDEXER"
    printf 'schema_version: %s\n' "$CACHE_SCHEMA_VERSION"
    printf 'symbol_count: %s\n' "$symbol_count"
    printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$staging/metadata.txt"

  rm -rf "$cache_dir"
  mv "$staging" "$cache_dir"
  BUILD_OK=1
  return 0
}

# ensure_fresh_or_fallback <root> <cache_dir> <force:0|1>
# Sets EFF_STATE (fresh|rebuilt|stale-by-revision|fallback|no-commits),
# EFF_INDEXER, EFF_FALLBACK_REASON, EFF_INDEXED_COMMIT. Returns 1 only for
# no-commits (nothing usable to report).
ensure_fresh_or_fallback() {
  local root="$1" cache_dir="$2" force="${3:-0}"
  EFF_FALLBACK_REASON=""
  determine_state "$root" "$cache_dir"

  if [ "$STATE" = "NO_COMMITS" ]; then
    EFF_STATE="no-commits"
    EFF_INDEXER="none"
    EFF_INDEXED_COMMIT="none"
    return 1
  fi

  if [ "$force" = "1" ] || [ "$STATE" = "MISSING" ] || [ "$STATE" = "CORRUPT" ]; then
    build_index "$root" "$cache_dir"
    if [ "$BUILD_OK" = "1" ]; then
      EFF_STATE="rebuilt"
      EFF_INDEXER="$BUILD_INDEXER"
      EFF_INDEXED_COMMIT="$(read_field "$cache_dir/metadata.txt" commit)"
    else
      EFF_STATE="fallback"
      EFF_INDEXER="direct-source-fallback"
      EFF_FALLBACK_REASON="$BUILD_REASON"
      if [ "$STATE" = "MISSING" ]; then
        EFF_INDEXED_COMMIT="none"
      else
        EFF_INDEXED_COMMIT="$(read_field "$cache_dir/metadata.txt" commit 2>/dev/null || echo unknown)"
      fi
    fi
    return 0
  fi

  EFF_INDEXER="$(read_field "$cache_dir/metadata.txt" indexer)"
  EFF_INDEXED_COMMIT="$(read_field "$cache_dir/metadata.txt" commit)"
  if [ "$STATE" = "STALE_REVISION" ]; then
    EFF_STATE="stale-by-revision"
  else
    EFF_STATE="fresh"
  fi
  return 0
}

print_ctx_header() {
  local root="$1" head dirty
  head="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo none)"
  dirty="no"
  [ -n "$(git -C "$root" status --short 2>/dev/null)" ] && dirty="yes"
  printf 'ctx:repo_root=%s\n' "$root"
  printf 'ctx:head=%s\n' "$head"
  printf 'ctx:dirty=%s\n' "$dirty"
  printf 'ctx:index_state=%s\n' "$EFF_STATE"
  printf 'ctx:indexed_commit=%s\n' "${EFF_INDEXED_COMMIT:-none}"
  printf 'ctx:indexer=%s\n' "${EFF_INDEXER:-direct-source-fallback}"
  if [ "$EFF_STATE" = "fallback" ] && [ -n "${EFF_FALLBACK_REASON:-}" ]; then
    printf 'ctx:fallback_reason=%s\n' "$EFF_FALLBACK_REASON"
  fi
}

# diff_overlay <root> [symbol] — always-on working-tree awareness: prints
# every changed path from `git status --short`, and when a symbol was
# given, greps changed files for it so uncommitted hits are never missing,
# without requiring any reindex.
diff_overlay() {
  local root="$1" symbol="${2:-}"
  local line status_code path
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    status_code="${line:0:2}"
    path="${line:3}"
    printf 'DIFF status=%s path=%s\n' "$status_code" "$path"
    if [ -n "$symbol" ] && [ -f "$root/$path" ]; then
      grep -n -w -F -- "$symbol" "$root/$path" 2>/dev/null | while IFS=: read -r ln _rest; do
        printf 'RESULT symbol=%s kind=changed file=%s line=%s source=diff confidence=inferred\n' "$symbol" "$path" "$ln"
      done
    fi
  done < <(git -C "$root" status --short 2>/dev/null)
}

# search_symbol <root> <cache_dir> <symbol> <index_state> <indexer>
# Confirmed hits from the ctags cache (only when index_state isn't
# "fallback"/"no-commits"), plus an always-on inferred grep pass across
# every candidate file (the only source at all when there's no indexer).
search_symbol() {
  local root="$1" cache_dir="$2" symbol="$3" index_state="$4" indexer="$5"

  if printf '%s' "$indexer" | grep -q '^universal-ctags' \
     && [ "$index_state" != "fallback" ] && [ "$index_state" != "no-commits" ] \
     && [ -f "$cache_dir/symbols.idx" ]; then
    local name kind line file
    while read -r name kind line file _rest; do
      [ "$name" = "$symbol" ] || continue
      printf 'RESULT symbol=%s kind=%s file=%s line=%s source=index confidence=confirmed\n' "$name" "$kind" "$file" "$line"
    done < "$cache_dir/symbols.idx"
  fi

  local f
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    grep -n -w -F -- "$symbol" "$root/$f" 2>/dev/null | while IFS=: read -r ln _rest; do
      printf 'RESULT symbol=%s kind=reference file=%s line=%s source=grep confidence=inferred\n' "$symbol" "$f" "$ln"
    done
  done < <(candidate_files "$root")
}

relation_home() {
  printf '%s/.kiro/.um-agentic-engineering/repo-relations' "${AGENTIC_TOOLKIT_HOME:-$HOME}"
}

# relation_key <provider_root> <symbol> <consumer_root> — direction matters:
# provider and consumer are not interchangeable, so they're never sorted.
relation_key() {
  local provider_root="$1" symbol="$2" consumer_root="$3"
  digest_string "relate:$(repo_identity "$provider_root")|${symbol}|$(repo_identity "$consumer_root")"
}

relation_dir_for() {
  printf '%s/%s' "$(relation_home)" "$(relation_key "$1" "$2" "$3")"
}

# write_relation_record <provider_root> <consumer_root> <symbol> <status>
#                        <provider_head> <consumer_head> <provider_evidence> <consumer_evidence>
# Persists a lightweight relationship record (repo identities, revisions,
# evidence) — never a graph, never a second indexer. Builds in a sibling
# temp dir first, same as build_index, so a reader never sees a partial
# record.
write_relation_record() {
  local provider_root="$1" consumer_root="$2" symbol="$3" status="$4"
  local provider_head="$5" consumer_head="$6" provider_evidence="$7" consumer_evidence="$8"
  local rel_dir
  rel_dir="$(relation_dir_for "$provider_root" "$symbol" "$consumer_root")"
  mkdir -p "$(relation_home)"
  local staging
  staging="$(mktemp -d "$(relation_home)/.staging.XXXXXX")" || return 1

  local provider_origin consumer_origin
  provider_origin="$(git -C "$provider_root" remote get-url origin 2>/dev/null || true)"
  [ -z "$provider_origin" ] && provider_origin="none"
  consumer_origin="$(git -C "$consumer_root" remote get-url origin 2>/dev/null || true)"
  [ -z "$consumer_origin" ] && consumer_origin="none"

  printf '%s\n' "$provider_evidence" | grep '^RESULT ' > "$staging/provider.evidence" 2>/dev/null || true
  printf '%s\n' "$consumer_evidence" | grep '^RESULT ' > "$staging/consumer.evidence" 2>/dev/null || true

  {
    printf 'schema_version: %s\n' "$RELATION_SCHEMA_VERSION"
    printf 'symbol: %s\n' "$symbol"
    printf 'provider_repo_path: %s\n' "$(cd "$provider_root" && pwd -P)"
    printf 'provider_origin_url: %s\n' "$provider_origin"
    printf 'provider_commit: %s\n' "$provider_head"
    printf 'consumer_repo_path: %s\n' "$(cd "$consumer_root" && pwd -P)"
    printf 'consumer_origin_url: %s\n' "$consumer_origin"
    printf 'consumer_commit: %s\n' "$consumer_head"
    printf 'status: %s\n' "$status"
    printf 'provider_evidence_count: %s\n' "$(wc -l < "$staging/provider.evidence" | tr -d ' ')"
    printf 'consumer_evidence_count: %s\n' "$(wc -l < "$staging/consumer.evidence" | tr -d ' ')"
    printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$staging/relation.txt"

  rm -rf "$rel_dir"
  mv "$staging" "$rel_dir"
}

cmd_status() {
  local root
  root="$(resolve_root_or_fail "${1:-}")" || exit 1
  local cache_dir
  cache_dir="$(cache_dir_for "$root")"
  determine_state "$root" "$cache_dir"

  local head dirty
  head="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo none)"
  dirty="no"
  [ -n "$(git -C "$root" status --short 2>/dev/null)" ] && dirty="yes"

  printf 'ctx:repo_root=%s\n' "$root"
  printf 'ctx:head=%s\n' "$head"
  printf 'ctx:dirty=%s\n' "$dirty"
  printf 'ctx:cache_state=%s\n' "$STATE"
  if [ -f "$cache_dir/metadata.txt" ]; then
    printf 'ctx:indexed_commit=%s\n' "$(read_field "$cache_dir/metadata.txt" commit 2>/dev/null || echo unknown)"
    printf 'ctx:indexer=%s\n' "$(read_field "$cache_dir/metadata.txt" indexer 2>/dev/null || echo unknown)"
  fi

  if [ "$STATE" = "NO_COMMITS" ]; then
    warn "Repository has no commits yet; nothing to index."
    exit 1
  fi
}

cmd_rebuild() {
  local root_arg="" force=0 a
  for a in "$@"; do
    case "$a" in
      --force) force=1 ;;
      *) root_arg="$a" ;;
    esac
  done
  local root
  root="$(resolve_root_or_fail "$root_arg")" || exit 1
  local cache_dir
  cache_dir="$(cache_dir_for "$root")"
  ensure_fresh_or_fallback "$root" "$cache_dir" "$force"
  local rc=$?
  print_ctx_header "$root"
  [ "$rc" -ne 0 ] && return 1
  [ "$EFF_STATE" = "fallback" ] && return 1
  return 0
}

cmd_lookup() {
  local symbol="${1:-}" root_arg="${2:-}"
  [ -n "$symbol" ] || fail "Usage: repo-context.sh lookup <symbol> [repo_root]"
  local root
  root="$(resolve_root_or_fail "$root_arg")" || exit 1
  local cache_dir
  cache_dir="$(cache_dir_for "$root")"
  ensure_fresh_or_fallback "$root" "$cache_dir" 0
  local rc=$?
  print_ctx_header "$root"
  if [ "$rc" -ne 0 ]; then
    warn "Repository has no commits yet; nothing to index."
    return 1
  fi
  search_symbol "$root" "$cache_dir" "$symbol" "$EFF_STATE" "$EFF_INDEXER"
  diff_overlay "$root" "$symbol"
}

cmd_relate() {
  local symbol="${1:-}" provider_arg="${2:-}" consumer_arg="${3:-}"
  if [ -z "$symbol" ] || [ -z "$provider_arg" ] || [ -z "$consumer_arg" ]; then
    fail "Usage: repo-context.sh relate <symbol> <provider_repo> <consumer_repo>"
  fi
  local provider_root consumer_root
  provider_root="$(resolve_root_or_fail "$provider_arg")" || exit 1
  consumer_root="$(resolve_root_or_fail "$consumer_arg")" || exit 1

  local provider_cache_dir consumer_cache_dir
  provider_cache_dir="$(cache_dir_for "$provider_root")"
  consumer_cache_dir="$(cache_dir_for "$consumer_root")"

  ensure_fresh_or_fallback "$provider_root" "$provider_cache_dir" 0
  local provider_eff_state="$EFF_STATE" provider_indexer="$EFF_INDEXER"
  local provider_head
  provider_head="$(git -C "$provider_root" rev-parse HEAD 2>/dev/null || echo none)"
  local provider_evidence
  provider_evidence="$(search_symbol "$provider_root" "$provider_cache_dir" "$symbol" "$provider_eff_state" "$provider_indexer"; diff_overlay "$provider_root" "$symbol")"

  ensure_fresh_or_fallback "$consumer_root" "$consumer_cache_dir" 0
  local consumer_eff_state="$EFF_STATE" consumer_indexer="$EFF_INDEXER"
  local consumer_head
  consumer_head="$(git -C "$consumer_root" rev-parse HEAD 2>/dev/null || echo none)"
  local consumer_evidence
  consumer_evidence="$(search_symbol "$consumer_root" "$consumer_cache_dir" "$symbol" "$consumer_eff_state" "$consumer_indexer"; diff_overlay "$consumer_root" "$symbol")"

  local provider_hits consumer_hits status
  provider_hits="$(printf '%s' "$provider_evidence" | grep -c '^RESULT ' || true)"
  consumer_hits="$(printf '%s' "$consumer_evidence" | grep -c '^RESULT ' || true)"

  if [ "${provider_hits:-0}" -gt 0 ] && [ "${consumer_hits:-0}" -gt 0 ]; then
    status="supported"
  else
    status="unknown"
  fi

  write_relation_record "$provider_root" "$consumer_root" "$symbol" "$status" \
    "$provider_head" "$consumer_head" "$provider_evidence" "$consumer_evidence"

  printf 'rel:symbol=%s\n' "$symbol"
  printf 'rel:provider_repo=%s\n' "$provider_root"
  printf 'rel:provider_head=%s\n' "$provider_head"
  printf 'rel:consumer_repo=%s\n' "$consumer_root"
  printf 'rel:consumer_head=%s\n' "$consumer_head"
  printf 'rel:status=%s\n' "$status"
  if [ "$status" = "unknown" ]; then
    warn "No supported relationship found for '$symbol' between these two repositories — reported as unknown, not invented."
  fi
  printf '%s\n' "$provider_evidence" | grep '^RESULT ' | sed 's/^RESULT /PROVIDER /' || true
  printf '%s\n' "$consumer_evidence" | grep '^RESULT ' | sed 's/^RESULT /CONSUMER /' || true

  [ "$status" = "supported" ]
}

cmd_relate_status() {
  local symbol="${1:-}" provider_arg="${2:-}" consumer_arg="${3:-}"
  if [ -z "$symbol" ] || [ -z "$provider_arg" ] || [ -z "$consumer_arg" ]; then
    fail "Usage: repo-context.sh relate-status <symbol> <provider_repo> <consumer_repo>"
  fi
  local provider_root consumer_root
  provider_root="$(resolve_root_or_fail "$provider_arg")" || exit 1
  consumer_root="$(resolve_root_or_fail "$consumer_arg")" || exit 1

  local rel_dir record
  rel_dir="$(relation_dir_for "$provider_root" "$symbol" "$consumer_root")"
  record="$rel_dir/relation.txt"
  if [ ! -f "$record" ]; then
    printf 'rel:record=missing\n'
    warn "No stored relationship record for '$symbol' between these two repositories yet; run 'relate' first."
    return 1
  fi

  local rec_status rec_provider_commit rec_consumer_commit
  rec_status="$(read_field "$record" status)"
  rec_provider_commit="$(read_field "$record" provider_commit)"
  rec_consumer_commit="$(read_field "$record" consumer_commit)"

  local provider_head consumer_head
  provider_head="$(git -C "$provider_root" rev-parse HEAD 2>/dev/null || echo none)"
  consumer_head="$(git -C "$consumer_root" rev-parse HEAD 2>/dev/null || echo none)"

  local provider_state consumer_state overall
  [ "$rec_provider_commit" = "$provider_head" ] && provider_state="fresh" || provider_state="stale"
  [ "$rec_consumer_commit" = "$consumer_head" ] && consumer_state="fresh" || consumer_state="stale"
  if [ "$provider_state" = "fresh" ] && [ "$consumer_state" = "fresh" ]; then
    overall="fresh"
  else
    overall="stale"
  fi

  printf 'rel:record=found\n'
  printf 'rel:symbol=%s\n' "$symbol"
  printf 'rel:status=%s\n' "$rec_status"
  printf 'rel:provider_repo=%s\n' "$provider_root"
  printf 'rel:recorded_provider_commit=%s\n' "$rec_provider_commit"
  printf 'rel:provider_head=%s\n' "$provider_head"
  printf 'rel:provider_state=%s\n' "$provider_state"
  printf 'rel:consumer_repo=%s\n' "$consumer_root"
  printf 'rel:recorded_consumer_commit=%s\n' "$rec_consumer_commit"
  printf 'rel:consumer_head=%s\n' "$consumer_head"
  printf 'rel:consumer_state=%s\n' "$consumer_state"
  printf 'rel:overall=%s\n' "$overall"

  if [ "$overall" = "stale" ]; then
    warn "Recorded relationship is stale — one or both repositories moved past the recorded commit. Re-run 'relate' to refresh it."
    return 1
  fi
  return 0
}

cmd_indexer_check() {
  if has_universal_ctags; then
    printf 'ctx:indexer_available=yes\n'
    printf 'ctx:indexer=universal-ctags %s\n' "$(ctags_version_string)"
  else
    printf 'ctx:indexer_available=no\n'
    printf 'ctx:fix=Install Universal Ctags for confirmed (not just inferred) results: brew install universal-ctags (macOS) or apt-get install universal-ctags (Linux/WSL)\n'
  fi
}

cmd_diff() {
  local root_arg="${1:-}"
  local root
  root="$(resolve_root_or_fail "$root_arg")" || exit 1
  local cache_dir
  cache_dir="$(cache_dir_for "$root")"
  ensure_fresh_or_fallback "$root" "$cache_dir" 0
  local rc=$?
  print_ctx_header "$root"
  [ "$rc" -ne 0 ] && return 1
  diff_overlay "$root" ""
}

show_help() {
  cat <<'EOF'
repo-context.sh — source-grounded repository symbol/reference lookup

Usage:
  repo-context.sh status  [repo_root]            Report cache freshness (read-only, never rebuilds).
  repo-context.sh rebuild [repo_root] [--force]  Bounded rebuild-or-fallback (force always rebuilds).
  repo-context.sh lookup  <symbol> [repo_root]   Find a symbol's definition/references with evidence.
  repo-context.sh diff    [repo_root]            Show working-tree status/diff overlay only.
  repo-context.sh relate  <symbol> <provider_repo> <consumer_repo>
                                                  Check one named symbol for evidence on both sides of
                                                  two different repositories and record the result.
  repo-context.sh relate-status <symbol> <provider_repo> <consumer_repo>
                                                  Report whether a previously recorded relationship is
                                                  still fresh, without recomputing it.
  repo-context.sh indexer-check                  Report whether Universal Ctags is available (no repo needed).
  repo-context.sh --help

repo_root defaults to the git repo enclosing the current directory.
EOF
}

ACTION="${1:-}"
ARGS=()
[ "$#" -gt 0 ] && ARGS=("${@:2}")

case "$ACTION" in
  status)        cmd_status "${ARGS[@]}" ;;
  rebuild)       cmd_rebuild "${ARGS[@]}" ;;
  lookup)        cmd_lookup "${ARGS[@]}" ;;
  diff)          cmd_diff "${ARGS[@]}" ;;
  relate)        cmd_relate "${ARGS[@]}" ;;
  relate-status) cmd_relate_status "${ARGS[@]}" ;;
  indexer-check) cmd_indexer_check ;;
  --help|-h|help|"") show_help ;;
  *) fail "Unknown command: $ACTION (see --help)" ;;
esac
