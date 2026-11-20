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
#   repo-context.sh relations-for <repo_root> [symbol]
#                                                   List every previously recorded relationship that
#                                                   involves this repo (optionally filtered to one
#                                                   symbol), on either side, without recomputing anything.
#                                                   Lets an agent already working in a repo notice an
#                                                   existing confirmed dependency on its own, instead of
#                                                   requiring the engineer to think to ask about it.
#   repo-context.sh indexer-check                  Report whether Universal Ctags is available (no repo needed).
#   repo-context.sh refresh       [repo_root]      Bounded rebuild only if the cache isn't already fresh (no-op otherwise).
#   repo-context.sh refresh-async [repo_root]      Fire-and-forget `refresh`: returns immediately, never fails.
#   repo-context.sh install-hooks [repo_root]      Install post-commit/post-merge/post-checkout Git hooks that
#                                                   call `refresh-async` after routine Git changes. Coexists with
#                                                   any existing hook content (Husky included) instead of
#                                                   replacing it, and is safe to run again (replaces only its
#                                                   own previously-installed block).
#   repo-context.sh hooks-status  [repo_root]      Report which of those hooks are currently installed (read-only).
#   repo-context.sh package <repo_root> <output_dir> [--force]
#                                                   Package the already-built index cache (metadata.txt +
#                                                   symbols.idx) into a versioned, checksummed artifact bundle
#                                                   tied to the exact current commit. Refuses if the cache isn't
#                                                   FRESH or the working tree is dirty, and never touches
#                                                   output_dir until the bundle is fully built in a staging dir,
#                                                   so a failed package call never replaces a previously
#                                                   published artifact there.
#   repo-context.sh verify  <bundle_dir>           Recompute a packaged artifact's per-file and overall sha256
#                                                   against its manifest.txt and report ok/corrupt, printing the
#                                                   manifest fields either way so it can be inspected.
#   repo-context.sh ci-setup <repo_root> --feed <Project/Feed> [--package <name>] [--pipeline-file <path>]
#                                                   Wire rebuild, then package, then verify, then publish
#                                                   directly into the repo's own Azure Pipelines YAML (default
#                                                   azure-pipelines.yml at the repo root; pass --pipeline-file
#                                                   if the real one lives elsewhere). Creates it if missing.
#                                                   Re-running replaces only its own previously-installed
#                                                   block, same pattern as install-hooks.
#   repo-context.sh ci-setup-status [repo_root] [--pipeline-file <path>]
#                                                   Report whether ci-setup has already configured this repo
#                                                   (read-only).
#   repo-context.sh fetch-baseline [repo_root] [--feed <Project/Feed>] [--org <url>]
#                                  [--package <name>] [--version <ver>] [--from <dir>] [--force]
#                                                   Adopt a compatible published baseline as this repo's
#                                                   local cache instead of rebuilding one. Rejects (leaving
#                                                   the local cache untouched) anything corrupt, schema-
#                                                   incompatible, or published for a different repository.
#                                                   --feed/--package default to what ci-setup configured.
#   repo-context.sh --help
#
# repo_root defaults to the git repo enclosing the current directory.
#
# Git lifecycle integration (`install-hooks`): a post-commit/post-merge/
# post-checkout hook triggers a bounded, backgrounded `refresh` so the cache
# catches up after routine commits, merges, and branch switches without
# anyone having to remember to run `rebuild --force` by hand. This is a
# one-shot background job per Git event, never a persistent watcher or
# daemon, and it always exits 0 from the hook's perspective: a failed or
# still-running refresh never blocks or fails the Git operation that
# triggered it. The per-query freshness check (`ctx:index_state`) remains
# the correctness backstop regardless of whether hooks are installed or a
# refresh is still in flight.
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
# lightweight record (never a graph, never a second indexer) under
# ${AGENTIC_TOOLKIT_HOME:-$HOME}/.kiro/.um-agentic-engineering/repo-relations/<key>/.
#
# Post-merge baseline publication (`package`/`verify`/`ci-setup`, PBI 297919):
# `package` does not index anything new — it only packages the cache this
# script already built (via `rebuild`/`refresh`) into a self-contained,
# checksummed bundle for Azure Pipelines to publish to Azure Artifacts.
# `verify` lets anyone who has retrieved a bundle confirm it hasn't been
# corrupted or tampered with, independent of how it was stored or
# transported. `ci-setup` wires rebuild/package/verify/publish directly into
# a repo's own azure-pipelines.yml so no one ever hand-copies this YAML.
#
# Reusing a published baseline locally (`fetch-baseline`, PBI 297918): the
# consume-side counterpart. Verifies integrity the same way `verify` does,
# then additionally checks the artifact is for this exact repository and
# matches this script's schema version before installing it as this
# repo's own cache, exactly as if `rebuild` had produced it locally.
# Anything that fails either check is rejected and the local cache is
# left untouched, so the normal rebuild/direct-source fallback still
# applies. Uncommitted local changes are never hidden either way: the
# diff overlay runs on every lookup regardless of where the cache came
# from.
#
# Env vars:
#   AGENTIC_TOOLKIT_HOME            Redirect cache under a throwaway home (see scripts/smoke-test.sh's use of the same variable for agentic-eng).
#   AGENTIC_REPO_CONTEXT_MAX_FILES  Bounded-rebuild file-count cap (default 20000).
#   AGENTIC_REPO_CONTEXT_TIMEOUT    Bounded-rebuild timeout in seconds (default 15).
#   AGENTIC_REPO_CONTEXT_FORCE_FALLBACK=1  Force direct-source fallback even if Universal Ctags is present (deterministic testing hook).
set -uo pipefail

CACHE_SCHEMA_VERSION=1
RELATION_SCHEMA_VERSION=1
ARTIFACT_SCHEMA_VERSION=1
DEFAULT_MAX_FILES=20000
DEFAULT_TIMEOUT=15

HOOK_NAMES="post-commit post-merge post-checkout"
HOOK_MARK_BEGIN='# >>> um-agentic-engineering repository-context refresh (managed block) >>>'
HOOK_MARK_END='# <<< um-agentic-engineering repository-context refresh <<<'

CI_MARK_BEGIN='# >>> um-agentic-engineering repository-context publish (managed block) >>>'
CI_MARK_END='# <<< um-agentic-engineering repository-context publish <<<'
CI_VENDOR_REL='.ci/repository-context/repo-context.sh'

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

digest_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

