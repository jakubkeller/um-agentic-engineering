# um-agentic-engineering

A shared [Kiro](https://kiro.dev) toolkit: skills and steering that install
once per workstation and are then available from every repository, without
copying anything into those repositories.

## Install

```sh
git clone git@github.com:jakubkeller/um-agentic-engineering.git
cd um-agentic-engineering
./install.sh
```

Day-to-day, once set up: `agentic-eng install|update|version|rollback|uninstall`.
See [docs/SETUP.md](docs/SETUP.md) for prerequisites, verification, and
uninstall, and [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
for common failure recovery.

## Layout

- `toolkit/` — the global, installable content (skills, steering, reserved
  agents). See [toolkit/README.md](toolkit/README.md).
- `agentic-eng` — the CLI: install/update/version/rollback/uninstall.
- `install.sh` — day-zero bootstrap wrapper (`agentic-eng` can't be on PATH
  before it's ever been run once); just calls `agentic-eng install`.
- `scripts/smoke-test.sh` — repeatable, automated, fully-offline verification.
- `docs/` — setup, troubleshooting, and the PBIs this toolkit was built from.

## Why

Kiro's documented global discovery paths (`~/.kiro/skills/`,
`~/.kiro/steering/`) make a shared toolkit possible without any Kiro-side
install feature beyond "files in the right place." This repo is that place,
versioned and installed with one idempotent command.
