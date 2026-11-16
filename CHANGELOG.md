# Changelog

Nothing in this repo has been tagged/released yet — there is no approved
`vX.Y.Z` release, so there's no version number to attach to any of this
until a maintainer cuts the first one. Everything below is accumulated,
unreleased work (PBI 297784 + PBI 297785 + PBI 297787 + PBI 297793).

## Unreleased

- Established the repo layout: `toolkit/` (global, installable content —
  `skills/`, `steering/`, `agents/`) separated from repo-owned project
  context (`docs/`, `scripts/`).
- Sample skill: `repo-snapshot`, a read-only repo-orientation skill that
  demonstrates the toolkit working identically across unrelated repos.
- `agentic-eng`: the CLI — `install`, `update`, `version`, `rollback`,
  `uninstall`. `install.sh` is a thin day-zero bootstrap wrapper
  (`agentic-eng` can't be on PATH before it's ever been run once) that just
  calls `agentic-eng install`.
- Releases are resolved from git tags (`vX.Y.Z`, highest wins via git's own
  version-aware sort) via a persistent, tool-managed local clone at
  `~/.kiro/.um-agentic-engineering/source/` — never an arbitrary branch/HEAD,
  and never by checking out/mutating the engineer's own working clone.
  **Known gap:** no tags exist yet; `install`/`update` correctly fail until a
  maintainer publishes the first one.
- New release content is staged and validated (has a `toolkit/skills`
  directory, every skill's frontmatter matches its folder, has a description,
  steering frontmatter is well-formed) before activation — version comes
  from the tag alone, never an in-repo `VERSION` file; a failing release
  is rejected and the previously-installed release is left untouched.
  Activation itself builds each artifact at a temp path and renames it into
  place.
- A bounded local cache (`~/.kiro/.um-agentic-engineering/releases/`, exactly
  `current` + `previous` via atomically-swapped symlinks) makes `rollback`
  work with zero network access, with an integrity check before restoring.
- `agentic-eng install`/`update` self-copy to
  `~/.kiro/.um-agentic-engineering/bin/` and add that directory to `PATH`
  themselves (one marked, idempotent line in `~/.zshrc`/`~/.bashrc`), so
  later commands work from anywhere, from a new shell, without needing the
  original clone to still exist or any manual editing.
- A generated (not shipped) steering file,
  `~/.kiro/steering/um-agentic-engineering-status.md`, records the installed
  version in every agent's context; removed on uninstall.
- `scripts/smoke-test.sh`: fully offline, using disposable local git
  fixtures (never the real GitHub remote) to exercise install, idempotent
  re-install, unrelated-file preservation, update, a rejected/broken update,
  rollback (including offline), version reporting (including
  simulated-offline), uninstall, the `install.sh` bootstrap path, and a
  clean failure when the release source is unreachable.
- `docs/SETUP.md` and `docs/TROUBLESHOOTING.md`.
- New skill: `repository-context`, source-grounded symbol/reference lookup
  with verifiable file:line evidence. Shells out to Universal Ctags when
  it's positively detected on `PATH` (not just anything named `ctags` —
  stock macOS ships an unrelated BSD `ctags`), with a direct `grep`-based
  text search as the fallback and as the always-on source of reference
  hits alongside the index; every result is labeled `confidence=confirmed`
  (an actual ctags definition) or `confidence=inferred` (a textual match),
  never overclaiming a grep hit as verified structure.
- The skill's generated index/cache lives entirely outside any tracked
  repository (`~/.kiro/.um-agentic-engineering/repo-context/<hash>/`, keyed
  by the analyzed repo's origin URL or path), as flat text files (a
  `metadata.txt` with repo identity/commit/indexer/schema version, plus a
  `symbols.idx`) — no database, daemon, or file watcher.
- A bounded freshness/recovery state machine: a missing or corrupted cache
  (detected via schema-version and symbol-count cross-checks, never
  silently trusted) triggers a bounded rebuild — capped by file count and
  by a portable bash timeout wrapper that kills the whole process group,
  not just the indexer's own pid, so a hung or forking indexer can't hold
  the run open — or a clearly labeled direct-source fallback if that
  rebuild isn't possible. A cache that's merely stale by revision (HEAD
  moved past the indexed commit) is never rebuilt automatically; instead a
  live `git diff`/`git status` overlay is layered on every answer so
  staged/uncommitted/newly-committed changes are always visible without a
  full reindex.
