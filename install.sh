#!/usr/bin/env bash
# um-agentic-engineering Kiro toolkit installer.
#
# Installs the global toolkit content under toolkit/ into Kiro's documented
# global discovery paths:
#   ~/.kiro/skills/<name>/     (Kiro IDE only — see docs/SETUP.md)
#   ~/.kiro/steering/<file>.md (Kiro IDE and CLI)
#
# Usage:
#   ./install.sh              install the release currently checked out
#   ./install.sh --uninstall  remove everything this installer has installed
#   ./install.sh --help
#
# See docs/SETUP.md for prerequisites, platform support, and verification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="$SCRIPT_DIR/toolkit"
VERSION_FILE="$SCRIPT_DIR/VERSION"

# AGENTIC_TOOLKIT_HOME exists only so scripts/smoke-test.sh can exercise this
# installer against a throwaway directory instead of a real $HOME. Kiro
# itself always reads from the engineer's actual home directory, so this
# variable has no effect on what Kiro discovers — do not rely on it for a
# real install.
INSTALL_HOME="${AGENTIC_TOOLKIT_HOME:-$HOME}"
KIRO_DIR="$INSTALL_HOME/.kiro"
SKILLS_DIR="$KIRO_DIR/skills"
STEERING_DIR="$KIRO_DIR/steering"
STATE_DIR="$KIRO_DIR/.um-agentic-engineering"
MANIFEST="$STATE_DIR/install-manifest.txt"

info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

show_help() {
  cat <<'EOF'
um-agentic-engineering Kiro toolkit installer

Usage:
  ./install.sh              Install (or update) the checked-out release.
  ./install.sh --uninstall  Remove everything this installer has installed.
  ./install.sh --help       Show this help.

Installs from toolkit/ in this repository into:
  ~/.kiro/skills/
  ~/.kiro/steering/

Re-running this command is safe: it only ever touches files it previously
installed itself (tracked in the manifest below) and leaves everything else
in ~/.kiro/ alone.

Manifest/state: ~/.kiro/.um-agentic-engineering/install-manifest.txt
EOF
}

ACTION="install"
for arg in "$@"; do
  case "$arg" in
    --uninstall) ACTION="uninstall" ;;
    --help|-h) ACTION="help" ;;
    *) fail "Unknown argument: $arg (see --help)" ;;
  esac
done

if [ "$ACTION" = "help" ]; then
  show_help
  exit 0
fi

check_prereqs() {
  [ -f "$VERSION_FILE" ] || fail "VERSION file not found at $VERSION_FILE. This checkout looks incomplete — re-clone the repository and run ./install.sh from its root."

  [ -d "$TOOLKIT_DIR/skills" ] || fail "toolkit/skills not found next to install.sh ($TOOLKIT_DIR). The release source is incomplete or this script was copied out of the repository. Re-clone the repository and run ./install.sh from its root."

  if [ ! -d "$INSTALL_HOME" ]; then
    fail "Install target directory does not exist: $INSTALL_HOME"
  fi
  if [ ! -w "$INSTALL_HOME" ]; then
    fail "No write permission to $INSTALL_HOME. Fix permissions on your home directory and re-run."
  fi

  case "$(uname -s)" in
    Darwin|Linux) ;;
    *) warn "This installer has only been verified on macOS and Linux (see docs/SETUP.md). Continuing anyway on $(uname -s), but Kiro's discovery behavior there is unverified." ;;
  esac

  if [ "$(uname -s)" = "Darwin" ] && [ ! -d "/Applications/Kiro.app" ] && ! command -v kiro >/dev/null 2>&1; then
    warn "Kiro.app was not found in /Applications and no 'kiro' command is on PATH. The toolkit will still be installed to $KIRO_DIR — Kiro will pick it up once it is installed."
  fi
}

RELEASE_VERSION=""
RELEASE_COMMIT="unknown"
load_release_metadata() {
  RELEASE_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
  if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --short HEAD >/dev/null 2>&1; then
    RELEASE_COMMIT="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
  fi
}

