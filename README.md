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

See [docs/SETUP.md](docs/SETUP.md) for prerequisites, verification, updates,
and uninstall, and [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for
common failure recovery.

## Layout

- `toolkit/` — the global, installable content (skills, steering, reserved
  agents). See [toolkit/README.md](toolkit/README.md).
- `install.sh` — the installer.
- `scripts/smoke-test.sh` — repeatable, automated install verification.
- `docs/` — setup, troubleshooting, and the PBI this toolkit was built from.

## Why

Kiro's documented global discovery paths (`~/.kiro/skills/`,
`~/.kiro/steering/`) make a shared toolkit possible without any Kiro-side
install feature beyond "files in the right place." This repo is that place,
versioned and installed with one idempotent command.
