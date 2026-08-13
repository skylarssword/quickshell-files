#!/usr/bin/env bash
# setup-video-converter.sh
# Interactive installer for the tide-island video converter + systemd watcher.
# Run once after cloning the repo. Re-run at any time to change paths.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_DIR="$HOME/.config/tide-island"
CONF_FILE="$CONF_DIR/video-convert.conf"
SYSTEMD_DIR="$HOME/.config/systemd/user"
BIN_DIR="$HOME/.local/bin"
ISLAND_CONF="$REPO_DIR/qml/shared/IslandConfiguration.qml"

# ── Uninstall ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Uninstalling tide-video-convert..."
    systemctl --user disable --now tide-video-convert.path 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/tide-video-convert.path" \
          "$SYSTEMD_DIR/tide-video-convert.service" \
          "$BIN_DIR/tide-video-convert.sh"
    systemctl --user daemon-reload
    echo "Done. Config preserved at $CONF_FILE — remove manually if desired."
    exit 0
fi

# ── Dependency check ───────────────────────────────────────────────────────
if ! command -v ffmpeg &>/dev/null; then
    echo "Error: ffmpeg is required but not found in PATH." >&2
    exit 1
fi

# ── Prompt ────────────────────────────────────────────────────────────────
echo "tide-island video converter setup"
echo

# Show existing values as defaults if re-running
if [[ -f "$CONF_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
    echo "(Existing config found — press Enter to keep current values)"
    echo
fi

read -rp "Watch folder (drop videos here):  [${SRC:-}] " INPUT_SRC
read -rp "Output folder (converted videos): [${DST:-}] " INPUT_DST
read -rp "Archive folder (originals go here): [${ARCHIVE:-}] " INPUT_ARCHIVE

SRC="${INPUT_SRC:-${SRC:-}}"
DST="${INPUT_DST:-${DST:-}}"
ARCHIVE="${INPUT_ARCHIVE:-${ARCHIVE:-}}"

if [[ -z "$SRC" || -z "$DST" || -z "$ARCHIVE" ]]; then
    echo "Error: all three paths are required." >&2
    exit 1
fi

# Expand ~ manually
SRC="${SRC/#\~/$HOME}"
DST="${DST/#\~/$HOME}"
ARCHIVE="${ARCHIVE/#\~/$HOME}"

# Create dirs
mkdir -p "$SRC" "$DST" "$ARCHIVE" "$CONF_DIR" "$SYSTEMD_DIR" "$BIN_DIR"

# ── Write config ──────────────────────────────────────────────────────────
cat > "$CONF_FILE" <<EOF
SRC="$SRC"
DST="$DST"
ARCHIVE="$ARCHIVE"
EOF
echo "Config written to $CONF_FILE"

# ── Install script ────────────────────────────────────────────────────────
cp "$REPO_DIR/bin/tide-video-convert.sh" "$BIN_DIR/"
chmod +x "$BIN_DIR/tide-video-convert.sh"
echo "Script installed to $BIN_DIR/tide-video-convert.sh"

# ── Write systemd units ───────────────────────────────────────────────────
cat > "$SYSTEMD_DIR/tide-video-convert.path" <<EOF
[Unit]
Description=Watch for videos to convert for tide-island

[Path]
PathChanged=$SRC
DirectoryNotEmpty=$SRC

[Install]
WantedBy=default.target
EOF

cp "$REPO_DIR/systemd/tide-video-convert.service" "$SYSTEMD_DIR/"

systemctl --user daemon-reload
systemctl --user enable --now tide-video-convert.path
echo "Systemd watcher enabled for $SRC"

# ── Patch IslandConfiguration.qml with DST ────────────────────────────────
if [[ -f "$ISLAND_CONF" ]]; then
    # Escape DST for use in sed
    ESC_DST="$(printf '%s\n' "$DST" | sed 's/[[\.*^$()+?{|]/\\&/g')"
    sed -i "s|readonly property string videoFolder: \".*\"|readonly property string videoFolder: \"$ESC_DST\"|" "$ISLAND_CONF"
    echo "IslandConfiguration.qml videoFolder updated to: $DST"
else
    echo "Warning: could not find IslandConfiguration.qml at $ISLAND_CONF"
    echo "Manually set videoFolder to: $DST"
fi

echo
echo "All done! Videos dropped into $SRC will be converted to $DST."
