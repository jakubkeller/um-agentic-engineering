#!/usr/bin/env bash
# repo-context.sh — source-grounded repository symbol/reference lookup for
# the `repository-context` Kiro skill (see SKILL.md in this same directory).
#
# Usage:
#   repo-context.sh status  [repo_root]            Report cache freshness (read-only, never rebuilds).
#   repo-context.sh rebuild [repo_root] [--force]  Bounded rebuild-or-fallback (force always rebuilds).
#   repo-context.sh lookup  <symbol> [repo_root]   Find a symbol's definition/references with evidence.
#   repo-context.sh diff    [repo_root]            Show working-tree status/diff overlay only.
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
# Env vars:
#   AGENTIC_TOOLKIT_HOME            Redirect cache under a throwaway home (see scripts/smoke-test.sh's use of the same variable for agentic-eng).
#   AGENTIC_REPO_CONTEXT_MAX_FILES  Bounded-rebuild file-count cap (default 20000).
#   AGENTIC_REPO_CONTEXT_TIMEOUT    Bounded-rebuild timeout in seconds (default 15).
#   AGENTIC_REPO_CONTEXT_FORCE_FALLBACK=1  Force direct-source fallback even if Universal Ctags is present (deterministic testing hook).
set -uo pipefail

CACHE_SCHEMA_VERSION=1
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
  repo-context.sh --help

repo_root defaults to the git repo enclosing the current directory.
EOF
}

ACTION="${1:-}"
ARGS=()
[ "$#" -gt 0 ] && ARGS=("${@:2}")

case "$ACTION" in
  status)  cmd_status "${ARGS[@]}" ;;
  rebuild) cmd_rebuild "${ARGS[@]}" ;;
  lookup)  cmd_lookup "${ARGS[@]}" ;;
  diff)    cmd_diff "${ARGS[@]}" ;;
  --help|-h|help|"") show_help ;;
  *) fail "Unknown command: $ACTION (see --help)" ;;
esac