- `scripts/repo-context-smoke-test.sh`: fully offline, exercising a fresh
  build, uncommitted/staged edits visible without reindexing, revision
  drift without an unnecessary rebuild, missing-cache and corrupt-cache
  recovery, a forced direct-source fallback, the file-count and timeout
  rebuild bounds, and a clean failure outside a git repository — passes
  meaningfully whether or not Universal Ctags happens to be installed on
  the machine running it.
- New steering file: `repository-context-awareness.md` (`inclusion:
  always`), so an engineer never has to discover `repository-context`
  manually. It tells every agent to check, once per repository per
  session, whether that repository has ever been indexed
  (`ctx:cache_state=MISSING`) and, if so, run the skill's own bounded
  rebuild itself right then with a one-line heads-up — rather than wait to
  be asked a question that needs it. Repositories that already have an
  index (fresh, stale-by-revision, or corrupt) are left alone; those cases
  are already handled by the skill itself when it's actually asked a
  question.
- New `repo-context.sh indexer-check` subcommand, and both the skill and
  the steering file now use it to proactively state the actual fix (the
  exact `brew`/`apt-get install universal-ctags` command) the moment
  Universal Ctags isn't available — once per session via steering, and
  inline whenever a lookup actually falls back for that reason — instead
  of only reporting that results are degraded and leaving the engineer to
  go find the install command in the docs themselves.
- New `repo-context.sh relate`/`relate-status`/`relations-for` subcommands
  (PBI 297793): `relate <symbol> <provider_repo> <consumer_repo>` reuses
  the exact same confirmed/inferred evidence model as `lookup`, applied to
  two different repository roots instead of one, to check whether a
  provider's contract (a defined symbol) and a consumer's reference to
  that same name both have real source evidence. `status=supported` only
  when both sides have evidence; `status=unknown` otherwise, so an
  unsupported relationship is reported as unknown, never invented. The
  result is persisted as a lightweight relationship record (repository
  identities, commits, and evidence, no graph database, no second indexer)
  under `~/.kiro/.um-agentic-engineering/repo-relations/<hash>/`, built via
  the same atomic staging-then-rename pattern as the single-repo index
  cache. `relate-status` reads a previously recorded relationship and
  compares its recorded commits against each repository's current `HEAD`
  (the same revision-comparison idea as single-repo `stale-by-revision`),
  reporting `rel:overall=stale` once either repository has moved on,
  without recomputing anything; re-running `relate` then refreshes the
  record with current evidence, which can flip `supported` to `unknown` or
  vice versa if the dependency was added or removed. `relations-for
  <repo_root> [symbol]` lists every relationship already confirmed for a
  given repository, on either side, so an agent can notice an existing
  confirmed dependency on its own instead of the engineer having to think
  to ask about it.
- New steering file: `cross-repo-dependency-awareness.md` (`inclusion:
  always`). Every time an agent is about to change an existing symbol's
  definition, it checks `relations-for` for that symbol in the current
  repo and, if another repository was previously confirmed (via `relate`)
  to depend on it, mentions that in one line before proceeding, rather
  than waiting for the engineer to remember to ask "does anything depend
  on this?" It says nothing when there's no confirmed relationship on
  record, since this only resurfaces a dependency that's already been
  confirmed once, not automatic discovery of unknown ones.
- `scripts/repo-context-smoke-test.sh` extended with cross-repo scenarios:
  a real provider/consumer dependency found with evidence on both sides, an
  unsupported relationship reported as unknown rather than invented for a
  symbol absent from both repos, a missing relationship record reported as
  such rather than guessed, the full stale-then-re-`relate`-then-fresh
  cycle after the consumer repo removes the call site, `relations-for`
  correctly reporting a confirmed relationship from either side, reporting
  `count=0` for a repo that's never been part of one, and flagging a
  counterpart repo as stale once it moves on without needing `relate`
  re-run.
