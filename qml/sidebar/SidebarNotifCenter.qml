import QtQuick
import Quickshell
import Quickshell.Wayland
import IslandBackend
import "../shared"

// ── Centered notification center popup ───────────────────────────────────────

PanelWindow {
    id: root

    property string iconFontFamily: ""
    property string textFontFamily: ""
    property var    notificationHistory: []
    property bool   dndActive: false

    property bool  useWalColor:         false
    property color walColor:            "#000000"
    property real  capsuleOpacityValue: 0.20
    property bool  gamemodeActive:      false

    readonly property color bgColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    signal clearRequested()
    signal dismissRequested(int entryId)
    signal dndToggleRequested()

    property bool popupOpen: false
    function open()  { popupOpen = true  }
    function close() { popupOpen = false }
    function toggle(){ popupOpen = !popupOpen }

    property int expandedIndex: -1
    onNotificationHistoryChanged: { if (notificationHistory.length === 0) expandedIndex = -1 }

    readonly property real cardW: 420
    readonly property real cardH: Math.min(560, 92 + Math.max(1, notificationHistory.length) * 68 + 36)

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: popupOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: popupOpen

    mask: Region {
        Region {
            x: Math.floor(card.x); y: Math.floor(card.y)
            width:  root.popupOpen ? Math.ceil(card.width)  : 0
            height: root.popupOpen ? Math.ceil(card.height) : 0
        }
    }

    MouseArea { anchors.fill: parent; enabled: root.popupOpen; onClicked: root.close(); z: -1 }
    Keys.onEscapePressed: root.close()

    Item {
        id: card
        width:  root.cardW
        height: root.cardH
        anchors.centerIn: parent

        opacity: root.popupOpen ? 1 : 0
        scale:   root.popupOpen ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on height  { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

        Rectangle {
            anchors.fill: parent; radius: 28
            color: root.bgColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            clip: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Item {
            anchors.fill: parent

            // ── Title row ─────────────────────────────────────────────
            Item {
                id: titleRow
                anchors.top: parent.top; anchors.topMargin: 18
                anchors.left: parent.left; anchors.leftMargin: 18
                anchors.right: parent.right; anchors.rightMargin: 18
                height: 30

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: IslandMotion.textPrimary
                    font.family: root.textFontFamily; font.pixelSize: 18; font.weight: Font.Medium
                }

                // DND toggle
                Rectangle {
                    id: dndBtn
                    anchors.right: clearBtn.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 15
                    color: dndMouse.pressed ? Qt.rgba(0.36,0.22,0.7,0.30)
                         : (dndMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.08))
                    border.width: 1
                    border.color: root.dndActive ? Qt.rgba(0.6,0.4,1.0,0.7)
                                : (dndMouse.containsMouse ? Qt.rgba(1,1,1,0.4) : Qt.rgba(1,1,1,0.2))
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent; text: "\uf186"
                        font.family: root.iconFontFamily; font.pixelSize: 13
                        color: root.dndActive ? Qt.rgba(0.7,0.5,1.0,0.95) : IslandMotion.textPrimary
                    }
                    MouseArea { id: dndMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.dndToggleRequested() }
                }

                // Clear all
                Rectangle {
                    id: clearBtn
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 15
                    color: clearMouse.pressed ? Qt.rgba(0.85,0.15,0.15,0.30)
                         : (clearMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.08))
                    border.width: 1
                    border.color: clearMouse.pressed ? Qt.rgba(1,0.3,0.3,0.7)
                                : (clearMouse.containsMouse ? Qt.rgba(1,1,1,0.4) : Qt.rgba(1,1,1,0.2))
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: clearMouse.pressed ? 0.90 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent; text: "\uf0f3"
                        font.family: root.iconFontFamily; font.pixelSize: 14
                        color: clearMouse.pressed ? Qt.rgba(1,0.4,0.4,0.95) : IslandMotion.textPrimary
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: clearMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearRequested()
                    }
                }
            }

            // ── Empty state ───────────────────────────────────────────
            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: "No notifications"
                color: IslandMotion.textFaint
                font.family: root.textFontFamily; font.pixelSize: 13
                visible: root.notificationHistory.length === 0
            }

            // ── Notification list ─────────────────────────────────────
            ListView {
                id: notifList
                anchors.top: titleRow.bottom; anchors.topMargin: 16
                anchors.left: parent.left; anchors.leftMargin: 18
                anchors.right: parent.right; anchors.rightMargin: 18
                anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                spacing: 8; clip: true
                visible: root.notificationHistory.length > 0
                // Use array directly so model updates when items are removed
                model: root.notificationHistory
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 3000
                maximumFlickVelocity: 2400

                delegate: Item {
                    id: notifRow
                    required property var  modelData
                    required property int  index
                    readonly property var  entry:      modelData
                    readonly property bool isExpanded: root.expandedIndex === index
                    readonly property bool hasBody:    (entry.body || "") !== "" && entry.body !== entry.summary

                    width:  notifList.width
                    height: isExpanded ? (hasBody ? 92 : 64) : 56
                    clip:   true

                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

                    // ── Swipe state (mirrors main NotificationCenterLayer) ─
                    property real dragX:          0
                    property bool dragging:       false
                    property bool pendingDismiss: false
                    readonly property real maxSwipe:         -88
                    readonly property real dismissThreshold: -56

                    Behavior on dragX {
                        enabled: !notifRow.dragging
                        NumberAnimation {
                            duration: 260; easing.type: Easing.OutQuart
                            onRunningChanged: {
                                if (!running && notifRow.pendingDismiss) {
                                    notifRow.pendingDismiss = false
                                    root.dismissRequested(notifRow.entry.id)
                                }
                            }
                        }
                    }

                    function relativeTime() {
                        if (!entry.timestamp) return ""
                        const diffMs = Date.now() - entry.timestamp
                        const mins = Math.floor(diffMs / 60000)
                        if (mins < 1)  return "now"
                        if (mins < 60) return mins + "m ago"
                        const hrs = Math.floor(mins / 60)
                        if (hrs < 24)  return hrs + "h ago"
                        return Math.floor(hrs / 24) + "d ago"
                    }

                    // ── Trash reveal behind card ──────────────────────
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: Math.max(0, -notifRow.dragX)
                        radius: 12; clip: true
                        color: StyleTokens.danger
                        visible: notifRow.dragX < -4

                        Text {
                            renderType: Text.NativeRendering
                            anchors.right: parent.right; anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf1f8"
                            font.family: root.iconFontFamily; font.pixelSize: 15
                            color: "white"
                            opacity: Math.min(1, -notifRow.dragX / -(notifRow.dismissThreshold))
                        }
                    }

                    // ── Card ──────────────────────────────────────────
                    Rectangle {
                        id: notifCard
                        x: notifRow.dragX; y: 0
                        width: parent.width; height: parent.height
                        radius: 12; clip: true
                        color: cardMouse.containsMouse || notifRow.isExpanded
                               ? Qt.rgba(1,1,1,0.09) : Qt.rgba(1,1,1,0.05)
                        border.width: IslandMotion.surfaceBorderWidth
                        border.color: IslandMotion.surfaceBorderColor
                        Behavior on color { ColorAnimation { duration: 120 } }

                        // App icon
                        Item {
                            width: 26; height: 26
                            anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 9
                            Image {
                                id: notifIcon; anchors.fill: parent
                                fillMode: Image.PreserveAspectFit; asynchronous: true; cache: true
                                visible: status === Image.Ready
                                source: notifRow.entry.appIcon && notifRow.entry.appIcon !== ""
                                        ? "file://" + notifRow.entry.appIcon : ""
                            }
                            Text {
                                renderType: Text.NativeRendering; anchors.centerIn: parent
                                visible: !notifIcon.visible; text: "\uf0f3"
                                font.family: root.iconFontFamily; font.pixelSize: 13
                                color: IslandMotion.textFaint; opacity: 0.6
                            }
                        }

                        // Timestamp
                        Text {
                            renderType: Text.NativeRendering
                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 9
                            text: notifRow.relativeTime()
                            color: IslandMotion.textFaint
                            font.pixelSize: 9; font.family: root.textFontFamily; opacity: 0.6
                        }

                        // Text content
                        Column {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 44; anchors.rightMargin: 12; anchors.topMargin: 6
                            spacing: 2

                            Text {
                                renderType: Text.NativeRendering; width: parent.width
                                text: notifRow.entry.appName || "Notification"
                                color: IslandMotion.textFaint; font.pixelSize: 10
                                font.weight: Font.DemiBold; font.family: root.textFontFamily
                                elide: Text.ElideRight
                            }
                            Text {
                                renderType: Text.NativeRendering; width: parent.width
                                text: notifRow.entry.summary || ""
                                color: IslandMotion.textPrimary; font.pixelSize: 12
                                font.family: root.textFontFamily
                                elide: notifRow.isExpanded ? Text.ElideNone : Text.ElideRight
                                wrapMode: notifRow.isExpanded ? Text.WordWrap : Text.NoWrap
                                maximumLineCount: notifRow.isExpanded ? 2 : 1
                            }
                            Text {
                                renderType: Text.NativeRendering; width: parent.width
                                visible: notifRow.isExpanded && notifRow.hasBody
                                text: notifRow.entry.body || ""
                                color: IslandMotion.textFaint; opacity: 0.85
                                font.pixelSize: 10; font.family: root.textFontFamily
                                wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                            }
                        }

                        // ── Mouse: swipe + tap ────────────────────────
                        MouseArea {
                            id: cardMouse; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            property real pressX: 0
                            property bool hasMoved: false

                            onPressed: function(mouse) {
                                pressX = mouse.x; hasMoved = false
                                notifRow.dragging = true
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed) return
                                let delta = mouse.x - pressX
                                if (delta > 0) delta = 0
                                if (!hasMoved && Math.abs(delta) > 6) hasMoved = true
                                if (hasMoved) notifRow.dragX = Math.max(notifRow.maxSwipe, delta)
                            }
                            onReleased: function(mouse) {
                                notifRow.dragging = false
                                if (hasMoved) {
                                    if (notifRow.dragX <= notifRow.dismissThreshold) {
                                        notifRow.pendingDismiss = true
                                        notifRow.dragX = -notifRow.width
                                    } else {
                                        notifRow.dragX = 0
                                    }
                                    return
                                }
                                root.expandedIndex = notifRow.isExpanded ? -1 : notifRow.index
                            }
                            onCanceled: {
                                notifRow.dragging = false
                                notifRow.dragX = 0
                            }
                        }
                    }
                }
            }
        }
    }
}