# shell_quote <string>: shell-escapes a string for safe embedding inside a
# generated hook file (paths with spaces or quotes included).
shell_quote() {
  printf '%q' "$1"
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

# hooks_dir_for <root>: the Git hooks directory that actually takes effect
# for this repo, honoring `core.hooksPath` (e.g. Husky v7+ redirects this to
# its own `.husky/` directory) instead of assuming `.git/hooks`.
hooks_dir_for() {
  local root="$1" dir
  dir="$(git -C "$root" rev-parse --git-path hooks 2>/dev/null)" || return 1
  [ -n "$dir" ] || return 1
  case "$dir" in
    /*) printf '%s' "$dir" ;;
    *)  printf '%s/%s' "$root" "$dir" ;;
  esac
}

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

  # Materialize the candidate file list to a real file before handing it to
  # the bounded/timed indexer, instead of streaming it through a pipe into
  # `run_with_timeout`'s backgrounded job: piping into a backgrounded
  # reader can race and silently lose the whole list if it takes any
  # measurable time to produce, independent of which indexer reads it.
  local filelist
  filelist="$(mktemp "$(cache_home)/.filelist.XXXXXX")" || {
    rm -rf "$staging"
    BUILD_OK=0
    BUILD_REASON="rebuild-failed"
    return 0
  }
  candidate_files "$root" > "$filelist"

  if ! ( cd "$root" && run_with_timeout "$timeout" ctags -x -L "$filelist" -f "$staging/symbols.idx" ) \
     || [ ! -f "$staging/symbols.idx" ]; then
    rm -rf "$staging"
    rm -f "$filelist"
    BUILD_OK=0
    BUILD_REASON="rebuild-failed"
    return 0
  fi
  rm -f "$filelist"

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
    printf 'source: local\n'
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
    EFF_CACHE_SOURCE="none"
    return 1
  fi

  if [ "$force" = "1" ] || [ "$STATE" = "MISSING" ] || [ "$STATE" = "CORRUPT" ]; then
    build_index "$root" "$cache_dir"
    if [ "$BUILD_OK" = "1" ]; then
      EFF_STATE="rebuilt"
      EFF_INDEXER="$BUILD_INDEXER"
      EFF_INDEXED_COMMIT="$(read_field "$cache_dir/metadata.txt" commit)"
      EFF_CACHE_SOURCE="local"
    else
      EFF_STATE="fallback"
      EFF_INDEXER="direct-source-fallback"
      EFF_FALLBACK_REASON="$BUILD_REASON"
      EFF_CACHE_SOURCE="none"
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
  EFF_CACHE_SOURCE="$(read_field "$cache_dir/metadata.txt" source 2>/dev/null || echo local)"
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
  printf 'ctx:cache_source=%s\n' "${EFF_CACHE_SOURCE:-none}"
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

# relation_key <provider_root> <symbol> <consumer_root>. Direction matters:
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
# evidence; never a graph, never a second indexer). Builds in a sibling
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
    printf 'ctx:cache_source=%s\n' "$(read_field "$cache_dir/metadata.txt" source 2>/dev/null || echo local)"
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

# cmd_refresh: a bounded, synchronous rebuild, but only when the cache
# genuinely isn't fresh (STALE_REVISION/MISSING/CORRUPT); a no-op when it's
# already FRESH. This is what Git hooks trigger (via `refresh-async`) after
# a commit, merge, or branch switch, and it's also safe to run directly.
cmd_refresh() {
  local root
  root="$(resolve_root_or_fail "${1:-}")" || exit 1
  local cache_dir
  cache_dir="$(cache_dir_for "$root")"
  determine_state "$root" "$cache_dir"
  local force=0
  case "$STATE" in
    MISSING|CORRUPT|STALE_REVISION) force=1 ;;
  esac
  ensure_fresh_or_fallback "$root" "$cache_dir" "$force"
  local rc=$?
  print_ctx_header "$root"
  [ "$rc" -ne 0 ] && return 1
  [ "$EFF_STATE" = "fallback" ] && return 1
  return 0
}

# cmd_refresh_async: fires `refresh` in the background and returns
# immediately, regardless of outcome. This is the only thing a Git hook
# ever calls directly: it must never make the hook wait on a rebuild, and
# it must never fail the Git operation that triggered it, so every failure
# path here is swallowed rather than propagated.
cmd_refresh_async() {
  local root
  root="$(resolve_root_or_fail "${1:-}")" || return 0
  local self
  self="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
  nohup bash "$self" refresh "$root" >/dev/null 2>&1 &
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
    warn "No supported relationship found for '$symbol' between these two repositories. Reported as unknown, not invented."
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
    warn "Recorded relationship is stale: one or both repositories moved past the recorded commit. Re-run 'relate' to refresh it."
    return 1
  fi
  return 0
}

cmd_relations_for() {
  local repo_arg="${1:-}" symbol="${2:-}"
  [ -n "$repo_arg" ] || fail "Usage: repo-context.sh relations-for <repo_root> [symbol]"
  local root root_norm
  root="$(resolve_root_or_fail "$repo_arg")" || exit 1
  root_norm="$(cd "$root" && pwd -P)"

  local home count=0
  home="$(relation_home)"
  if [ ! -d "$home" ]; then
    printf 'rel:count=0\n'
    return 0
  fi

  local d
  for d in "$home"/*/; do
    [ -d "$d" ] || continue
    local record="$d/relation.txt"
    [ -f "$record" ] || continue

    local rec_symbol rec_provider_path rec_consumer_path rec_status
    rec_symbol="$(read_field "$record" symbol 2>/dev/null || true)"
    rec_provider_path="$(read_field "$record" provider_repo_path 2>/dev/null || true)"
    rec_consumer_path="$(read_field "$record" consumer_repo_path 2>/dev/null || true)"
    rec_status="$(read_field "$record" status 2>/dev/null || true)"

    [ -n "$symbol" ] && [ "$rec_symbol" != "$symbol" ] && continue

    local role counterpart own_recorded consumer_recorded
    if [ "$rec_provider_path" = "$root_norm" ]; then
      role="provider"
      counterpart="$rec_consumer_path"
      own_recorded="$(read_field "$record" provider_commit 2>/dev/null || true)"
      consumer_recorded="$(read_field "$record" consumer_commit 2>/dev/null || true)"
    elif [ "$rec_consumer_path" = "$root_norm" ]; then
      role="consumer"
      counterpart="$rec_provider_path"
      own_recorded="$(read_field "$record" consumer_commit 2>/dev/null || true)"
      consumer_recorded="$(read_field "$record" provider_commit 2>/dev/null || true)"
    else
      continue
    fi

    local own_head own_state
    own_head="$(git -C "$root_norm" rev-parse HEAD 2>/dev/null || echo none)"
    [ "$own_head" = "$own_recorded" ] && own_state="fresh" || own_state="stale"

    local counterpart_state="unreachable"
    if [ -d "$counterpart" ]; then
      local counterpart_head
      counterpart_head="$(git -C "$counterpart" rev-parse HEAD 2>/dev/null || true)"
      if [ -n "$counterpart_head" ]; then
        [ "$counterpart_head" = "$consumer_recorded" ] && counterpart_state="fresh" || counterpart_state="stale"
      fi
    fi

    printf 'REL role=%s symbol=%s status=%s counterpart_repo=%s own_state=%s counterpart_state=%s\n' \
      "$role" "$rec_symbol" "$rec_status" "$counterpart" "$own_state" "$counterpart_state"
    count=$((count + 1))
  done

  printf 'rel:count=%s\n' "$count"
}

# hook_block <script_path> <root>: the managed shell snippet installed
# into each Git hook file. It only ever triggers `refresh-async` (never
# blocks, never fails) and ends in `true` so the managed block's own exit
# status can never affect the rest of the hook file, whatever shell runs it.
hook_block() {
  local script_path="$1" root="$2"
  printf '%s\n' "$HOOK_MARK_BEGIN"
  printf '# Triggers a bounded, backgrounded repository-context refresh.\n'
  printf '# Returns immediately either way; never fails this Git operation.\n'
  printf 'command -v bash >/dev/null 2>&1 && bash %s refresh-async %s >/dev/null 2>&1\n' \
    "$(shell_quote "$script_path")" "$(shell_quote "$root")"
  printf 'true\n'
  printf '%s\n' "$HOOK_MARK_END"
}

# install_one_hook <hook_file> <block>: installs/replaces only the
# managed block, inserted right after any existing shebang line so it
# always runs regardless of what the rest of an existing hook (Husky's
# included) does afterward, including an early `exit`. Never touches any
# other line of an existing hook file.
install_one_hook() {
  local hook_file="$1" block="$2"
  if [ -f "$hook_file" ]; then
    local tmp
    tmp="$(mktemp "${hook_file}.XXXXXX")" || return 1
    awk -v begin="$HOOK_MARK_BEGIN" -v end="$HOOK_MARK_END" '
      $0==begin {skip=1; next}
      $0==end {skip=0; next}
      skip {next}
      {print}
    ' "$hook_file" > "$tmp"

    local first_line
    first_line="$(head -n1 "$tmp")"
    if printf '%s' "$first_line" | grep -q '^#!'; then
      { printf '%s\n' "$first_line"; printf '%s\n' "$block"; tail -n +2 "$tmp"; } > "$hook_file"
    else
      { printf '%s\n' "$block"; cat "$tmp"; } > "$hook_file"
    fi
    rm -f "$tmp"
  else
    { printf '#!/usr/bin/env bash\n'; printf '%s\n' "$block"; } > "$hook_file"
  fi
  chmod +x "$hook_file"
}

cmd_install_hooks() {
  local root
  root="$(resolve_root_or_fail "${1:-}")" || exit 1
  local hooks_dir
  hooks_dir="$(hooks_dir_for "$root")" || fail "Could not resolve the Git hooks directory for $root"
  mkdir -p "$hooks_dir"

  local self
  self="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
  local block
  block="$(hook_block "$self" "$root")"

  local h
  for h in $HOOK_NAMES; do
    install_one_hook "$hooks_dir/$h" "$block"
  done
  cmd_hooks_status "$root"
}

cmd_hooks_status() {
  local root
  root="$(resolve_root_or_fail "${1:-}")" || exit 1
  local hooks_dir
  hooks_dir="$(hooks_dir_for "$root")" || fail "Could not resolve the Git hooks directory for $root"
  printf 'hooks:dir=%s\n' "$hooks_dir"

  local h all_installed=yes
  for h in $HOOK_NAMES; do
    if [ -f "$hooks_dir/$h" ] && grep -qF "$HOOK_MARK_BEGIN" "$hooks_dir/$h" 2>/dev/null; then
      printf 'hooks:%s=installed\n' "$h"
    else
      printf 'hooks:%s=missing\n' "$h"
      all_installed=no
    fi
  done
  printf 'hooks:all_installed=%s\n' "$all_installed"
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

# cmd_package <repo_root> <output_dir> [--force]
# Packages the ALREADY-BUILT index cache (metadata.txt + symbols.idx; never
# builds or rebuilds anything itself) into a versioned, integrity-checked
# artifact bundle at output_dir: repo identity, exact commit, schema/indexer
# version, and a per-file + overall sha256. Requires the cache to be FRESH
# (indexed commit == HEAD) and the working tree clean — refuses otherwise,
# so a published artifact can never be published for the wrong commit.
# Never partially writes output_dir: builds in a sibling staging dir first
# and only replaces output_dir on full success, so a failed package call
# never touches (and never replaces) whatever was already published there.
cmd_package() {
  local force=0
  local positional=()
  local a
  for a in "$@"; do
    case "$a" in
      --force) force=1 ;;
      *) positional+=("$a") ;;
    esac
  done
  local root_arg="${positional[0]:-}" out_arg="${positional[1]:-}"
  if [ -z "$root_arg" ] || [ -z "$out_arg" ]; then
    fail "Usage: repo-context.sh package <repo_root> <output_dir> [--force]"
  fi

  local root
  root="$(resolve_root_or_fail "$root_arg")" || exit 1
  local cache_dir
  cache_dir="$(cache_dir_for "$root")"
  determine_state "$root" "$cache_dir"

  if [ "$STATE" != "FRESH" ]; then
    warn "Refusing to package: cache state is $STATE, not FRESH. Run 'rebuild --force \"$root\"' against the exact commit being published first."
    return 1
  fi

  local dirty="no"
  [ -n "$(git -C "$root" status --short 2>/dev/null)" ] && dirty="yes"
  if [ "$dirty" = "yes" ]; then
    warn "Refusing to package: working tree is dirty. A published artifact must correspond exactly to a committed revision."
    return 1
  fi

  if [ -f "$out_arg/manifest.txt" ] && [ "$force" -ne 1 ]; then
    warn "Refusing to overwrite an already-packaged artifact at $out_arg (pass --force to repackage)."
    return 1
  fi

  local commit origin indexer
  commit="$(git -C "$root" rev-parse HEAD)"
  origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
  [ -z "$origin" ] && origin="none"
  indexer="$(read_field "$cache_dir/metadata.txt" indexer)"

  mkdir -p "$(dirname "$out_arg")" || fail "Could not create parent directory for $out_arg"
  local staging
  staging="$(mktemp -d "$(dirname "$out_arg")/.pkg-staging.XXXXXX")" \
    || fail "Could not create a staging directory next to $out_arg"

  local f hash_lines=""
  local manifest_file_lines=""
  for f in metadata.txt symbols.idx; do
    if [ -f "$cache_dir/$f" ]; then
      cp "$cache_dir/$f" "$staging/$f"
      local h
      h="$(digest_file "$staging/$f")"
      manifest_file_lines="${manifest_file_lines}file_sha256:${f}: ${h}
"
      hash_lines="${hash_lines}${f}:${h}
"
    fi
  done

  local bundle_sha256
  bundle_sha256="$(digest_string "$(printf '%s' "$hash_lines" | LC_ALL=C sort)")"

  {
    printf 'artifact_schema_version: %s\n' "$ARTIFACT_SCHEMA_VERSION"
    printf 'repo_origin_url: %s\n' "$origin"
    printf 'commit: %s\n' "$commit"
    printf 'indexer: %s\n' "$indexer"
    printf 'cache_schema_version: %s\n' "$CACHE_SCHEMA_VERSION"
    printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s' "$manifest_file_lines"
    printf 'bundle_sha256: %s\n' "$bundle_sha256"
  } > "$staging/manifest.txt"

  rm -rf "$out_arg"
  mv "$staging" "$out_arg"

  printf 'pkg:status=ok\n'
  printf 'pkg:output=%s\n' "$out_arg"
  printf 'pkg:repo_root=%s\n' "$root"
  printf 'pkg:commit=%s\n' "$commit"
  printf 'pkg:indexer=%s\n' "$indexer"
  printf 'pkg:bundle_sha256=%s\n' "$bundle_sha256"
  return 0
}

