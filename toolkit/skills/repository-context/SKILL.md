---
name: repository-context
description: Use when a question needs a specific symbol, file, or code-path location in the current repository with verifiable evidence — e.g. "where is X defined", "what calls Y", "show me the function for Z", "is this file:line still accurate" — or when a question asks whether one repository actually depends on another through a named contract, e.g. "what consumes this API", "does repo B still call this function from repo A". Returns file:line evidence, the repository's current revision, and flags stale or uncommitted context rather than silently trusting a cache.
metadata:
  author: um-agentic-engineering
  version: 1.1.0
---

# Repository Context

Answer a symbol/reference/code-path question about the **current**
repository with verifiable file:line evidence, tagged with the repository's
revision and freshness — rather than re-scanning the whole repository from
scratch on every question, and rather than silently trusting a cache that
might be stale, corrupt, or missing.

This skill is generic: it must work in any git repository, not just this
toolkit's own repo. It never modifies repository state — read-only, like
`repo-snapshot`.

## Steps

1. Resolve the repository root: `git rev-parse --show-toplevel`. If this
   fails, say so and stop — do not guess at a repository root.
2. Find this skill's own installed directory (the folder this `SKILL.md`
   lives in — typically `~/.kiro/skills/repository-context/`) and run:
   ```
   bash <that-dir>/repo-context.sh lookup "<symbol>" "<repo-root>"
   ```
   Invoke it with `bash <path>`, not `<path>` directly — that way a lost
   executable bit on the script can never silently break the skill.
3. The script prints a small header followed by `RESULT`/`DIFF` lines:
   - `ctx:head` — the repository's current commit.
   - `ctx:dirty` — whether the working tree has uncommitted changes.
   - `ctx:index_state` — `fresh`, `rebuilt`, `stale-by-revision`, or
     `fallback`. `stale-by-revision` means the cached index was built
     against an older commit than `ctx:head` — this is expected and not an
     error; the script already overlays live `git diff`/`git status`
     results on top so nothing uncommitted or newly committed goes
     missing just because the base index wasn't rebuilt.
   - `ctx:indexer` — either `universal-ctags <version>` or
     `direct-source-fallback`.
   - `ctx:fallback_reason` — present only when `index_state=fallback`
     (e.g. `indexer-unavailable`, `too-many-files`, `rebuild-failed`).
   - `RESULT symbol=... kind=... file=... line=... source=... confidence=...`
     — one per hit. `confidence=confirmed` means it came from an actual
     Universal Ctags definition (`source=index`); `confidence=inferred`
     means it came from a textual scan (`source=grep` or `source=diff`) —
     a real hit, but not a verified structural relationship (it could be a
     comment, a string, or an unrelated same-named symbol elsewhere).
   - `DIFF status=... path=...` — a currently changed (staged or unstaged)
     file, from `git status --short`.
