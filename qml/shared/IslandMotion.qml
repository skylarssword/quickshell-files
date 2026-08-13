pragma Singleton
import QtQuick

// Central motion token system for tide-island.
// Every duration/easing in the shell should derive from these tokens
// rather than hardcoding raw numbers. Tune `standard` here to rescale
// the whole shell's feel at once.
QtObject {
    // ---- duration scale ----------------------------------------------
    // Bumped up from the first pass: the initial values (120/200/320/440/600)
    // read as too snappy/rushed once seen live. These sit closer to mugen's
    // actual feel while keeping the OutExpo/spring easings for polish.
    readonly property int micro:    360   // hover tints, icon swaps
    readonly property int fast:     420   // button press, small reveals
    readonly property int standard: 500   // capsule morph
    readonly property int gentle:   650   // content cross-fades
    readonly property int slow:     760   // panel slides, large reshapes

    // ---- easing vocabulary ---------------------------------------------
    readonly property int easeOut:     Easing.OutCubic
    readonly property int easeMove:    Easing.InOutCubic
    readonly property int easeOrganic: Easing.InOutSine
    readonly property int easeArrive:  Easing.OutExpo
    readonly property int easeSpring:  Easing.OutBack

    // ---- content-layer transition timing ------------------------------
    // Used by every layer that fades content inside the capsule
    // (notifications, expanded player, info panel, control center, etc).
    // The delay lets the capsule start reshaping before content appears,
    // which is what removes the "refresh/blink" feel on state switches.
    readonly property int contentExitDuration:  micro   // content leaves fast
    readonly property int contentEnterDelay:    110     // wait before fading in
    readonly property int contentEnterDuration: fast    // content arrives clean

    // ---- text colors (all-white hierarchy) -----------------------------
    // Raised further from the first pass -- primary is now effectively
    // opaque white, and even the faintest tier stays well above 0.75 so
    // nothing disappears against dark or busy wallpapers.
    readonly property color textPrimary:   Qt.rgba(0.98, 0.98, 1.00, 0.98)
    readonly property color textSecondary: Qt.rgba(0.90, 0.90, 0.95, 0.94)
    readonly property color textFaint:     Qt.rgba(0.82, 0.82, 0.90, 0.88)

    // ---- surface border (thin hairline, mugen-style) -------------------
    readonly property color surfaceBorderColor: Qt.rgba(0.35, 0.35, 0.40, 0.40)
    readonly property int surfaceBorderWidth: 1
}