# cmd_verify <bundle_dir>
# Recomputes every file's sha256 and the overall bundle_sha256 from a
# packaged artifact directory and compares them to what manifest.txt
# claims, so an engineer (or a pipeline, before/after retrieval) can
# actually confirm an artifact wasn't corrupted or tampered with rather
# than trusting the manifest blindly. Prints the manifest fields either
# way so the artifact can be inspected even when verification fails.
# verify_bundle <bundle_dir>: recomputes every manifest-listed file's
# sha256 and the overall bundle_sha256, comparing them against what
# manifest.txt itself claims. Sets VERIFY_OK (1/0) and, on a mismatch,
# VERIFY_REASON (missing-manifest/missing-file/checksum-mismatch/
# bundle-hash-mismatch). Never prints anything itself, so both `verify`
# (a human-facing report) and `fetch-baseline` (a silent compatibility
# gate) can reuse the exact same check and decide separately what to
# report.
verify_bundle() {
  local bundle_dir="$1"
  local manifest="$bundle_dir/manifest.txt"
  VERIFY_REASON=""
  if [ ! -f "$manifest" ]; then
    VERIFY_OK=0
    VERIFY_REASON="missing-manifest"
    return 0
  fi

  local ok=1 line f recorded actual hash_lines=""
  while IFS= read -r line; do
    case "$line" in
      file_sha256:*)
        f="${line#file_sha256:}"
        f="${f%%:*}"
        recorded="${line#file_sha256:${f}: }"
        hash_lines="${hash_lines}${f}:${recorded}
