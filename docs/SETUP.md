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

- macOS, Linux, or **Windows via WSL** — each with `bash` and `git` (both
  ship by default on macOS, most Linux distros, and any WSL distro; this
  tool is written to be compatible with bash 3.2, macOS's default).
- A writable home directory and network access the first time you install
  or update (to fetch release tags). `rollback` never needs network.
- [Kiro](https://kiro.dev) installed to actually use the toolkit — but the
  tool does not hard-require it. If Kiro isn't detected it installs anyway
  and warns, since Kiro will discover the files once it's installed.
- **Optional:** [Universal Ctags](https://ctags.io) (`brew install
  universal-ctags` on macOS, `apt-get install universal-ctags` on
  Linux/WSL) lets the `repository-context` skill return verified symbol
  definitions. Without it, that skill automatically falls back to a direct
  text search — no hard requirement, and nothing else in the toolkit needs
  it. Note: stock macOS ships an unrelated BSD `ctags` under the same
  name; the skill only uses the real Universal Ctags when it's actually
  installed.

**Native Windows (PowerShell/cmd, no WSL) is not supported.** `agentic-eng`
is a bash script and the auto-PATH step writes to `~/.zshrc`/`~/.bashrc` —
inside WSL that's the right place (it's just Linux), but there's no
PowerShell/cmd equivalent today. If you're on Windows, install and run
everything from inside a WSL terminal, not Git Bash (unverified) and not a
native PowerShell/cmd prompt.

> **Unverified on WSL specifically:** this installs into *that shell's*
> `~/.kiro/` — i.e. WSL's Linux home directory. If Kiro itself runs as a
> native Windows app rather than inside WSL (e.g. via a WSL/Remote
> extension), it may read a *different* `~/.kiro/` (the Windows one) than
> the one this installs into, and the skill/steering files would silently
> never be seen by Kiro. Nobody has confirmed which case applies yet on a
> real WSL VDI — check this once before relying on it, the same way the
> real-tag end-to-end flow still needs a first manual check.

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
4. adds that directory to your `PATH` itself, appending one marked,
   idempotent line to `~/.zshrc`/`~/.bashrc` (whichever matches `$SHELL`) if
   it isn't on `PATH` already.

Restart Kiro, or reload its window, afterward so it picks up the new global
skill — that one's on Kiro, there's no API to do it for you. Open a new
shell (or `source` the rc file it printed) and `agentic-eng
update|version|rollback` work as bare commands from any directory — no
manual editing required.

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
./scripts/repo-context-smoke-test.sh
```

The first confirms: install, idempotent re-install, version reporting (both
reachable and simulated-offline), a normal update, a *rejected* update
(invalid release, prior install stays usable), rollback (including fully
offline), uninstall, the `install.sh` bootstrap path, and a clean failure
when the release source is unreachable.

The second exercises `repository-context`'s `repo-context.sh` directly
(no install needed): correct file:line evidence on a fresh index, an
uncommitted/staged edit visible without a reindex, revision drift flagged
without an unnecessary rebuild, a missing or corrupted cache recovering via
a bounded rebuild, a forced direct-source fallback clearly labeled as such,
the file-count and timeout bounds on rebuilding, and a clean failure outside
a git repository. It passes meaningfully whether or not Universal Ctags is
actually installed on the machine running it, since it branches on which
indexer `repo-context.sh` itself reports using. It also exercises the
cross-repository `relate`/`relate-status` commands: a real provider/consumer
dependency found with evidence on both sides, an unsupported relationship
reported as unknown rather than invented, a missing relationship record
reported as such, and the stored record going stale — then being correctly
updated — once the consumer repo removes the call site.

What neither script *can* confirm is that Kiro itself actually discovers and
runs a skill, that the real tag-based resolution works against the real
GitHub remote, or that `repo-context.sh`'s Universal Ctags invocation (`ctags
-x -L -`) behaves exactly as expected against a real Universal Ctags binary
rather than a hand-crafted fixture — all three require things this repo's
own dev environment doesn't have (the real IDE/remote, or Universal Ctags
installed). Once a real tag exists, do this once, manually:

1. From a fresh clone, run `./install.sh`. Confirm `agentic-eng` lands on
   your PATH per the printed instructions.
2. Open two unrelated repositories in Kiro (not this one). In each, type
   `/repo-snapshot` in the chat and confirm it reports that repository's own
   branch/status/commits — proving one global install serves both, with no
   `.kiro/skills/` committed into either repo.
3. In one of those repositories, ask a symbol question that
   `/repository-context` would answer (e.g. "where is `<some function>`
   defined"). Confirm it returns correct file:line evidence plus the
   repository's revision and dirty/stale/fallback flags. If Universal Ctags
   is installed, confirm at least one result is labeled
   `confidence=confirmed`; otherwise confirm it clearly reports
   `direct-source-fallback` rather than silently returning only inferred
   results.
4. Publish a second tag, run `agentic-eng update`, confirm it activates, then
   `agentic-eng rollback` and confirm it reverts.
5. With two unrelated real repositories where one actually calls a function
   defined in the other, ask Kiro what consumes that function (naming both
   repos). Confirm it reports `rel:status=supported` with file:line evidence
   from both repositories. Ask the same question for a symbol that isn't
   really shared between them and confirm it reports `rel:status=unknown`
   rather than guessing a relationship.

## Uninstall

```sh
agentic-eng uninstall
```

Removes exactly what was recorded in
`~/.kiro/.um-agentic-engineering/install-manifest.txt`, the generated
version-status steering file, and the tool's entire state directory
(`~/.kiro/.um-agentic-engineering/`, including the self-installed `bin/`
copy) — nothing else in `~/.kiro/` is touched.
