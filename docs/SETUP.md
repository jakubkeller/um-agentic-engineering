# Setup

## What this installs

A shared [Kiro](https://kiro.dev) toolkit, installed once per workstation
into Kiro's own global discovery paths, so it's available from every
repository without being copied into any of them:

| Content           | Installed to          | Kiro surfaces that see it |
|--------------------|------------------------|----------------------------|
| Skills (`toolkit/skills/`) | `~/.kiro/skills/<name>/` | **IDE only** |
| Steering (`toolkit/steering/`) | `~/.kiro/steering/<file>.md` | IDE and CLI |

These paths and the IDE/CLI split come from Kiro's own documentation
(kiro.dev/docs/skills, kiro.dev/docs/steering) — they are not something this
tool invents. There is no documented Kiro CLI command or install API for
*global* skills; Kiro's own IDE "Import a skill" feature works by copying
files into `~/.kiro/skills/`, and that's exactly what `agentic-eng` does
too, just without requiring the IDE.

## Prerequisites

- macOS or Linux with `bash` and `git` (both ship by default on macOS and
  most Linux distros; this tool is written to be compatible with bash 3.2,
  macOS's default).
- A writable home directory and network access the first time you install
  or update (to fetch release tags). `rollback` never needs network.
- [Kiro](https://kiro.dev) installed to actually use the toolkit — but the
  tool does not hard-require it. If Kiro isn't detected it installs anyway
  and warns, since Kiro will discover the files once it's installed.

Windows is not supported or verified. If you need it, open an issue rather
than assuming this works under WSL/Git Bash.

## Install (day zero)

`agentic-eng` can't be on your PATH before you've ever run it once, so the
very first install always starts from a clone:

```sh
git clone git@github.com:jakubkeller/um-agentic-engineering.git
cd um-agentic-engineering
./install.sh
```

`install.sh` is a thin bootstrap wrapper — it just runs `./agentic-eng
install`. That one run:

1. resolves the **latest approved release** (the highest `vX.Y.Z` git tag on
   this repo — not whatever commit happens to be checked out),
2. installs it into `~/.kiro/skills/` and `~/.kiro/steering/`,
3. copies `agentic-eng` itself to `~/.kiro/.um-agentic-engineering/bin/`, so
   it keeps working even if you delete this clone,
4. prints a one-time instruction to add that directory to your `PATH` if
   it isn't already (we never edit your shell profile for you).

Restart Kiro, or reload its window, afterward so it picks up the new global
skill. After adding the printed line to your shell profile and opening a new
shell, `agentic-eng update|version|rollback` work as bare commands from any
directory.

> **Known gap today:** this repo has no `vX.Y.Z` tags yet. Until a
> maintainer creates and pushes the first one (`git tag -a v1.0.0 <commit>
> && git push origin v1.0.0`), `agentic-eng install`/`update` will correctly
> fail with "no approved release tags found yet" rather than silently
> installing an arbitrary branch. This is intentional — see
> `docs/TROUBLESHOOTING.md`.

## Day-to-day commands

```sh
agentic-eng install     # first-time setup (see above)
agentic-eng update      # explicitly check for and activate a newer release
agentic-eng version     # show installed version, and latest available if reachable
agentic-eng rollback    # restore the previously installed release (works offline)
agentic-eng uninstall   # remove everything agentic-eng has installed
```

Nothing here runs automatically — no background checks, no cron, no Kiro
hook. You decide when to run `update`, and every engineer can be on a
different installed version with no coordination required.

## Verify

Run the automated smoke test. It's fully offline (builds its own throwaway
git fixtures instead of touching the real GitHub remote) and never touches
your real `~/.kiro`:

```sh
./scripts/smoke-test.sh
```

This confirms: install, idempotent re-install, version reporting (both
reachable and simulated-offline), a normal update, a *rejected* update
(invalid release, prior install stays usable), rollback (including fully
offline), uninstall, the `install.sh` bootstrap path, and a clean failure
when the release source is unreachable.

What it *cannot* confirm is that Kiro itself actually discovers and runs the
skill, or that the real tag-based resolution works against the real GitHub
remote — both require the real IDE/remote. Once a real tag exists, do this
once, manually:

1. From a fresh clone, run `./install.sh`. Confirm `agentic-eng` lands on
   your PATH per the printed instructions.
2. Open two unrelated repositories in Kiro (not this one). In each, type
   `/repo-snapshot` in the chat and confirm it reports that repository's own
   branch/status/commits — proving one global install serves both, with no
   `.kiro/skills/` committed into either repo.
3. Publish a second tag, run `agentic-eng update`, confirm it activates, then
   `agentic-eng rollback` and confirm it reverts.

## Uninstall

```sh
agentic-eng uninstall
```

Removes exactly what was recorded in
`~/.kiro/.um-agentic-engineering/install-manifest.txt`, the generated
version-status steering file, and the tool's entire state directory
(`~/.kiro/.um-agentic-engineering/`, including the self-installed `bin/`
copy) — nothing else in `~/.kiro/` is touched.