"
        if [ ! -f "$bundle_dir/$f" ]; then
          ok=0
          VERIFY_REASON="missing-file"
          continue
        fi
        actual="$(digest_file "$bundle_dir/$f")"
        if [ "$actual" != "$recorded" ]; then
          ok=0
          VERIFY_REASON="checksum-mismatch"
        fi
        ;;
    esac
  done < "$manifest"

  local recorded_bundle_sha256 recomputed_bundle_sha256
  recorded_bundle_sha256="$(read_field "$manifest" bundle_sha256)"
  recomputed_bundle_sha256="$(digest_string "$(printf '%s' "$hash_lines" | LC_ALL=C sort)")"
  if [ "$recomputed_bundle_sha256" != "$recorded_bundle_sha256" ]; then
    ok=0
    VERIFY_REASON="bundle-hash-mismatch"
  fi
  VERIFY_OK="$ok"
}

cmd_verify() {
  local bundle_dir="${1:-}"
  [ -n "$bundle_dir" ] || fail "Usage: repo-context.sh verify <bundle_dir>"
  local manifest="$bundle_dir/manifest.txt"
  if [ ! -f "$manifest" ]; then
    printf 'verify:status=missing-manifest\n'
    warn "No manifest.txt found at $bundle_dir; this does not look like a repository-context published artifact."
    return 1
  fi

  verify_bundle "$bundle_dir"

  printf 'verify:artifact_schema_version=%s\n' "$(read_field "$manifest" artifact_schema_version)"
  printf 'verify:repo_origin_url=%s\n' "$(read_field "$manifest" repo_origin_url)"
  printf 'verify:commit=%s\n' "$(read_field "$manifest" commit)"
  printf 'verify:indexer=%s\n' "$(read_field "$manifest" indexer)"
  printf 'verify:cache_schema_version=%s\n' "$(read_field "$manifest" cache_schema_version)"
  printf 'verify:generated_at=%s\n' "$(read_field "$manifest" generated_at)"
  printf 'verify:bundle_sha256=%s\n' "$(read_field "$manifest" bundle_sha256)"

  if [ "$VERIFY_OK" -eq 1 ]; then
    printf 'verify:status=ok\n'
    return 0
  else
    warn "Artifact at $bundle_dir failed integrity verification ($VERIFY_REASON)."
    printf 'verify:status=corrupt\n'
    return 1
  fi
}

# ci_publish_block <feed> <package>: the managed Azure Pipelines steps
# block wired into a repo's pipeline YAML by cmd_ci_setup, written flush
# left (sequence dash at column 0). cmd_ci_setup re-indents the whole
# block uniformly via indent_block to match wherever it's actually being
# inserted, so this function never has to know or guess the target's
# indentation convention. References the vendored copy of this script at
# $(Build.SourcesDirectory)/.ci/repository-context/repo-context.sh (see
# vendor_ci_script), never a path under ~/.kiro or $(Pipeline.Workspace):
# those only exist if whatever is running this build happens to already
# have the toolkit installed, which a fresh Microsoft-hosted agent never
# does. $(Build.SourcesDirectory) is the triggering repo's own checkout,
# guaranteed to exist on any agent, hosted or self-hosted, with nothing
# extra to provision. Also installs Universal Ctags first if it isn't
# already on the agent: without it, rebuild silently falls back to a
# direct-source search that writes no index file at all, so package
# would refuse every single run with nothing to actually publish.
# Values are substituted via plain string replacement, not shell/awk
# expansion, so the literal Azure macros ($(Build.SourcesDirectory) etc.)
# in the heredoc below are never touched by this script's own shell.
ci_publish_block() {
  local feed="$1" package="$2" block
  block="$(cat <<'YAML_EOF'
# >>> um-agentic-engineering repository-context publish (managed block) >>>
- bash: |
    set -euo pipefail
    if command -v ctags >/dev/null 2>&1 && ctags --version 2>/dev/null | grep -qi 'Universal Ctags'; then
      echo "Universal Ctags already present."
      exit 0
    fi
    SUDO=""
    [ "$(id -u)" != "0" ] && SUDO="sudo"
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get update -y && $SUDO apt-get install -y universal-ctags
    elif command -v brew >/dev/null 2>&1; then
      brew install universal-ctags
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y ctags
    elif command -v apk >/dev/null 2>&1; then
      $SUDO apk add --no-cache universal-ctags
    else
      echo "No supported package manager found to install Universal Ctags on this agent. Without it, rebuild falls back to a direct-source search with no index file, and package has nothing to publish. Install Universal Ctags on this agent image, or adjust this step for your platform." >&2
      exit 1
    fi
  displayName: 'repository-context: ensure Universal Ctags is available'

- bash: |
    set -euo pipefail
    bash "$(Build.SourcesDirectory)/.ci/repository-context/repo-context.sh" rebuild --force "$(Build.SourcesDirectory)"
  displayName: 'repository-context: rebuild index for the merged commit'

- bash: |
    set -euo pipefail
    rm -rf "$(Build.ArtifactStagingDirectory)/repo-context-baseline"
    bash "$(Build.SourcesDirectory)/.ci/repository-context/repo-context.sh" package "$(Build.SourcesDirectory)" "$(Build.ArtifactStagingDirectory)/repo-context-baseline"
  displayName: 'repository-context: package a versioned, checksummed artifact'

- bash: |
    set -euo pipefail
    bash "$(Build.SourcesDirectory)/.ci/repository-context/repo-context.sh" verify "$(Build.ArtifactStagingDirectory)/repo-context-baseline"
  displayName: 'repository-context: verify artifact integrity before publishing'

- task: UniversalPackages@0
  displayName: 'repository-context: publish baseline (no version is created unless every prior step succeeded)'
  inputs:
    command: publish
    publishDirectory: '$(Build.ArtifactStagingDirectory)/repo-context-baseline'
    vstsFeedPublish: '__ARTIFACT_FEED__'
    vstsFeedPackagePublish: '__PACKAGE_NAME__'
    versionOption: custom
    versionPublish: '0.0.$(Build.BuildId)'
# <<< um-agentic-engineering repository-context publish <<<
YAML_EOF
)"
  block="${block//__ARTIFACT_FEED__/$feed}"
  block="${block//__PACKAGE_NAME__/$package}"
  printf '%s\n' "$block"
}

