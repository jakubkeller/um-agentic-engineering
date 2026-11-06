# Troubleshooting

## `./install.sh` fails with "VERSION file not found" or "toolkit/skills not found"

The checkout is incomplete — usually because `install.sh` was copied out of
the repository on its own, or the clone was interrupted. Re-clone the
repository and run `./install.sh` from its root (not a copy of just the
script).

## `./install.sh` fails with "No write permission to $HOME"

Fix permissions on your home directory, or on whatever `AGENTIC_TOOLKIT_HOME`
points at if you set it manually (you normally shouldn't — see below).

## The warning about Kiro.app / `kiro` not being found

This is informational, not fatal. The installer still writes to
`~/.kiro/...`; Kiro will discover those files once it's installed, no
re-install needed. If you *have* Kiro installed and still see this warning,
it just means detection didn't recognize your install location — safe to
ignore.

## I ran `/repo-snapshot` in Kiro and nothing happened

1. Confirm the files exist: `ls ~/.kiro/skills/repo-snapshot/SKILL.md`.
   If missing, re-run `./install.sh` from the toolkit checkout.
2. Restart Kiro or reload its window — skills are loaded at startup, not
   watched live.
3. Global skills are an **IDE** feature. If you're using the Kiro CLI, global
   skills aren't read at all (only global steering is) — this is a Kiro
   platform limitation documented at kiro.dev/docs/skills, not a bug in this
   installer.
4. If you're using a Kiro **custom agent**, it doesn't load skills by
   default; it needs `skill://~/.kiro/skills/*/SKILL.md` added to its
   `resources` field.

## A skill/steering file I expected to be installed is missing

Check the installer's own output — it skips (with a `WARNING:` line, not a
failure) anything that already exists at the target path under a name the
toolkit didn't install itself, so it never clobbers a personal skill of
yours that happens to share a name. Rename or remove the conflicting
personal file, then re-run `./install.sh`.

## I want to go back to a specific older release

```sh
git -C um-agentic-engineering checkout <tag-or-commit>
cd um-agentic-engineering && ./install.sh
```

There is no separate release server or channel — the git history of this
repository *is* the release history, and the `VERSION` file at whatever
commit you have checked out is "the current approved release" from that
commit's point of view.

## `AGENTIC_TOOLKIT_HOME`

This environment variable exists only so `scripts/smoke-test.sh` can run the
installer against a disposable directory instead of your real home
directory. Don't set it for a real install — Kiro always reads from your
actual home directory regardless of this variable, so pointing the
installer elsewhere would only make the toolkit invisible to Kiro.

## Why doesn't `toolkit/agents/` install anything?

Kiro's docs explicitly confirm global discovery paths for skills
(`~/.kiro/skills/`) and steering (`~/.kiro/steering/`), which is why this
installer targets exactly those two. There is no equivalent documented
global discovery path for custom agent definitions, so `toolkit/agents/` is
reserved but intentionally not wired into the installer — adding that would
mean guessing at an unverified mechanism, which the PBI this toolkit was
built against explicitly calls out not to do.
