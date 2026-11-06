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
`~/.kiro/.um-agentic-engineering/bin/agentic-eng`, but can't edit your shell
profile for you. Add the printed line (something like
`export PATH="$HOME/.kiro/.um-agentic-engineering/bin:$PATH"`) to
`~/.zshrc`/`~/.bashrc`, then open a new shell. Until then, run it via the
path directly, or from inside a clone as `./agentic-eng <command>`.

## `agentic-eng update` rejected a release

This means the resolved release failed validation (missing `VERSION`, a
skill's frontmatter `name:` not matching its folder, a missing/empty
`description:`, or malformed steering frontmatter) — your previous working
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
this variable.

## Why doesn't `toolkit/agents/` install anything?

Kiro's docs explicitly confirm global discovery paths for skills
(`~/.kiro/skills/`) and steering (`~/.kiro/steering/`). There's no
equivalent documented global discovery path for custom agent definitions, so
`toolkit/agents/` is reserved but intentionally not wired in — adding that
would mean guessing at an unverified mechanism.