# indent_block <n>: filter that prefixes every non-blank line of stdin
# with <n> spaces, leaving blank lines blank. Used to re-indent
# ci_publish_block's flush-left output to match wherever it's inserted.
indent_block() {
  local n="$1" pad line
  pad="$(printf '%*s' "$n" '')"
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      printf '\n'
    else
      printf '%s%s\n' "$pad" "$line"
    fi
  done
}

# detect_steps_indent <file> <steps_line_no>: looks at the lines after a
# known `steps:` key for the first one that's a sequence item (optionally
# past blank/comment-only lines) and prints how many leading spaces it
# has. Prints nothing (caller defaults) if the list is empty, the file
# ends first, or a line that's neither blank, a comment, nor a sequence
# item is hit (a different, unrelated key: stop looking, don't guess).
detect_steps_indent() {
  local file="$1" steps_line="$2" total line trimmed
  local i
  i=$(( steps_line + 1 ))
  total="$(wc -l < "$file" | tr -d ' ')"
  while [ "$i" -le "$total" ]; do
    line="$(sed -n "${i}p" "$file")"
    trimmed="${line#"${line%%[![:space:]]*}"}"
    if [ -z "$trimmed" ]; then
      i=$((i + 1)); continue
    fi
    case "$trimmed" in
      '#'*) i=$((i + 1)); continue ;;
      -*) printf '%s' $(( ${#line} - ${#trimmed} )); return 0 ;;
      *) return 1 ;;
    esac
  done
  return 1
}

# detect_default_branch <repo_root>: the branch a freshly-created pipeline
# file's trigger should target. Prefers the remote's actual default branch
# (accurate once origin/HEAD has been fetched/set), falls back to whatever
# branch is currently checked out (the best available guess for a repo
# with no remote yet), and only falls back to the literal "main" if
# neither is available, since guessing wrong here would mean the trigger
# silently never fires.
detect_default_branch() {
  local root="$1" ref
  ref="$(git -C "$root" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$ref" ]; then
    printf '%s' "${ref#origin/}"
    return 0
  fi
  ref="$(git -C "$root" branch --show-current 2>/dev/null || true)"
  if [ -n "$ref" ]; then
    printf '%s' "$ref"
    return 0
  fi
  printf 'main'
}

# vendor_ci_script <repo_root>: copies this running repo-context.sh into
# the target repo at CI_VENDOR_REL. The generated pipeline steps always
# call that vendored copy, under $(Build.SourcesDirectory), never a path
# under ~/.kiro or $(Pipeline.Workspace), because the triggering repo's
# own checkout is the only thing any build agent (hosted or self-hosted)
# is ever guaranteed to already have; nothing else can be assumed to be
# pre-installed there. This is a pinned snapshot, not a live link: it
# always re-copies on a re-run, so re-running ci-setup after this script
# changes is how a team picks up a fix for CI purposes.
vendor_ci_script() {
  local root="$1" self dest
  self="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
  dest="$root/$CI_VENDOR_REL"
  mkdir -p "$(dirname "$dest")" || fail "Could not create parent directory for $dest"
  cp "$self" "$dest" || fail "Could not vendor $self to $dest"
  chmod +x "$dest"
}