4. Report back to the user:
   - The file:line evidence for each result, **labeled** `confirmed` or
     `inferred` — never present an inferred/grep hit as a verified
     structural relationship.
   - The repository's current revision (`ctx:head`), and plainly say when
     the working tree is dirty or the base index is stale-by-revision.
   - If `ctx:indexer=direct-source-fallback`, say so plainly (e.g. "no
     code-aware indexer was available, so this used a text search instead
     of structural analysis") rather than silently presenting fallback
     results as if they came from a richer index. If
     `ctx:fallback_reason=indexer-unavailable` specifically, also tell the
     user the fix right then, in that same message, not just that
     something's missing: "install Universal Ctags for verified results —
     `brew install universal-ctags` (macOS) or `apt-get install
     universal-ctags` (Linux/WSL)." Don't make them go find that
     themselves in the docs.
5. For a "what changed" / "is this still accurate" question instead of a
   symbol lookup, run `lookup`'s diff-only counterpart:
   ```
   bash <that-dir>/repo-context.sh diff "<repo-root>"
   ```
6. Do not run any command that changes repository state. The script itself
   only ever writes to its own cache directory under
   `~/.kiro/.um-agentic-engineering/repo-context/`, never inside the
   repository being analyzed.

## Cross-repository dependency lookup (provider/consumer)

Use this when asked whether two **different** repositories actually depend
on each other through one specific named contract — e.g. "does repo B call
`fetch_order_status` from repo A?", "what consumes this API?", "is anyone
still using `OrderValidator`?" across repos. This is intentionally narrow:
it only confirms or denies that **one named symbol** has real textual
evidence on both sides (a provider's definition/reference and a consumer's
reference to the same name). It is not organization-wide dependency
discovery, and it does not claim dependency types beyond "the same name is
genuinely present in both repositories" — no network tracing, no schema
matching, no semantic API binding.

1. Identify the **provider** repository (where the contract — a function,
   endpoint handler, exported symbol — is defined or expected to live), the
   **consumer** repository (where it's expected to be called/used), and the
   exact symbol name to check. Both repositories must already be cloned
   locally — this never clones, fetches, or otherwise reaches a remote.
2. Run:
   ```
   bash <that-dir>/repo-context.sh relate "<symbol>" "<provider-repo-root>" "<consumer-repo-root>"
   ```
3. Read `rel:status`:
   - `supported` — real evidence was found on **both** sides. Report the
     `PROVIDER ...` and `CONSUMER ...` lines back to the user exactly like
     `lookup`'s `RESULT` lines — same `confidence=confirmed`/`inferred`
     distinction, never presented as more certain than it is — along with
     `rel:provider_head`/`rel:consumer_head` (the commit each side's
     evidence was found at).
   - `unknown` — evidence was missing on at least one side. Say plainly
     that no supported relationship was found between these two
     repositories for that symbol — **never infer or invent a dependency**
     just because the name sounds related or the two repos are known to
     interact some other way.
4. The result is also persisted as a lightweight relationship record
   (repository identities, commits, and evidence — no graph database, no
   second indexer) under
   `~/.kiro/.um-agentic-engineering/repo-relations/`. To check whether a
   previously found relationship is still current **without** re-running
   the full lookup, use:
   ```
   bash <that-dir>/repo-context.sh relate-status "<symbol>" "<provider-repo-root>" "<consumer-repo-root>"
   ```
   - `rel:record=missing` — this symbol/repo-pair has never been checked;
     run `relate` first.
   - `rel:overall=fresh` — both repositories are still at the commit the
     relationship was recorded at; the stored evidence still applies.
   - `rel:overall=stale` — one or both repositories have moved on since the
     record was written. Say so, then re-run `relate` to refresh it with
     current evidence — the refreshed result may flip `supported` to
     `unknown`, or vice versa, if the dependency was added or removed. This
     reuses the exact same revision-comparison idea as single-repo
     `lookup`'s `stale-by-revision`, not a new staleness model.

## Notes

- This skill is installed globally (`~/.kiro/skills/repository-context/`)
  by the `um-agentic-engineering` toolkit installer, the same way as
  `repo-snapshot` — see the toolkit's `docs/SETUP.md`.
- `repo-context.sh` works standalone from this directory; it doesn't need
  to be invoked through any other tool.
- Indexing prefers Universal Ctags when it's actually installed and on
  `PATH` (not just anything named `ctags` — see `docs/TROUBLESHOOTING.md`
  if results always say `direct-source-fallback` despite a `ctags` binary
  existing). Without it, every answer comes from a direct text search
  instead — still correct, just without the `confirmed`/definition
  distinction.
- The generated cache is local, disposable, and safe to delete at any
  time; the next call just rebuilds or falls back. There is no database,
  daemon, or file watcher involved.
- Run `bash <that-dir>/repo-context.sh --help` for the full command
  surface (`status`, `rebuild`, `lookup`, `diff`, `relate`,
  `relate-status`).
