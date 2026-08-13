pragma Singleton
import QtQuick

// ── tide-island user configuration ──────────────────────────────────────────
// Edit this file once after installing. Everything else in the shell reads
// from these properties — no other file should contain hardcoded paths.
//
// Paths support ~ expansion via the shell; use absolute paths or $HOME-style
// strings handled by your scripts. QML reads these as plain strings passed
// to Process commands, so ~ works fine there.

QtObject {

    // ── Wallpaper ────────────────────────────────────────────────────────
    // Where your wallpaper images live (used by WallpaperHub + picker).
    // Default assumes ml4w dotfiles. Change to wherever you keep wallpapers,
    // e.g. "/home/yourname/Pictures/wallpapers"
    readonly property string wallpaperFolder: "/home/userone/.config/ml4w/wallpapers"

    // Thumbnail cache directory. tide-island generates and reads its own
    // thumbnails here — no waypaper required.
    readonly property string thumbCacheDir: "/home/userone/.cache/tide-island/thumbs"

    // Script called after setting a wallpaper. Ships as wal-video-fix in
    // the base tide-island install. Change if you use a different hook.
    readonly property string postCommand: "/home/userone/.local/bin/wal-video-fix"

    // ── Video conversion ─────────────────────────────────────────────────
    // Output folder for converted videos shown in WallpaperHub.
    // Set by setup-video-converter.sh — re-run that script instead of
    // editing this manually.
    readonly property string videoFolder: "/home/userone/.config/ml4w/wallpapers/1080p-Wallpapers/"

    // ── Pywal ────────────────────────────────────────────────────────────
    // Where wal writes colors.sh after a theme change. This is the default
    // pywal path — only change if you've overridden wal's cache dir.
    readonly property string walColorsFile: "/home/userone/.cache/wal/colors.sh"

    // ── Cache ────────────────────────────────────────────────────────────
    // JSON cache written by the wallpaper picker for per-wallpaper accent colors.
    // The directory is created automatically — no manual setup needed.
    readonly property string colorCacheFile: "/home/userone/.cache/quickshell/wallpaper-colors.json"

    // ── Fonts ────────────────────────────────────────────────────────────
    // Relative to the repo root — these ship with tide-island in fonts/
    // You do not need to edit these unless you swap out the font.
    readonly property string fontRegular: Qt.resolvedUrl("../../fonts/FlexRounded-R.ttf")
    readonly property string fontMedium:  Qt.resolvedUrl("../../fonts/FlexRounded-M.ttf")
    readonly property string fontBold:    Qt.resolvedUrl("../../fonts/FlexRounded-B.ttf")

    // ── Notification Sound ───────────────────────────────────────────────
    // Play a sound when a notification arrives (only fires when DND is off,
    // mirroring the bell-wobble behaviour).
    // Set to false to silence notification sounds entirely.
    readonly property bool notificationSoundEnabled: true

    // Playback volume from 0 (silent) to 100 (full volume).
    readonly property int notificationSoundVolume: 90
}
