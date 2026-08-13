import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell.Services.Mpris
import IslandBackend
import "../shared"

// EqualizerPanel — fully self-contained EQ view with two pages:
//   Page 1 (default): original equalizer with Flat/Bass/Treble/... presets
//   Page 2 (custom):  10 numbered slots, tap to load/select, edit sliders,
//                      Save writes current sliders into the selected slot,
//                      Reset clears the selected slot back to flat.
// Tapping the album art swaps between the two pages.
//
// DECOUPLING NOTE: this component polls its own MPRIS state and runs its own
// equalizer.sh process calls. It does NOT read from ExpandedPlayerLayer,
// IslandMprisController, or LyricManager. If this file breaks, nothing else
// in the shell is affected.

Item {
    id: root

    property bool showCondition: false
    property string iconFontFamily: ""
    property string textFontFamily: ""
    // Set true when embedded in SidebarMusicPopup — disables the album art
    // page toggle (no art visible there) and adjusts top margin to clear
    // the ‹ back button that floats above the panel.
    property bool sidebarMode: false

    // ── Page state ───────────────────────────────────────────────────────────
    property bool customPageActive: false

    // ── Independent MPRIS polling (own copy, not shared with anything) ──────
    property var _playersList: Mpris.players.values !== undefined ? Mpris.players.values : Mpris.players
    property var _activePlayer: {
        if (!_playersList || _playersList.length === 0) return null
        for (let i = 0; i < _playersList.length; i++) {
            if (_playersList[i].playbackState === MprisPlaybackState.Playing)
                return _playersList[i]
        }
        return _playersList.length > 0 ? _playersList[0] : null
    }
    readonly property string _artUrl: _activePlayer ? (_activePlayer.trackArtUrl || _activePlayer.artUrl || "") : ""

    readonly property string scriptPath: _scriptPath()
    function _scriptPath() {
        const override = Quickshell.env("EQUALIZER_SH_PATH")
        if (override && override !== "") return override
        return "/usr/share/tide-island/qml/island/equalizer.sh"
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAGE 1 STATE — original equalizer (unchanged behavior)
    // ═══════════════════════════════════════════════════════════════════════
    property var bandValues: [0,0,0,0,0,0,0,0,0,0]
    property string currentPreset: "Flat"
    property bool pendingChanges: false
    property bool loaded: false
    readonly property var presetNames: ["Flat","Bass","Treble","Vocal","Pop","Rock","Jazz","Classic"]

    function refresh() {
        getProc.command = ["bash", scriptPath, "get"]
        getProc.running = true
    }

    function setBand(index1to10, value) {
        const arr = bandValues.slice()
        arr[index1to10 - 1] = value
        bandValues = arr
        currentPreset = "Custom"
        pendingChanges = true

        setBandProc.command = ["bash", scriptPath, "set_band", String(index1to10), String(Math.round(value))]
        setBandProc.running = true
    }

    function applyChanges() {
        pendingChanges = false
        applyProc.command = ["bash", scriptPath, "apply"]
        applyProc.running = true
    }

    function applyPreset(name) {
        const presetGains = {
            "Flat":    [0,0,0,0,0,0,0,0,0,0],
            "Bass":    [5,7,5,2,1,0,0,0,1,2],
            "Treble":  [-2,-1,0,1,2,3,4,5,6,6],
            "Vocal":   [-2,-1,1,3,5,5,4,2,1,0],
            "Pop":     [2,4,2,0,1,2,4,2,1,2],
            "Rock":    [5,4,2,-1,-2,-1,2,4,5,6],
            "Jazz":    [3,3,1,1,1,1,2,1,2,3],
            "Classic": [0,1,2,2,2,2,1,2,3,4]
        }
        if (!presetGains[name]) return
        bandValues = presetGains[name].slice()
        currentPreset = name
        pendingChanges = false

        presetProc.command = ["bash", scriptPath, "preset", name]
        presetProc.running = true
    }

    onShowConditionChanged: {
        if (showCondition && !loaded) refresh()
    }

    Process {
        id: getProc
        stdout: StdioCollector { id: getOut }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) return
            try {
                const data = JSON.parse(getOut.text)
                root.bandValues = [
                    Number(data.b1)||0, Number(data.b2)||0, Number(data.b3)||0,
                    Number(data.b4)||0, Number(data.b5)||0, Number(data.b6)||0,
                    Number(data.b7)||0, Number(data.b8)||0, Number(data.b9)||0,
                    Number(data.b10)||0
                ]
                root.currentPreset = data.preset || "Flat"
                root.pendingChanges = !!data.pending
                root.loaded = true
            } catch(e) {
                // Leave defaults in place; this panel degrades gracefully on its own.
            }
        }
    }

    Process { id: setBandProc }
    Process { id: applyProc }
    Process { id: presetProc }

    // ═══════════════════════════════════════════════════════════════════════
    // PAGE 2 STATE — custom numbered slots
    // ═══════════════════════════════════════════════════════════════════════
    property var customBandValues: [0,0,0,0,0,0,0,0,0,0]
    property int selectedSlot: 1
    property var customSlotsFilled: ({})   // { "1": true, "3": true, ... }
    property bool customSlotDirty: false   // true once sliders edited since last load/save

    function refreshCustomSlotsList() {
        getCustomSlotsProc.command = ["bash", scriptPath, "get_custom_slots"]
        getCustomSlotsProc.running = true
    }

