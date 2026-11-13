# Troubleshooting

## "No approved release tags found yet"

Expected until a maintainer creates the first one. There are no `vX.Y.Z`
tags in this repo yet, and `agentic-eng` intentionally refuses to fall back
to installing an arbitrary branch/commit as "the latest approved release."
Ask whoever owns the toolkit's releases to run:
```sh
git tag -a v1.0.0 <commit> -m "Initial release"
git push origin v1.0.0
```

## `agentic-eng: command not found` after install

`install`/`update` copy `agentic-eng` to
`~/.kiro/.um-agentic-engineering/bin/agentic-eng` and append a PATH line to
your `~/.zshrc`/`~/.bashrc` automatically — but that only takes effect in a
**new** shell (a running process can't change its parent shell's
environment; no tool can do that for you). Open a new terminal, or run
`source ~/.zshrc` (or `~/.bashrc`), and it'll work as a bare command. Until
then, run it via the full path, or from inside a clone as
`./agentic-eng <command>`.

## `agentic-eng update` rejected a release

This means the resolved release failed validation (no `toolkit/skills`
directory, a skill's frontmatter `name:` not matching its folder, a
missing/empty `description:`, or malformed steering frontmatter) — your
previous working
installation is left exactly as it was, untouched. This should only ever
happen if a tag was published with broken content; report it to whoever
owns the release so they can fix and re-tag.

## `agentic-eng rollback` says there's nothing to roll back to

`rollback` restores from a locally-retained cache of the *previous*
successfully-activated release. If you've only ever installed once (never
updated), there is no previous release yet — this is expected, not a bug.

## Could not check for updates (offline)

`agentic-eng version`/`update` need network access to fetch tags. If you're
offline or the remote is unreachable, `version` says so explicitly rather
than claiming you're up to date — retry once you have connectivity.
`rollback` never needs network and is unaffected.

## The warning about Kiro.app / `kiro` not being found

Informational, not fatal. The toolkit still installs to `~/.kiro/...`; Kiro
will discover it once installed, no re-install needed.

## I ran `/repo-snapshot` in Kiro and nothing happened

1. Confirm the files exist: `ls ~/.kiro/skills/repo-snapshot/SKILL.md`. If
   missing, run `agentic-eng install` (or `update`).
2. Restart Kiro or reload its window — skills load at startup, not live.
3. Global skills are an **IDE** feature. The Kiro CLI doesn't read global
   skills at all (only global steering) — a Kiro platform limitation, not a
   bug here.
4. A Kiro **custom agent** doesn't load skills by default; it needs
   `skill://~/.kiro/skills/*/SKILL.md` in its `resources` field.

## A skill/steering file I expected to be installed is missing

Check the tool's own output — it skips (warning, not failing) anything that
already exists at the target path under a name it didn't itself install, so
it never clobbers a personal skill of yours with the same name. Rename or
remove the conflicting personal file, then re-run.

## `AGENTIC_TOOLKIT_HOME`

Exists only so `scripts/smoke-test.sh` can run `agentic-eng` against a
disposable directory instead of your real home directory. Don't set it for
a real install — Kiro always reads your actual home directory regardless of
this variable. `repo-context.sh` (the `repository-context` skill's helper
script) honors the same variable for the same reason, used by
`scripts/repo-context-smoke-test.sh`.

## `repository-context` always says `direct-source-fallback`, even though `ctags` is on my PATH