# Lines of a manifest that aren't comments/blank are "<category>/<name>"
# relative paths this installer previously wrote under $KIRO_DIR.
read_manifest_entries() {
  if [ -f "$MANIFEST" ]; then
    grep -v '^[[:space:]]*#' "$MANIFEST" | grep -v '^[[:space:]]*$' || true
  fi
}

entry_in_list() {
  local needle="$1" entry
  while IFS= read -r entry; do
    [ "$entry" = "$needle" ] && return 0
  done <<<"$2"
  return 1
}

do_install() {
  check_prereqs
  load_release_metadata
  mkdir -p "$SKILLS_DIR" "$STEERING_DIR" "$STATE_DIR"

  local prev_entries
  prev_entries="$(read_manifest_entries)"
  local new_entries=""

  info "Installing um-agentic-engineering toolkit $RELEASE_VERSION ($RELEASE_COMMIT) into $KIRO_DIR"

  # --- skills: toolkit/skills/<name>/SKILL.md -> ~/.kiro/skills/<name>/ ---
  while IFS= read -r -d '' dir; do
    local name dest rel
    name="$(basename "$dir")"
    rel="skills/$name"
    if [ ! -f "$dir/SKILL.md" ]; then
      warn "Skipping $rel: no SKILL.md found."
      continue
    fi
    dest="$SKILLS_DIR/$name"
    if [ -e "$dest" ] && ! entry_in_list "$rel" "$prev_entries"; then
      warn "Skipping $rel: $dest already exists and was not installed by this toolkit. Remove it manually first if you want this sample skill installed under that name."
      continue
    fi
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -R "$dir/." "$dest/"
    new_entries="${new_entries}${rel}
"
    info "Installed skill: $name"
  done < <(find "$TOOLKIT_DIR/skills" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

  # --- steering: toolkit/steering/*.md -> ~/.kiro/steering/ ---
  while IFS= read -r -d '' file; do
    local base dest rel
    base="$(basename "$file")"
    rel="steering/$base"
    dest="$STEERING_DIR/$base"
    if [ -e "$dest" ] && ! entry_in_list "$rel" "$prev_entries"; then
      warn "Skipping $rel: $dest already exists and was not installed by this toolkit."
      continue
    fi
    cp "$file" "$dest"
    new_entries="${new_entries}${rel}
"
    info "Installed steering file: $base"
  done < <(find "$TOOLKIT_DIR/steering" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)

  # --- remove anything we installed previously that is no longer shipped ---
  if [ -n "$prev_entries" ]; then
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      if ! entry_in_list "$entry" "$new_entries"; then
        rm -rf "${KIRO_DIR:?}/${entry:?}"
        info "Removed stale artifact from a previous install: $entry"
      fi
    done <<<"$prev_entries"
  fi

  {
    printf '# um-agentic-engineering toolkit install manifest\n'
    printf '# version: %s\n' "$RELEASE_VERSION"
    printf '# commit: %s\n' "$RELEASE_COMMIT"
    printf '# installed_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# installed_from: %s\n' "$SCRIPT_DIR"
    printf '%s' "$new_entries"
  } > "$MANIFEST"

  local count
  count="$(printf '%s' "$new_entries" | grep -c . || true)"
  info "Done. $count artifact(s) installed. Manifest: $MANIFEST"
  info "Restart Kiro (or reload its window) to pick up new global skills/steering."
}

do_uninstall() {
  if [ ! -f "$MANIFEST" ]; then
    info "Nothing to uninstall: no manifest found at $MANIFEST."
    exit 0
  fi
  local entries
  entries="$(read_manifest_entries)"
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    rm -rf "${KIRO_DIR:?}/${entry:?}"
    info "Removed: $entry"
  done <<<"$entries"
  rm -rf "$STATE_DIR"
  info "Uninstall complete."
}

case "$ACTION" in
  install) do_install ;;
  uninstall) do_uninstall ;;
esac