# cmd_ci_setup <repo_root> --feed <project/feed> [--package <name>] [--pipeline-file <path>]
# Wires the rebuild, then package, then verify, then publish sequence
# directly into the repo's own Azure Pipelines YAML, so a team never
# hand-copies this. --pipeline-file defaults to azure-pipelines.yml at the
# repo root (Azure DevOps's own default when a pipeline is first created
# from the UI); pass it explicitly when a repo's actual pipeline lives at
# a different path, or this would create a second, never-triggered file
# instead of editing the real one. Must be a relative path inside the
# repo (no leading "/", no ".." segments).
#
# Creates the file fresh if it doesn't exist yet at that path, using
# whichever branch detect_default_branch resolves as the trigger (a
# brand-new repo also still needs a human, once, to connect that file as
# a Pipeline inside Azure DevOps itself; writing the YAML cannot do that,
# and this command says so).
#
# Otherwise inserts (or, on a re-run, replaces only) a clearly marked
# block right after the file's single top-level `steps:` key, matching
# whatever indentation that file's own steps already use (detect_steps_
# indent), not a hardcoded one, so this never produces invalid YAML
# against a real hand-written pipeline. Refuses, rather than guessing,
# when: the file has `trigger: none` (the publish steps would then never
# actually run post-merge, defeating the entire point); or the file
# doesn't have exactly one top-level `steps:` key (typically a
# multi-stage pipeline, where the real `steps:` lives nested under each
# job, not at the top level).
cmd_ci_setup() {
  local positional=() feed="" package="" pipeline_rel=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --feed) feed="${2:-}"; shift 2 ;;
      --package) package="${2:-}"; shift 2 ;;
      --pipeline-file) pipeline_rel="${2:-}"; shift 2 ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  local root_arg="${positional[0]:-}"
  [ -n "$feed" ] || fail "Usage: repo-context.sh ci-setup <repo_root> --feed <Project/Feed> [--package <name>] [--pipeline-file <path>]"

  local root
  root="$(resolve_root_or_fail "$root_arg")" || exit 1
  [ -n "$package" ] || package="repository-context-baseline-$(basename "$root")"
  [ -n "$pipeline_rel" ] || pipeline_rel="azure-pipelines.yml"
  case "$pipeline_rel" in
    /*) fail "--pipeline-file must be relative to the repo root, not absolute: $pipeline_rel" ;;
    *..*) fail "--pipeline-file must stay inside the repository; '..' segments are not allowed: $pipeline_rel" ;;
  esac

  local pipeline_file="$root/$pipeline_rel"

  if [ ! -f "$pipeline_file" ]; then
    local branch
    branch="$(detect_default_branch "$root")"
    local block
    block="$(ci_publish_block "$feed" "$package" | indent_block 2)"
    mkdir -p "$(dirname "$pipeline_file")" || fail "Could not create parent directory for $pipeline_file"
    vendor_ci_script "$root"
    {
      printf 'trigger:\n'
      printf '  branches:\n'
      printf '    include: [ %s ]\n' "$branch"
      printf '\n'
      printf 'steps:\n'
      printf '%s\n' "$block"
    } > "$pipeline_file"
    printf 'ci:status=created\n'
    printf 'ci:file=%s\n' "$pipeline_file"
    printf 'ci:trigger_branch=%s\n' "$branch"
    printf 'ci:vendored_script=%s\n' "$root/$CI_VENDOR_REL"
    printf 'ci:feed=%s\n' "$feed"
    printf 'ci:package=%s\n' "$package"
    warn "Created $pipeline_file (and vendored $CI_VENDOR_REL, commit both), triggered on '$branch'. If this repo's pipeline actually lives at a different path, re-run with --pipeline-file <path> instead, this new file won't run until something points Azure DevOps at it. And if this repo has no Pipeline connected in Azure DevOps at all yet, that one connection has to be made once, in Azure DevOps itself (New Pipeline, use existing YAML file, select this path), nothing here can do that part."
    return 0
  fi

  if grep -qE '^trigger:[[:space:]]*none[[:space:]]*$' "$pipeline_file"; then
    warn "Refusing to edit $pipeline_file: it has 'trigger: none', so a push/merge never runs this pipeline at all. Wiring the publish steps in here would mean they never run post-merge either, which defeats the point. Resolve that trigger first (or wire this into whichever pipeline actually runs on merge), then re-run ci-setup."
    return 1
  fi

  local stripped
  stripped="$(mktemp "${pipeline_file}.stripped.XXXXXX")" || fail "Could not create a temp file next to $pipeline_file"
  awk -v begin="$CI_MARK_BEGIN" -v end="$CI_MARK_END" '
    index($0, begin) { skip=1; next }
    index($0, end) { skip=0; next }
    skip {next}
    {print}
  ' "$pipeline_file" > "$stripped"

  local steps_count
  steps_count="$(grep -cE '^steps:[[:space:]]*(#.*)?$' "$stripped")"
  if [ "$steps_count" -ne 1 ]; then
    local block_preview
    block_preview="$(ci_publish_block "$feed" "$package" | indent_block 2)"
    rm -f "$stripped"
    warn "Refusing to edit $pipeline_file automatically: expected exactly one top-level 'steps:' key, found $steps_count. This usually means multiple stages/jobs, where the real steps: lives nested under each job. Insert this block by hand under the right job's steps:"
    printf '%s\n' "$block_preview" >&2
    return 1
  fi

  local line_no indent block
  line_no="$(grep -nE '^steps:[[:space:]]*(#.*)?$' "$stripped" | head -n1 | cut -d: -f1)"
  indent="$(detect_steps_indent "$stripped" "$line_no")" || indent=2
  block="$(ci_publish_block "$feed" "$package" | indent_block "$indent")"

  local tmp
  tmp="$(mktemp "${pipeline_file}.XXXXXX")" || { rm -f "$stripped"; fail "Could not create a temp file next to $pipeline_file"; }
  { head -n "$line_no" "$stripped"; printf '%s\n' "$block"; tail -n "+$((line_no + 1))" "$stripped"; } > "$tmp"
  mv "$tmp" "$pipeline_file"
  rm -f "$stripped"
  vendor_ci_script "$root"

  printf 'ci:status=updated\n'
  printf 'ci:file=%s\n' "$pipeline_file"
  printf 'ci:vendored_script=%s\n' "$root/$CI_VENDOR_REL"
  printf 'ci:feed=%s\n' "$feed"
  printf 'ci:package=%s\n' "$package"
}

# cmd_ci_setup_status <repo_root> [--pipeline-file <path>]: read-only check
# for whether cmd_ci_setup has already wired this repo's pipeline file
# (default azure-pipelines.yml; pass --pipeline-file to match a non-default
# path exactly as it was given to ci-setup).
cmd_ci_setup_status() {
  local positional=() pipeline_rel=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --pipeline-file) pipeline_rel="${2:-}"; shift 2 ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  local root
  root="$(resolve_root_or_fail "${positional[0]:-}")" || exit 1
  [ -n "$pipeline_rel" ] || pipeline_rel="azure-pipelines.yml"
  local pipeline_file="$root/$pipeline_rel"
  printf 'ci:file=%s\n' "$pipeline_file"
  if [ -f "$pipeline_file" ] && grep -qF "$CI_MARK_BEGIN" "$pipeline_file" 2>/dev/null; then
    printf 'ci:publish_configured=yes\n'
  else
    printf 'ci:publish_configured=no\n'
  fi
}

# configured_feed_and_package <repo_root> [--pipeline-file <path>]
# Reads the feed/package this repo already publishes to, straight out of
# its own committed, ci-setup-managed pipeline block (default
# azure-pipelines.yml), never a separate config file, so there's nothing
# new for an engineer to maintain or for fetch-baseline to go out of sync
# with. Sets CFG_FEED/CFG_PACKAGE and returns 0 only when both were found.
configured_feed_and_package() {
  local positional=() pipeline_rel=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --pipeline-file) pipeline_rel="${2:-}"; shift 2 ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  local root="${positional[0]:-}"
  [ -n "$pipeline_rel" ] || pipeline_rel="azure-pipelines.yml"
  local pipeline_file="$root/$pipeline_rel"
  [ -f "$pipeline_file" ] || return 1

  local block
  block="$(awk -v begin="$CI_MARK_BEGIN" -v end="$CI_MARK_END" '
    index($0, begin) { inblock=1; next }
    index($0, end) { inblock=0; next }
    inblock { print }
  ' "$pipeline_file")"
  [ -n "$block" ] || return 1

  CFG_FEED="$(printf '%s\n' "$block" | grep -m1 'vstsFeedPublish:' | sed -E "s/^[[:space:]]*vstsFeedPublish:[[:space:]]*'?([^']*)'?[[:space:]]*$/\1/")"
  CFG_PACKAGE="$(printf '%s\n' "$block" | grep -m1 'vstsFeedPackagePublish:' | sed -E "s/^[[:space:]]*vstsFeedPackagePublish:[[:space:]]*'?([^']*)'?[[:space:]]*$/\1/")"
  [ -n "$CFG_FEED" ] && [ -n "$CFG_PACKAGE" ]
}

# detect_ado_organization_url <repo_root>: best-effort derivation of the
# Azure DevOps organization/collection URL `az artifacts universal
# download` needs, straight from this repo's own `origin` remote, so
# fetch-baseline never has to ask anyone for it. Recognizes Azure DevOps
# Services (dev.azure.com, both https and the ssh.dev.azure.com form, and
# the legacy <org>.visualstudio.com form) and a conventional on-prem
# Azure DevOps Server layout (.../tfs/<collection>/...). Prints nothing
# and returns 1 if the remote doesn't look like any of those; callers
# must then require an explicit --org rather than guess.
detect_ado_organization_url() {
  local root="$1" origin
  origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
  [ -n "$origin" ] || return 1

  case "$origin" in
    *@ssh.dev.azure.com:v3/*)
      local rest="${origin#*ssh.dev.azure.com:v3/}"
      printf 'https://dev.azure.com/%s' "${rest%%/*}"
      return 0
      ;;
    https://*dev.azure.com/*)
      local rest="${origin#*dev.azure.com/}"
      rest="${rest#*@}"
      printf 'https://dev.azure.com/%s' "${rest%%/*}"
      return 0
      ;;
    https://*.visualstudio.com/*)
      local host="${origin#https://}"
      host="${host#*@}"
      printf 'https://%s' "${host%%/*}"
      return 0
      ;;
    *)
      if printf '%s' "$origin" | grep -qE '^https?://[^/]+/tfs/'; then
        printf '%s' "$origin" | sed -E 's#^(https?://[^/]+/tfs/[^/]+).*#\1#'
        return 0
      fi
      return 1
      ;;
  esac
}

# cmd_fetch_baseline <repo_root> [--feed <Project/Feed>] [--org <url>]
#                     [--package <name>] [--version <ver>] [--from <dir>]
#                     [--force]
# The consume-side counterpart to package/verify/ci-setup (PBI 297918):
# reuse a baseline someone else's CI already published instead of
# rebuilding one from scratch locally. Never a second indexer and never a
# new cache format: on success this installs the exact same
# metadata.txt/symbols.idx pair `rebuild` itself would have produced into
# this repo's own cache directory, so every existing command (status,
# lookup, diff, ...) picks it up completely unchanged. Anything that
# isn't a clean, verified, matching-repo, matching-schema artifact is
# rejected outright and the local cache is left exactly as it was,
# leaving the normal rebuild/direct-source fallback to take over, same as
# if fetch-baseline had never been called at all.
#
# --feed/--package default to whatever this repo's own ci-setup already
# configured (read straight out of its committed pipeline file via
# configured_feed_and_package), and --org defaults to whatever
# detect_ado_organization_url can derive from the `origin` remote, so the
# common case needs zero flags. --from <dir> skips the network call
# entirely and adopts an already-retrieved bundle directly, the fully
# offline-testable path, and also the realistic path for any CI step
# that has already downloaded the artifact into a working directory.
#
# The actual `az artifacts universal download` call is the one piece of
# this command this toolkit cannot verify without a live Azure DevOps
# connection (same category as `UniversalPackages@0` on the publish
# side): if `az` isn't installed, isn't logged in, or the call fails for
# any reason, that's reported as `fetch:status=unavailable` and treated
# exactly like "no baseline to offer", never a hard error.
cmd_fetch_baseline() {
  local positional=() feed="" org="" package="" version="*" from_dir="" force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --feed) feed="${2:-}"; shift 2 ;;
      --org) org="${2:-}"; shift 2 ;;
      --package) package="${2:-}"; shift 2 ;;
      --version) version="${2:-}"; shift 2 ;;
      --from) from_dir="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  local root
  root="$(resolve_root_or_fail "${positional[0]:-}")" || exit 1
  local cache_dir
  cache_dir="$(cache_dir_for "$root")"

  determine_state "$root" "$cache_dir"
  if [ "$STATE" = "FRESH" ] && [ "$force" -ne 1 ]; then
    printf 'fetch:status=skipped\n'
    printf 'fetch:reason=local-already-fresh\n'
    return 0
  fi

  mkdir -p "$(cache_home)"
  local bundle_dir cleanup_bundle=0

  if [ -n "$from_dir" ]; then
    if [ ! -d "$from_dir" ]; then
      printf 'fetch:status=unavailable\n'
      printf 'fetch:reason=from-dir-missing\n'
      warn "No directory at $from_dir to fetch from."
      return 1
    fi
    bundle_dir="$from_dir"
  else
    if [ -z "$feed" ] || [ -z "$package" ]; then
      if configured_feed_and_package "$root"; then
        [ -z "$feed" ] && feed="$CFG_FEED"
        [ -z "$package" ] && package="$CFG_PACKAGE"
      fi
    fi
    if [ -z "$feed" ]; then
      printf 'fetch:status=unavailable\n'
      printf 'fetch:reason=no-feed-configured\n'
      warn "No --feed given and this repo's pipeline isn't ci-setup'd yet; pass --feed <Project/Feed> explicitly, or run ci-setup first."
      return 1
    fi
    [ -n "$package" ] || package="repository-context-baseline-$(basename "$root")"
    if [ -z "$org" ]; then
      org="$(detect_ado_organization_url "$root")"
    fi
    if [ -z "$org" ]; then
      printf 'fetch:status=unavailable\n'
      printf 'fetch:reason=no-organization-detected\n'
      warn "Could not derive an Azure DevOps organization URL from this repo's origin remote; pass --org <https://dev.azure.com/YourOrg> explicitly."
      return 1
    fi
    if ! command -v az >/dev/null 2>&1; then
      printf 'fetch:status=unavailable\n'
      printf 'fetch:reason=az-cli-missing\n'
      warn "Azure CLI ('az') is not installed; cannot fetch a published baseline."
      return 1
    fi

    case "$feed" in
      */*) : ;;
      *)
        printf 'fetch:status=unavailable\n'
        printf 'fetch:reason=invalid-feed-format\n'
        warn "--feed must be '<Project>/<Feed>', got: $feed"
        return 1
        ;;
    esac
    local project="${feed%%/*}" feed_name="${feed#*/}"

    local staging errlog
    staging="$(mktemp -d "$(cache_home)/.fetch-staging.XXXXXX")" || {
      printf 'fetch:status=unavailable\n'
      printf 'fetch:reason=staging-failed\n'
      return 1
    }
    errlog="$(mktemp "$(cache_home)/.fetch-err.XXXXXX")" || {
      rm -rf "$staging"
      printf 'fetch:status=unavailable\n'
      printf 'fetch:reason=staging-failed\n'
      return 1
    }
    if ! az artifacts universal download \
        --organization "$org" --project "$project" --feed "$feed_name" \
        --name "$package" --version "$version" --path "$staging" \
        >/dev/null 2>"$errlog"; then
      warn "az artifacts universal download failed: $(cat "$errlog" 2>/dev/null | tail -n1)"
      rm -rf "$staging"; rm -f "$errlog"
      printf 'fetch:status=unavailable\n'
      printf 'fetch:reason=download-failed\n'
      return 1
    fi
    rm -f "$errlog"
    bundle_dir="$staging"
    cleanup_bundle=1
  fi

  verify_bundle "$bundle_dir"
  if [ "$VERIFY_OK" -ne 1 ]; then
    [ "$cleanup_bundle" -eq 1 ] && rm -rf "$bundle_dir"
    printf 'fetch:status=rejected\n'
    printf 'fetch:reason=%s\n' "${VERIFY_REASON:-corrupt}"
    warn "Published artifact at $bundle_dir failed integrity verification ($VERIFY_REASON); not adopting it."
    return 1
  fi

  local manifest="$bundle_dir/manifest.txt"
  local m_schema m_cache_schema m_origin m_commit m_indexer my_origin
  m_schema="$(read_field "$manifest" artifact_schema_version)"
  m_cache_schema="$(read_field "$manifest" cache_schema_version)"
  m_origin="$(read_field "$manifest" repo_origin_url)"
  m_commit="$(read_field "$manifest" commit)"
  m_indexer="$(read_field "$manifest" indexer)"
  my_origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
  [ -z "$my_origin" ] && my_origin="none"

  if [ "$m_schema" != "$ARTIFACT_SCHEMA_VERSION" ] || [ "$m_cache_schema" != "$CACHE_SCHEMA_VERSION" ]; then
    [ "$cleanup_bundle" -eq 1 ] && rm -rf "$bundle_dir"
    printf 'fetch:status=rejected\n'
    printf 'fetch:reason=incompatible-schema\n'
    warn "Published artifact's schema (artifact=$m_schema, cache=$m_cache_schema) doesn't match this script (artifact=$ARTIFACT_SCHEMA_VERSION, cache=$CACHE_SCHEMA_VERSION); not adopting it."
    return 1
  fi

  if [ "$m_origin" != "$my_origin" ]; then
    [ "$cleanup_bundle" -eq 1 ] && rm -rf "$bundle_dir"
    printf 'fetch:status=rejected\n'
    printf 'fetch:reason=repo-mismatch\n'
    warn "Published artifact is for a different repository ($m_origin), not this one ($my_origin); not adopting it."
    return 1
  fi

  local adopt_staging
  adopt_staging="$(mktemp -d "$(cache_home)/.adopt-staging.XXXXXX")" || fail "Could not create a staging directory to adopt into"
  grep -v '^source: ' "$bundle_dir/metadata.txt" > "$adopt_staging/metadata.txt"
  printf 'source: published\n' >> "$adopt_staging/metadata.txt"
  [ -f "$bundle_dir/symbols.idx" ] && cp "$bundle_dir/symbols.idx" "$adopt_staging/symbols.idx"
  rm -rf "$cache_dir"
  mv "$adopt_staging" "$cache_dir"
  [ "$cleanup_bundle" -eq 1 ] && rm -rf "$bundle_dir"

  local head relation
  head="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo none)"
  if [ "$m_commit" = "$head" ]; then
    relation="exact"
  elif git -C "$root" merge-base --is-ancestor "$m_commit" "$head" 2>/dev/null; then
    relation="ancestor-of-head"
  else
    relation="diverged"
  fi

  printf 'fetch:status=adopted\n'
  printf 'fetch:repo_root=%s\n' "$root"
  printf 'fetch:artifact_commit=%s\n' "$m_commit"
  printf 'fetch:head=%s\n' "$head"
  printf 'fetch:relation_to_head=%s\n' "$relation"
  printf 'fetch:indexer=%s\n' "$m_indexer"
  return 0
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
  repo-context.sh relations-for <repo_root> [symbol]
                                                  List every previously recorded relationship involving
                                                  this repo, optionally filtered to one symbol.
  repo-context.sh indexer-check                  Report whether Universal Ctags is available (no repo needed).
  repo-context.sh refresh       [repo_root]      Bounded rebuild only if the cache isn't already fresh.
  repo-context.sh refresh-async [repo_root]      Fire-and-forget refresh: returns immediately, never fails.
  repo-context.sh install-hooks [repo_root]      Install Git hooks that call refresh-async after commits,
                                                  merges, and branch switches. Coexists with existing hooks.
  repo-context.sh hooks-status  [repo_root]      Report which of those hooks are installed (read-only).
  repo-context.sh package <repo_root> <output_dir> [--force]
                                                  Package the already-built index cache into a versioned,
                                                  checksummed artifact bundle for the current commit. Refuses
                                                  if the cache isn't FRESH or the working tree is dirty.
  repo-context.sh verify  <bundle_dir>           Recompute and check a packaged artifact's checksums; prints
                                                  its manifest fields either way (repo/commit/schema/indexer).
  repo-context.sh ci-setup <repo_root> --feed <Project/Feed> [--package <name>] [--pipeline-file <path>]
                                                  Wire rebuild, then package, then verify, then publish
                                                  directly into the repo's own Azure Pipelines YAML (default
                                                  azure-pipelines.yml; pass --pipeline-file if the real one
                                                  lives elsewhere). Creates it if missing. Re-running
                                                  replaces only its own previously-installed block.
  repo-context.sh ci-setup-status [repo_root] [--pipeline-file <path>]
                                                  Report whether ci-setup has already configured this repo
                                                  (read-only).
  repo-context.sh fetch-baseline [repo_root] [--feed <Project/Feed>] [--org <url>]
                                 [--package <name>] [--version <ver>] [--from <dir>] [--force]
                                                  Adopt a compatible published baseline (verified, matching
                                                  repo and schema) as this repo's local cache instead of
                                                  rebuilding one. --feed/--package default to whatever
                                                  ci-setup already configured for this repo; --org defaults
                                                  to whatever can be derived from the origin remote.
                                                  --from <dir> adopts an already-downloaded bundle directly,
                                                  skipping the network call. Rejects (and leaves the local
                                                  cache untouched) anything corrupt, schema-incompatible, or
                                                  published for a different repository.
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
  relations-for) cmd_relations_for "${ARGS[@]}" ;;
  indexer-check) cmd_indexer_check ;;
  refresh)       cmd_refresh "${ARGS[@]}" ;;
  refresh-async) cmd_refresh_async "${ARGS[@]}" ;;
  install-hooks) cmd_install_hooks "${ARGS[@]}" ;;
  hooks-status)  cmd_hooks_status "${ARGS[@]}" ;;
  package)       cmd_package "${ARGS[@]}" ;;
  verify)        cmd_verify "${ARGS[@]}" ;;
  ci-setup)        cmd_ci_setup "${ARGS[@]}" ;;
  ci-setup-status) cmd_ci_setup_status "${ARGS[@]}" ;;
  fetch-baseline)  cmd_fetch_baseline "${ARGS[@]}" ;;
  --help|-h|help|"") show_help ;;
  *) fail "Unknown command: $ACTION (see --help)" ;;
esac