Stock macOS ships a BSD `ctags` (from the Xcode Command Line Tools) under
the same command name as [Universal Ctags](https://ctags.io). The skill
checks `ctags --version` for the string "Universal Ctags" rather than just
whether a `ctags` command exists, specifically so it doesn't mistake the
unrelated BSD tool for the real thing. Install the real one
(`brew install universal-ctags` on macOS, `apt-get install universal-ctags`
on Linux/WSL) to get `confidence=confirmed` results from an actual index;
until then, every result is `confidence=inferred` from a direct text
search — still correct, just without the verified-definition distinction.

You shouldn't have to go looking for that install command yourself: both
the `repository-context` skill (when it actually falls back while
answering a question) and the `repository-context-awareness` steering
file (once per session, proactively) are supposed to state it directly
rather than just saying something's missing. Run
`bash ~/.kiro/skills/repository-context/repo-context.sh indexer-check`
directly if you want to check without waiting for either of those.

## `repository-context` reports `index_state=stale-by-revision`

Expected, not a bug — it means the cached index was built against an older
commit than the repository's current `HEAD`. The skill does not
automatically reindex on every commit (that would mean an expensive
indexing pass on every single question); instead it overlays a live `git
diff`/`git status` pass on top of the existing index so nothing uncommitted
or newly committed goes missing. Run `repo-context.sh rebuild --force` if
you want the base index itself refreshed.

## Kiro indexed a repo on its own and told me about it — did I ask for that?

Not directly, but it's expected: the `repository-context-awareness`
steering file (`inclusion: always`, installed to
`~/.kiro/steering/`) tells every agent to check, once per repository per
session, whether that repository has ever been indexed. If it hasn't
(`ctx:cache_state=MISSING`), the agent runs `repo-context.sh rebuild`
itself — bounded by the same file-count and timeout caps as any other
rebuild — and mentions it in one line. It never does this more than once
per repository per session, never reindexes a repo that already has a
cache (fresh, stale, or even corrupt — those are handled by the skill
itself when actually asked a question, not by this steering file), and
never writes anything inside the repository itself. Delete
`toolkit/steering/repository-context-awareness.md` from your installed
release (or just ignore the one-line notice) if you'd rather it stayed
fully on-demand.

## Where is `repository-context`'s generated cache, and is it safe to delete?

`~/.kiro/.um-agentic-engineering/repo-context/<hash>/`, one subdirectory per
analyzed repository (keyed by that repository's origin URL or path, not by
name). It's always safe to delete — the next lookup just triggers a bounded
rebuild, or falls back to a direct text search if no indexer is available.
It is never written inside any repository being analyzed, so there is
nothing to `.gitignore`.

## `relate` reports `rel:status=unknown` even though I know these two repos depend on each other

Expected, not a bug, if the exact symbol name you passed doesn't literally
appear in both repositories' current working trees. `relate` only confirms
one specific named contract textually on both sides (a provider's
definition/reference and a consumer's reference to that same name) — it
doesn't trace imports, follow renamed/aliased symbols, or reason about the
dependency any other way. Check the exact spelling, and that you passed the
provider repo and the consumer repo in the right order (direction matters —
`relate` doesn't treat them as interchangeable). This is intentional: an
unsupported relationship is reported as unknown rather than invented.

## `relate-status` says `rel:overall=stale`

Expected, not a bug — one or both repositories have moved past the commit
the relationship was last recorded at (`relate` doesn't watch for new
commits on its own; there's no daemon). Re-run `relate` to recompute and
refresh the stored record with current evidence — the refreshed result can
flip `supported` to `unknown`, or vice versa, if the dependency was
actually added or removed since the last check.

## Where is the cross-repo relationship record, and is it safe to delete?

`~/.kiro/.um-agentic-engineering/repo-relations/<hash>/`, one subdirectory
per checked `(provider repo, symbol, consumer repo)` triple. Always safe to
delete — the next `relate` call just rebuilds it; `relate-status` on a
deleted record reports `rel:record=missing` rather than failing unclearly.
It is never written inside either repository being analyzed.

## Why doesn't `toolkit/agents/` install anything?

Kiro's docs explicitly confirm global discovery paths for skills
(`~/.kiro/skills/`) and steering (`~/.kiro/steering/`). There's no
equivalent documented global discovery path for custom agent definitions, so
`toolkit/agents/` is reserved but intentionally not wired in — adding that
would mean guessing at an unverified mechanism.
