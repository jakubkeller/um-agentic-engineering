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
installer invents. There is no documented Kiro CLI command or install API
for *global* skills; Kiro's own IDE "Import a skill" feature works by
copying files into `~/.kiro/skills/`, and that's exactly what `install.sh`
does too, just without requiring the IDE.

## Prerequisites

- macOS or Linux with `bash` (ships by default on both; this installer is
  written to be compatible with bash 3.2, macOS's default).
- A writable home directory.
- [Kiro](https://kiro.dev) installed to actually use the toolkit — but the
  installer does not hard-require it. If Kiro isn't detected it installs
  anyway and warns, since Kiro will discover the files once it's installed.
- `git` is optional. It's only used to record the installed commit hash in
  the manifest for troubleshooting; its absence doesn't block install.

Windows is not supported or verified by this installer. If you need it, open
an issue rather than assuming the script works under WSL/Git Bash.

## Install

```sh
git clone git@github.com:jakubkeller/um-agentic-engineering.git
cd um-agentic-engineering
./install.sh
```

This installs whatever release is currently checked out (the `VERSION` file
at the repo root is the source of truth for the approved release). To get a
later release, `git pull` (or check out a different tag) and run
`./install.sh` again — it's safe to re-run any time.

Restart Kiro, or reload its window, afterward so it picks up the new global
skill.

## Verify

Run the automated smoke test. It never touches your real `~/.kiro` — it
exercises the installer against throwaway temp directories:

```sh
./scripts/smoke-test.sh
```

This confirms: a fresh install lands the sample skill at the documented
path, a second install doesn't duplicate anything, an unrelated personal
skill with a different name is left alone, uninstall removes exactly what
was installed, and a broken/incomplete checkout fails loudly instead of
pretending to succeed.

What it *cannot* confirm is that Kiro itself actually discovers and runs the
skill — that requires the real IDE. Do this once, manually, after install:

1. Open two unrelated repositories in Kiro (not this one, and not copies of
   each other).
2. In each, type `/repo-snapshot` in the chat.
3. Confirm it runs and reports that repository's own branch/status/commits
   — proving the same globally-installed skill works from both, with no
   `.kiro/skills/` committed into either repo.

## Upgrade and rollback

There is no separate release server or channel: this git repository's
history *is* the release history, and each approved release is a tagged
commit with its own `VERSION` file. Upgrading and rolling back are the same
operation in both directions — check out the release you want, then
re-run the installer:

```sh
# upgrade to the latest approved release
git -C um-agentic-engineering pull
cd um-agentic-engineering && ./install.sh

# roll back to a previous release
git -C um-agentic-engineering checkout v1.0.0
cd um-agentic-engineering && ./install.sh
```

`install.sh` is idempotent and direction-agnostic: it diffs what's currently
installed (per the manifest) against what the checked-out release ships,
refreshes anything shared between the two, and removes anything the old
install had that the newly-checked-out release doesn't — whether that's
moving forward or backward. Your own personal skills/steering (anything it
didn't install itself) are never touched either way.

## Uninstall

```sh
./install.sh --uninstall
```

Removes exactly the files recorded in
`~/.kiro/.um-agentic-engineering/install-manifest.txt`, then removes that
manifest directory too.
