#!/usr/bin/env bash
# Day-zero bootstrap entry point. agentic-eng itself can't be on PATH before
# it's ever been run once, so this is what a fresh clone's README/SETUP.md
# tells engineers to run first. It just delegates to the real implementation.
#
#   git clone git@github.com:jakubkeller/um-agentic-engineering.git
#   cd um-agentic-engineering
#   ./install.sh
#
# After this, agentic-eng is installed to ~/.kiro/.um-agentic-engineering/bin/
# and update/version/rollback are available (see docs/SETUP.md for the PATH
# step). Re-running this later is equivalent to `agentic-eng update`.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/agentic-eng" install
