import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell._Window
import Quickshell.Services.SystemTray
import "../shared"

Rectangle {
    id: root

    property bool useWalColor: false
    property color walColor: "#000000"
    property real capsuleOpacityValue: 0.20
    property bool gamemodeActive: false
    property string iconFontFamily: "monospace"
    property string textFontFamily: "sans-serif"

    property bool dndActive: false
    signal dndToggleRequested()
    signal notificationCenterRequested()
    signal powerMenuRequested()

    property int unseenCount: 0
    property bool notificationPulseToggle: false
    onNotificationPulseToggleChanged: {
        if (!root.dndActive) {
            bellWobble.restart()
            // Sound is handled centrally in shell.qml
        }
    }

    SoundEffect {
        id: notificationSound
        source: Quickshell.shellDir + "/qml/shared/assets/sounds/notification.mp3"
        volume: IslandConfiguration.notificationSoundVolume / 100.0
    }

    property bool expanded: false
    readonly property string archGlyph: "󰣇"
    // bell glyphs replaced by SVGs — see assets/notification.svg and notification-off.svg
    readonly property string packageGlyph: "\uf487"

    readonly property int glyphSlotWidth: 38
    readonly property int fixedIconPixelSize: 16
    readonly property int trayIconSize: 16
    readonly property int trayIconSpacing: 8
    readonly property int trayGap: 10
    readonly property int itemCount: trayRepeater.count

    readonly property int dividerWidth: 2
    readonly property int dividerHeight: 16
    readonly property color dividerColor: IslandMotion.surfaceBorderColor
    readonly property int edgePadding: 12

    property int updatesCount: 0

    Process {
        id: updatesQuery
        property string _buf: ""
        command: ["bash", "-c",
            "echo $(( $(checkupdates 2>/dev/null | wc -l) + $(paru -Qum 2>/dev/null | wc -l) ))"]
        stdout: SplitParser { onRead: updatesQuery._buf += data }
        onRunningChanged: {
            if (!running) {
                const parsed = parseInt(updatesQuery._buf.trim(), 10)
                root.updatesCount = isNaN(parsed) ? 0 : parsed
                updatesQuery._buf = ""
            }
        }
    }

    Process {
        id: updatesRunner
        command: ["kitty", "-e", "bash", "-c", "~/.config/ml4w/scripts/ml4w-install-system-updates"]
        onRunningChanged: {
            if (!running) updatesQuery.running = true
        }
    }

    Timer {
        id: updatesPollTimer
        interval: 3600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!updatesQuery.running) updatesQuery.running = true
        }
    }

    width: Math.max(glyphSlotWidth + edgePadding * 2, fixedRow.implicitWidth + edgePadding * 2)
    height: 38
    radius: 19
    y: 5
    clip: true

    Behavior on width {
        NumberAnimation { duration: IslandMotion.standard; easing.type: IslandMotion.easeArrive }
    }

    color: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    Behavior on color { ColorAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove } }

    border.width: IslandMotion.surfaceBorderWidth
    border.color: IslandMotion.surfaceBorderColor

    component Divider: Rectangle {
        width: root.dividerWidth
        height: root.dividerHeight
        radius: root.dividerWidth / 2
        color: root.dividerColor
        anchors.verticalCenter: parent.verticalCenter
    }

    Row {
        id: fixedRow
        anchors.right: parent.right
        anchors.rightMargin: root.edgePadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayIconSpacing

        // ── Expandable tray: updates + real tray icons ─────────────────
        Row {
            id: trayRow
            spacing: root.trayIconSpacing
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.expanded ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeOut } }

            // ── Update count ──────────────────────────────────────────────
            Item {
                width: updatesRow.implicitWidth
                height: root.trayIconSize
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: updatesRow
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        renderType: Text.NativeRendering
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.packageGlyph
                        font.family: root.iconFontFamily
                        font.pixelSize: root.trayIconSize
                        color: "white"
                        opacity: updatesMouse.containsMouse ? 1.0 : 0.7
                        scale: updatesMouse.containsMouse ? 1.15 : (updatesMouse.pressed ? 0.82 : 1.0)
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        id: updatesText
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(root.updatesCount)
                        font.family: root.textFontFamily
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: "white"
                        opacity: updatesMouse.containsMouse ? 1.0 : 0.7
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                }

                MouseArea {
                    id: updatesMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    z: 10
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.expanded
                    onClicked: updatesRunner.running = true
                }
            }

            Repeater {
                id: trayRepeater
                model: SystemTray.items

                delegate: Item {
                    id: trayIconDelegate
                    width: root.trayIconSize
                    height: root.trayIconSize
                    anchors.verticalCenter: parent.verticalCenter

                    PopupWindow {
                        id: menuPopup
                        visible: false
                        color: "transparent"
                        anchor.item: trayIconDelegate
                        anchor.rect.x: -200 + trayIconDelegate.width
                        anchor.rect.y: trayIconDelegate.height + 8
                        implicitWidth: 200
                        implicitHeight: menuColumn.implicitHeight + 16

                        QsMenuOpener {
                            id: menuOpener
                            menu: modelData.hasMenu ? modelData.menu : null
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "#1e1e1e"
                            radius: 8

                            Column {
                                id: menuColumn
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 8
                                spacing: 2

                                Repeater {
                                    model: menuOpener.children ? menuOpener.children.values : []

                                    delegate: Column {
                                        id: menuItemDelegate
                                        width: parent.width
                                        spacing: 2
                                        property bool submenuExpanded: false

                                        Rectangle {
                                            width: parent.width
                                            height: modelData.isSeparator ? 0 : 28
                                            visible: !modelData.isSeparator
                                            radius: 4
                                            color: menuItemArea.containsMouse ? "#333333" : "transparent"
                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            Text {
                                                renderType: Text.NativeRendering
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 8
                                                text: (modelData.text || "") + (modelData.hasChildren ? " ▶" : "")
                                                color: menuItemArea.containsMouse ? "white" : Qt.rgba(1,1,1,0.75)
                                                font.pixelSize: 12
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            MouseArea {
                                                id: menuItemArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (modelData.hasChildren) {
                                                        menuItemDelegate.submenuExpanded = !menuItemDelegate.submenuExpanded
                                                    } else {
                                                        if (modelData.triggered)
                                                            modelData.triggered()
                                                        else if (modelData.activate)
                                                            modelData.activate()
                                                        menuPopup.visible = false
                                                    }
                                                }
                                            }
                                        }

                                        Column {
                                            visible: menuItemDelegate.submenuExpanded && modelData.hasChildren
                                            width: parent.width
                                            spacing: 2

                                            QsMenuOpener {
                                                id: subMenuOpener
                                                menu: modelData.hasChildren ? modelData : null
                                            }

                                            Repeater {
                                                model: subMenuOpener.children ? subMenuOpener.children.values : []

                                                delegate: Rectangle {
                                                    width: parent.width
                                                    height: modelData.isSeparator ? 0 : 28
                                                    visible: !modelData.isSeparator
                                                    radius: 4
                                                    color: subMenuArea.containsMouse ? "#333333" : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 150 } }

                                                    Text {
                                                        renderType: Text.NativeRendering
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 16
                                                        text: modelData.text || ""
                                                        color: subMenuArea.containsMouse ? "white" : Qt.rgba(1,1,1,0.75)
                                                        font.pixelSize: 12
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }

                                                    MouseArea {
                                                        id: subMenuArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData.triggered)
                                                                modelData.triggered()
                                                            else if (modelData.activate)
                                                                modelData.activate()
                                                            menuPopup.visible = false
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Image {
                        id: trayIcon
                        anchors.fill: parent
                        source: {
                            const icon = modelData.icon
                            if (!icon || icon === "") return ""
                            return icon
                        }
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                        sourceSize: Qt.size(root.trayIconSize * 2, root.trayIconSize * 2)
                        opacity: trayMouse.containsMouse ? 1.0 : 0.75
                        scale: trayMouse.containsMouse ? 1.2 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        visible: trayIcon.status !== Image.Ready

                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: modelData.title ? modelData.title[0] : "?"
                            color: "white"
                            font.pixelSize: root.trayIconSize - 2
                            opacity: trayMouse.containsMouse ? 1.0 : 0.75
                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }

                    MouseArea {
                        id: trayMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        z: 10
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.expanded
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            mouse.accepted = true
                            if (mouse.button === Qt.RightButton || modelData.onlyMenu) {
                                menuPopup.visible = !menuPopup.visible
                            } else if (modelData.activate) {
                                modelData.activate()
                            }
                        }
                    }
                }
            }
        }

        // ── Divider between tray section and arch — only when expanded ──
        Divider { visible: root.expanded }

        // ── Chevron expand/collapse trigger — flips when tray opens ────
        // Pointing right (›) at rest → points left (‹) when expanded,
        // matching mugen-shell's chevron-double-right / chevron-double-left.
        // We use a single glyph and rotate 180° so the flip is animated.
        Item {
            id: archIconItem
            width: root.glyphSlotWidth
            height: root.height
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: chevronImg
                anchors.centerIn: parent
                width: 22
                height: 22
                source: Quickshell.shellDir + "/qml/shared/assets/chevron-double-left.svg"
                sourceSize: Qt.size(28, 28)
                fillMode: Image.PreserveAspectFit

                // Flip 180° when tray is open — same as mugen-shell's left/right swap
                rotation: root.expanded ? 180 : 0

                opacity: archMouse.containsMouse ? 1.0 : 0.7
                scale: archMouse.containsMouse ? 1.2 : (archMouse.pressed ? 0.82 : 1.0)

                Behavior on opacity  { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale    { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                id: archMouse
                anchors.fill: parent
                anchors.margins: -4
                z: 20
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }

        Divider {}

        // ── Notification / DND toggle ───────────────────────────────────
        Item {
            id: notificationIconItem
            width: root.glyphSlotWidth
            height: root.height
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: bellImg
                anchors.centerIn: parent
                width: root.fixedIconPixelSize + 6
                height: root.fixedIconPixelSize + 6
                source: root.dndActive
                    ? Quickshell.shellDir + "/qml/shared/assets/notification-off.svg"
                    : Quickshell.shellDir + "/qml/shared/assets/notification.svg"
                sourceSize: Qt.size((root.fixedIconPixelSize + 2) * 2, (root.fixedIconPixelSize + 2) * 2)
                fillMode: Image.PreserveAspectFit

                opacity: notificationMouse.containsMouse ? 1.0 : 0.7
                scale: notificationMouse.containsMouse ? 1.15 : (notificationMouse.pressed ? 0.82 : 1.0)

                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale   { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                SequentialAnimation {
                    id: bellWobble
                    NumberAnimation { target: bellImg; property: "rotation"; to: 16;  duration: 70;  easing.type: Easing.OutQuad }
                    NumberAnimation { target: bellImg; property: "rotation"; to: -14; duration: 100; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: bellImg; property: "rotation"; to: 8;   duration: 90;  easing.type: Easing.InOutQuad }
                    NumberAnimation { target: bellImg; property: "rotation"; to: 0;   duration: 90;  easing.type: Easing.OutQuad }
                }
            }

            Rectangle {
                id: unseenBadge
                visible: root.unseenCount > 0
                width: Math.max(14, badgeText.implicitWidth + 7)
                height: 14
                radius: height / 2
                color: "#ff3b30"
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 2
                anchors.rightMargin: -2

                Text {
                    id: badgeText
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: root.unseenCount > 99 ? "99+" : String(root.unseenCount)
                    color: "white"
                    font.family: root.textFontFamily
                    font.pixelSize: 9
                    font.bold: true
                }
            }

            MouseArea {
                id: notificationMouse
                anchors.fill: parent
                anchors.margins: -4
                z: 20
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton)
                        root.dndToggleRequested()
                    else
                        root.notificationCenterRequested()
                }
            }
        }

        Divider {}

        // ── Power / arch logo — pinned to the far right ─────────────────
        Item {
            id: powerIconItem
            width: root.glyphSlotWidth
            height: root.height
            anchors.verticalCenter: parent.verticalCenter

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: root.archGlyph
                font.family: root.iconFontFamily
                font.pixelSize: 22
                color: IslandMotion.textPrimary
                opacity: powerMouse.containsMouse ? 1.0 : 0.7
                scale: powerMouse.containsMouse ? 1.15 : (powerMouse.pressed ? 0.82 : 1.0)

                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                id: powerMouse
                anchors.fill: parent
                anchors.margins: -4
                z: 20
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.powerMenuRequested()
            }
        }
    }
}
