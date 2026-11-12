pragma Singleton
import QtQuick
import Quickshell.Io

// Central Liquid Glass switch + tuning for tide-island.
// Everything glass-related lives here: the on/off state (persisted to
// ~/.local/state/tide-island/liquid-glass) and every tuning number.
QtObject {
    id: glass

    // Off by default; loaded from the state file at startup.
    property bool enabled: false

    function setEnabled(on) {
        enabled = on
        stateWrite.running = false
        stateWrite.command = ["sh", "-c",
            'd="${XDG_STATE_HOME:-$HOME/.local/state}/tide-island"; mkdir -p "$d" && echo '
            + (on ? "on" : "off") + ' > "$d/liquid-glass"']
        stateWrite.running = true
    }

    // ── card knobs (used by GlassSheen) ─────────────────────────────────
    readonly property real tintAlpha:   0.10   // dark tint under the glass; keeps white text readable on bright wallpapers
    readonly property real edgeAlpha:   0.14   // dark hairline just outside the card
    readonly property real shadowAlpha: 0.07   // soft shadow falloff outside the edge
    readonly property real rimAlpha:    0.16   // bright inner rim
    readonly property real glowAlpha:   0.05   // soft light at the top of the card
    readonly property real glintAlpha:  0.55   // peak of the specular line along the top edge

    // ── island body knobs (used by DynamicIslandWindow's capsule) ───────
    readonly property real bodyScale:       0.5    // multiplies the body's black alpha: 0.5 turns the 20% chip into 10%
    readonly property real bodyEdgeAlpha:   0.16
    readonly property real bodyShadowAlpha: 0.08
    readonly property real bodyRimAlpha:    0.18
    readonly property real bodyGlowAlpha:   0.06
    readonly property real bodyGlintAlpha:  0.55

    property Process _read: Process {
        running: true
        command: ["sh", "-c", 'cat "${XDG_STATE_HOME:-$HOME/.local/state}/tide-island/liquid-glass" 2>/dev/null']
        stdout: SplitParser {
            onRead: (data) => glass.enabled = (data.trim() === "on")
        }
    }

    property Process _write: Process { id: stateWrite }
}