function selectSlot(slot) {
        selectedSlot = slot
        customSlotDirty = false
        getCustomSlotProc.command = ["bash", scriptPath, "get_custom_slot", String(slot)]
        getCustomSlotProc.running = true

        // Selecting a slot also applies it live immediately.
        loadCustomLiveProc.command = ["bash", scriptPath, "load_custom", String(slot)]
        loadCustomLiveProc.running = true
    }

    Process { id: loadCustomLiveProc }

    function setCustomBand(index1to10, value) {
        const arr = customBandValues.slice()
        arr[index1to10 - 1] = value
        customBandValues = arr
        customSlotDirty = true
    }

    function saveSelectedSlot() {
        const args = ["bash", scriptPath, "save_custom", String(selectedSlot)]
        for (let i = 0; i < 10; i++)
            args.push(String(Math.round(customBandValues[i])))
        saveCustomProc.command = args
        saveCustomProc.running = true
    }

    function resetSelectedSlot() {
        customBandValues = [0,0,0,0,0,0,0,0,0,0]
        customSlotDirty = true
    }

    Process {
        id: getCustomSlotsProc
        stdout: StdioCollector { id: getCustomSlotsOut }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) return
            try {
                root.customSlotsFilled = JSON.parse(getCustomSlotsOut.text)
            } catch(e) {
                root.customSlotsFilled = {}
            }
        }
    }

    Process {
        id: getCustomSlotProc
        stdout: StdioCollector { id: getCustomSlotOut }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) return
            try {
                const data = JSON.parse(getCustomSlotOut.text)
                root.customBandValues = [
                    Number(data.b1)||0, Number(data.b2)||0, Number(data.b3)||0,
                    Number(data.b4)||0, Number(data.b5)||0, Number(data.b6)||0,
                    Number(data.b7)||0, Number(data.b8)||0, Number(data.b9)||0,
                    Number(data.b10)||0
                ]
                root.customSlotDirty = false
            } catch(e) {
                root.customBandValues = [0,0,0,0,0,0,0,0,0,0]
            }
        }
    }

    Process {
        id: saveCustomProc
        onExited: (exitCode, exitStatus) => {
            root.customSlotDirty = false
            root.refreshCustomSlotsList()
        }
    }

    function _onCustomPageOpened() {
        refreshCustomSlotsList()
        selectSlot(selectedSlot)
    }

    onCustomPageActiveChanged: {
        if (customPageActive) _onCustomPageOpened()
    }

    // ── UI ───────────────────────────────────────────────────────────────────
    anchors.fill: parent
    anchors.topMargin:    sidebarMode ? 48 : 20
    anchors.leftMargin:   sidebarMode ? 8  : 20
    anchors.rightMargin:  sidebarMode ? 8  : 20
    anchors.bottomMargin: sidebarMode ? 8  : 20
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        NumberAnimation { duration: showCondition ? 280 : 120; easing.type: Easing.InOutQuad }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAGE 1 — original equalizer (Flat / Bass / Treble / ...)
    // ═══════════════════════════════════════════════════════════════════════
    Column {
        id: page1
        anchors.fill: parent
        spacing: 12
        visible: !root.customPageActive

        // ── Sliders row — full width in sidebar, art+sliders in main island ──
        Item {
            width: parent.width
            height: parent.height - bottomRow.height - parent.spacing

            // Album art (main island only — tap to switch to custom page)
            Item {
                id: artColumn
                visible: !root.sidebarMode
                width:  visible ? parent.height : 0
                height: parent.height

                Image {
                    id: eqArtImage
                    anchors.fill: parent
                    source: root._artUrl
                    fillMode: Image.PreserveAspectCrop
                    smooth: true; mipmap: true; cache: true
                    visible: false
                }
                Rectangle {
                    id: eqArtMask
                    anchors.fill: parent
                    radius: 22; visible: false
                }
                OpacityMask {
                    anchors.fill: parent
                    source: eqArtImage
                    maskSource: eqArtMask
                }
                Rectangle {
                    anchors.fill: parent; radius: 22
                    color: "transparent"
                    border.width: 1; border.color: Qt.rgba(1,1,1,0.08)
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.customPageActive = true
                }
            }

            Row {
                anchors.left:   artColumn.visible ? artColumn.right : parent.left
                anchors.leftMargin: artColumn.visible ? 20 : 0
                anchors.right:  parent.right
                anchors.top:    parent.top
                anchors.bottom: parent.bottom
                spacing: 4

                Repeater {
                    model: 10
                    delegate: Item {
                        width: (parent.width - 9 * 4) / 10
                        height: parent.height

                        readonly property real bandGain: root.bandValues[index] !== undefined ? root.bandValues[index] : 0
                        readonly property string bandLabel: ["31","63","125","250","500","1k","2k","4k","8k","16k"][index]

                        Column {
                            anchors.fill: parent
                            spacing: 4

                            Item {
                                width: parent.width
                                height: parent.height - bandLabelText.height - 4

                                Rectangle {
                                    id: bandTrack
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 6
                                    height: parent.height
                                    radius: 3
                                    color: Qt.rgba(1, 1, 1, 0.08)

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 10; height: 1
                                        color: Qt.rgba(1, 1, 1, 0.2)
                                    }

                                    Rectangle {
                                        readonly property real norm: Math.max(-12, Math.min(12, bandGain)) / 12
                                        width: parent.width; radius: 3
                                        color: norm >= 0 ? "#5e9eff" : "#ff6b6b"
                                        y: norm >= 0
                                           ? parent.height / 2 - (parent.height / 2) * norm
                                           : parent.height / 2
                                        height: (parent.height / 2) * Math.abs(norm)
                                    }
                                }

                                MouseArea {
                                    id: bandDrag
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    preventStealing: true
                                    function valueFromY(y) {
                                        const h = bandTrack.height
                                        const clampedY = Math.max(0, Math.min(h, y))
                                        const norm = 1 - (clampedY / h) * 2
                                        return Math.max(-12, Math.min(12, norm * 12))
                                    }
                                    onPressed: (mouse) => {
                                        mouse.accepted = true
                                        const localY = mapToItem(bandTrack, mouse.x, mouse.y).y
                                        root.setBand(index + 1, valueFromY(localY))
                                    }
                                    onPositionChanged: (mouse) => {
                                        if (!pressed) return
                                        const localY = mapToItem(bandTrack, mouse.x, mouse.y).y
                                        root.setBand(index + 1, valueFromY(localY))
                                    }
                                }

                                Rectangle {
                                    readonly property real norm: Math.max(-12, Math.min(12, bandGain)) / 12
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 14; height: 14; radius: 7
                                    color: "white"
                                    y: (parent.height / 2) - (parent.height / 2) * norm - height / 2
                                    Behavior on y {
                                        enabled: !bandDrag.pressed
                                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                    }
                                }
                            }

                            Text {
                                renderType: Text.NativeRendering
                                id: bandLabelText
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: bandLabel
                                color: IslandMotion.textSecondary
                                font.pixelSize: 9
                                font.family: textFontFamily
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: bottomRow
            width: parent.width
            height: 28

            // Draggable scrolling preset list
            ListView {
                id: presetListView
                anchors.left: parent.left
                anchors.right: rightButtons.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                orientation: ListView.Horizontal
                spacing: 6
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.presetNames

                delegate: Rectangle {
                    required property string modelData
                    readonly property bool isActive: root.currentPreset === modelData
                    width: presetText.implicitWidth + 14
                    height: presetListView.height
                    radius: height / 2
                    color: isActive ? "#5e9eff" : Qt.rgba(1, 1, 1, 0.08)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        renderType: Text.NativeRendering
                        id: presetText
                        anchors.centerIn: parent
                        text: modelData
                        color: isActive ? IslandMotion.textPrimary : IslandMotion.textSecondary
                        font.pixelSize: 10
                        font.family: textFontFamily
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.applyPreset(modelData)
                    }
                }
            }

            Row {
                id: rightButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                spacing: 6

                // Custom slots button
                Rectangle {
                    width: 58; height: parent.height; radius: height / 2
                    color: customPageBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                    border.width: 1
                    border.color: Qt.rgba(1,1,1,0.18)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: "Custom"
                        color: IslandMotion.textSecondary
                        font.pixelSize: 10
                        font.family: textFontFamily
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: customPageBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.customPageActive = true
                    }
                }

                // Apply button
                Rectangle {
                    id: applyButton
                    width: 58; height: parent.height; radius: height / 2
                    color: root.pendingChanges ? "#5e9eff" : Qt.rgba(1, 1, 1, 0.06)
                    Behavior on color { ColorAnimation { duration: 200 } }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: root.pendingChanges ? "Apply" : "Saved"
                        color: root.pendingChanges ? IslandMotion.textPrimary : IslandMotion.textSecondary
                        font.pixelSize: 10
                        font.family: textFontFamily
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.pendingChanges
                        cursorShape: root.pendingChanges ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.applyChanges()
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAGE 2 — custom numbered slots, full width sliders
    // ═══════════════════════════════════════════════════════════════════════
    Column {
        id: page2
        anchors.fill: parent
        spacing: 12
        visible: root.customPageActive

        Item {
            width: parent.width
            height: parent.height - bottomRow2.height - parent.spacing

            Row {
                anchors.fill: parent
                spacing: 4

                Repeater {
                    model: 10
                    delegate: Item {
                        width: (parent.width - 9 * 4) / 10
                        height: parent.height

                        readonly property real bandGain: root.customBandValues[index] !== undefined ? root.customBandValues[index] : 0
                        readonly property string bandLabel: ["31","63","125","250","500","1k","2k","4k","8k","16k"][index]

                        Column {
                            anchors.fill: parent
                            spacing: 4

                            Item {
                                width: parent.width
                                height: parent.height - bandLabelText2.height - 4

                                Rectangle {
                                    id: bandTrack2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 6; height: parent.height; radius: 3
                                    color: Qt.rgba(1, 1, 1, 0.08)

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 10; height: 1
                                        color: Qt.rgba(1, 1, 1, 0.2)
                                    }

                                    Rectangle {
                                        readonly property real norm: Math.max(-12, Math.min(12, bandGain)) / 12
                                        width: parent.width; radius: 3
                                        color: norm >= 0 ? "#5e9eff" : "#ff6b6b"
                                        y: norm >= 0
                                           ? parent.height / 2 - (parent.height / 2) * norm
                                           : parent.height / 2
                                        height: (parent.height / 2) * Math.abs(norm)
                                    }
                                }

                                MouseArea {
                                    id: bandDrag2
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    preventStealing: true
                                    function valueFromY(y) {
                                        const h = bandTrack2.height
                                        const clampedY = Math.max(0, Math.min(h, y))
                                        const norm = 1 - (clampedY / h) * 2
                                        return Math.max(-12, Math.min(12, norm * 12))
                                    }
                                    onPressed: (mouse) => {
                                        mouse.accepted = true
                                        const localY = mapToItem(bandTrack2, mouse.x, mouse.y).y
                                        root.setCustomBand(index + 1, valueFromY(localY))
                                    }
                                    onPositionChanged: (mouse) => {
                                        if (!pressed) return
                                        const localY = mapToItem(bandTrack2, mouse.x, mouse.y).y
                                        root.setCustomBand(index + 1, valueFromY(localY))
                                    }
                                }

                                Rectangle {
                                    readonly property real norm: Math.max(-12, Math.min(12, bandGain)) / 12
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 14; height: 14; radius: 7
                                    color: "white"
                                    y: (parent.height / 2) - (parent.height / 2) * norm - height / 2
                                    Behavior on y {
                                        enabled: !bandDrag2.pressed
                                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                    }
                                }
                            }

                            Text {
                                renderType: Text.NativeRendering
                                id: bandLabelText2
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: bandLabel
                                color: IslandMotion.textSecondary
                                font.pixelSize: 9
                                font.family: textFontFamily
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }

            // Bottom row — ‹ Presets on left, slots in middle, Reset+Save on right
        }

        Item {
            id: bottomRow2
            width: parent.width
            height: 28

            // ‹ Presets back button
            Rectangle {
                id: backToPresetsBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: presetsBtnText.implicitWidth + 20
                height: parent.height; radius: height / 2
                color: presetsBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.15) : Qt.rgba(1,1,1,0.08)
                border.width: 1; border.color: Qt.rgba(1,1,1,0.18)
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    id: presetsBtnText
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: "‹ Presets"
                    color: IslandMotion.textSecondary
                    font.pixelSize: 10
                    font.family: textFontFamily
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: presetsBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.customPageActive = false
                }
            }

            // Numbered slot pills — centered between back button and action buttons
            Row {
                id: slotRow
                anchors.left: backToPresetsBtn.right
                anchors.right: actionButtons.left
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                spacing: 5
                clip: true

                Repeater {
                    model: 10
                    delegate: Rectangle {
                        readonly property int slotNum: index + 1
                        readonly property bool isFilled: !!root.customSlotsFilled[String(slotNum)]
                        readonly property bool isSelected: root.selectedSlot === slotNum
                        width: 22; height: parent.height; radius: height / 2
                        color: isSelected
                            ? "#5e9eff"
                            : (isFilled ? Qt.rgba(0.36, 0.62, 1.0, 0.35) : Qt.rgba(1, 1, 1, 0.08))
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: String(slotNum)
                            color: isSelected ? IslandMotion.textPrimary : IslandMotion.textSecondary
                            font.pixelSize: 10
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selectSlot(slotNum)
                        }
                    }
                }
            }

            Row {
                id: actionButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                spacing: 6

                Rectangle {
                    width: 50; height: parent.height; radius: height / 2
                    color: resetMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: "Reset"
                        color: IslandMotion.textSecondary
                        font.pixelSize: 10
                        font.family: textFontFamily
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: resetMouse; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.resetSelectedSlot()
                    }
                }

                Rectangle {
                    width: 50; height: parent.height; radius: height / 2
                    color: root.customSlotDirty ? "#5e9eff" : Qt.rgba(1, 1, 1, 0.06)
                    Behavior on color { ColorAnimation { duration: 200 } }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: root.customSlotDirty ? "Save" : "Saved"
                        color: root.customSlotDirty ? IslandMotion.textPrimary : IslandMotion.textSecondary
                        font.pixelSize: 10
                        font.family: textFontFamily
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.customSlotDirty
                        cursorShape: root.customSlotDirty ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.saveSelectedSlot()
                    }
                }
            }
        }
    }
}
