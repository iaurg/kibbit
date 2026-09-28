#!/bin/bash
# Kibbit installer.
#
#   curl -fsSL https://raw.githubusercontent.com/iaurg/kibbit/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/iaurg/kibbit/main/install.sh | bash -s -- --uninstall
#
# Downloads the latest release, checks its SHA-256, installs Kibbit.app into /Applications
# (or ~/Applications when /Applications isn't writable) and launches it.
#
# Kibbit isn't notarized. Files fetched with curl don't get the quarantine flag that browsers
# add, so Gatekeeper doesn't block the app installed this way.
#
# Environment overrides:
#   KIBBIT_VERSION   release tag to install, e.g. v0.2.0 (default: latest)
#   KIBBIT_DIR       install directory (default: /Applications or ~/Applications)
#   KIBBIT_BASE_URL  where Kibbit.zip and Kibbit.zip.sha256 live (used by CI tests)
#   KIBBIT_NO_OPEN   set to 1 to skip launching after install
set -euo pipefail

REPO="iaurg/kibbit"
APP="Kibbit.app"
BUNDLE_ID="dev.kibbit.Kibbit"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

install_dir() {
    if [[ -n "${KIBBIT_DIR:-}" ]]; then
        echo "$KIBBIT_DIR"
    elif [[ -w /Applications ]]; then
        echo /Applications
    else
        echo "$HOME/Applications"
    fi
}

quit_running() {
    if pgrep -x Kibbit >/dev/null 2>&1; then
        info "Quitting the running Kibbit…"
        osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || pkill -x Kibbit || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Kibbit >/dev/null 2>&1 || break; sleep 0.3; done
    fi
}

uninstall() {
    bold "Uninstalling Kibbit"
    quit_running
    for dir in "${KIBBIT_DIR:-}" /Applications "$HOME/Applications"; do
        [[ -n "$dir" && -d "$dir/$APP" ]] && { rm -rf "${dir:?}/$APP"; info "Removed $dir/$APP"; }
    done
    rm -rf "$HOME/Library/Application Support/Kibbit"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    security delete-generic-password -s Kibbit >/dev/null 2>&1 || true
    info "Removed settings and the saved token."
    info "If you enabled launch at login, also remove Kibbit under System Settings → General → Login Items."
    bold "Bye! 👋"
}

install() {
    [[ "$(uname -s)" == "Darwin" ]] || fail "Kibbit is a macOS app."
    local major
    major="$(sw_vers -productVersion | cut -d. -f1)"
    (( major >= 14 )) || fail "Kibbit needs macOS 14 (Sonoma) or newer; this Mac runs $(sw_vers -productVersion)."

    local base="${KIBBIT_BASE_URL:-}"
    if [[ -z "$base" ]]; then
        if [[ -n "${KIBBIT_VERSION:-}" ]]; then
            base="https://github.com/$REPO/releases/download/$KIBBIT_VERSION"
        else
            base="https://github.com/$REPO/releases/latest/download"
        fi
    fi

    local dest
    # Global, not local: the EXIT trap runs after this function has returned.
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    dest="$(install_dir)"

    bold "Installing Kibbit ${KIBBIT_VERSION:-(latest)}"
    info "Downloading…"
    curl -fsSL "$base/Kibbit.zip" -o "$tmp/Kibbit.zip" || fail "Download failed from $base/Kibbit.zip"
    curl -fsSL "$base/Kibbit.zip.sha256" -o "$tmp/Kibbit.zip.sha256" || fail "Checksum download failed."

    local expected actual
    expected="$(awk '{print $1}' "$tmp/Kibbit.zip.sha256")"
    actual="$(shasum -a 256 "$tmp/Kibbit.zip" | awk '{print $1}')"
    [[ -n "$expected" && "$expected" == "$actual" ]] || fail "Checksum mismatch; the download may be corrupted. Try again."
    info "Checksum OK."

    ditto -x -k "$tmp/Kibbit.zip" "$tmp/unpacked"
    [[ -d "$tmp/unpacked/$APP" ]] || fail "The download didn't contain $APP."

    quit_running
    mkdir -p "$dest"
    rm -rf "${dest:?}/$APP"
    ditto "$tmp/unpacked/$APP" "$dest/$APP"
    xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true
    info "Installed to $dest/$APP"

    if ! command -v claude >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/claude" ]]; then
        info "Kibbit answers through Claude Code, which isn't installed yet. Setup will walk you through it."
    fi

    if [[ "${KIBBIT_NO_OPEN:-0}" != "1" ]]; then
        open "$dest/$APP"
        bold "Kibbit is hatching in your menu bar 🥚"
    else
        bold "Done."
    fi
}

case "${1:-}" in
    --uninstall) uninstall ;;
    "") install ;;
    *) fail "Unknown option: $1 (use --uninstall to remove Kibbit)" ;;
esac
