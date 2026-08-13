import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects
import "../shared"
import IslandBackend
import Quickshell._Window
import Quickshell.Services.SystemTray

Item {
    id: root

    readonly property var userConfig: UserConfig

    property string lyricText: ""
    property string timeText: ""
    property string currentArtUrl: ""
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string textFontFamily: activeConfig.textFontFamily
    property string timeFontFamily: activeConfig.timeFontFamily
    property bool showCondition: false
    property bool showTray: true
    property bool showSecondaryText: true
    property bool recordingActive: false
    property real transitionProgress: 0
    property int textPixelSize: 16
   readonly property int trayIconSize: 14
    readonly property int trayIconSpacing: 5
    readonly property int trayCount: trayRepeater.count
    readonly property real trayTotalWidth: trayCount > 0 ? (trayCount * (trayIconSize + trayIconSpacing)) + 8 : 0
readonly property real trayReserved: 0
    property real minimumWidth: 220
    property real maximumWidth: minimumWidth
    property real horizontalPadding: 14
    property real hiddenLeftPadding: 18
    property real hiddenRightPadding: 16
    property string activeLyricText: lyricText
    property string previousLyricText: ""
    property real lyricChangeProgress: 1
property int recordingDotSpacing: -5
    property var cavaLevels: []

    readonly property real clampedProgress: Math.max(0, Math.min(1, transitionProgress))
    readonly property bool lyricMostlyVisible: clampedProgress > 0.92
readonly property real artSize: 26
    readonly property real artSpacing: 8
readonly property real artReserved: (currentArtUrl !== "" && lyricMostlyVisible) ? artSize + artSpacing : 0
    // Used for width sizing rather than artReserved directly, since at rest
    // (the state preferredWidth is computed for) the lyrics are fully visible
    // anyway — this avoids a circular dependency on the settled width.
    readonly property real artReservedForWidth: currentArtUrl !== "" ? artSize + artSpacing : 0
readonly property real cavaReserved: lyricMostlyVisible
    ? cavaBars.implicitWidth + artSpacing
    : 0
readonly property real textWidth: Math.max(0, width - horizontalPadding * 2 - artReserved - cavaReserved)
    readonly property real centeredX: horizontalPadding + artReserved
    readonly property real lyricHiddenLeftX: -textWidth - hiddenLeftPadding
    readonly property real timeHiddenRightX: width + hiddenRightPadding
    readonly property real lyricEntryDistance: Math.max(0, centeredX - lyricHiddenLeftX)
    readonly property real timeExitDistance: Math.max(0, timeHiddenRightX - centeredX)
    readonly property real dragDistance: Math.max(lyricEntryDistance, timeExitDistance)
    readonly property real lyricX: centeredX - (1 - clampedProgress) * dragDistance
    readonly property real timeX: centeredX + clampedProgress * dragDistance
    readonly property real visibleLyricWidth: Math.min(textWidth, Math.max(0, lyricMetrics.advanceWidth))
readonly property real visibleTimeWidth: textWidth
    readonly property real timeRecordingDotX: Math.max(
        4,
        timeX + (textWidth - visibleTimeWidth) / 2 - recordingDotSpacing - timeRecordingIndicator.width
    )
readonly property real preferredWidth: Math.max(
140 + cavaReserved + artReservedForWidth,
        Math.min(Math.max(minimumWidth, maximumWidth), lyricMetrics.advanceWidth + horizontalPadding * 2 + 28 + cavaReserved + artReservedForWidth)
    )
    onLyricTextChanged: {
        if (lyricText === activeLyricText) return;

        if (activeLyricText === "" || !lyricMostlyVisible) {
            lyricChangeAnimation.stop();
            previousLyricText = "";
            activeLyricText = lyricText;
            lyricChangeProgress = 1;
            return;
        }

        previousLyricText = activeLyricText;
        activeLyricText = lyricText;
        lyricChangeProgress = 0;
        lyricChangeAnimation.restart();
    }

    onShowConditionChanged: {
        if (showCondition) return;
        lyricChangeAnimation.stop();
        previousLyricText = "";
        activeLyricText = lyricText;
        lyricChangeProgress = 1;
    }

    onTransitionProgressChanged: {
        if (lyricMostlyVisible) return;
        lyricChangeAnimation.stop();
        previousLyricText = "";
        activeLyricText = lyricText;
        lyricChangeProgress = 1;
    }

    anchors.fill: parent
    clip: true
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: showCondition ? 220 : 140
            easing.type: Easing.InOutQuad
        }
    }

    TextMetrics {
        id: lyricMetrics
        font.family: textFontFamily
        font.pixelSize: textPixelSize
        font.weight: Font.DemiBold
        text: activeLyricText !== "" ? activeLyricText : lyricText
    }

    TextMetrics {
        id: timeMetrics
        font.family: timeFontFamily
        font.pixelSize: textPixelSize + 1
        font.weight: Font.Bold
        text: timeText
    }

    SequentialAnimation {
        id: lyricChangeAnimation

        NumberAnimation {
            target: root
            property: "lyricChangeProgress"
            from: 0
            to: 1
            duration: 260
            easing.type: Easing.OutCubic
        }

        ScriptAction {
            script: root.previousLyricText = ""
        }
    }

Item {
        visible: currentArtUrl !== "" && root.lyricMostlyVisible
        width: root.artSize
        height: root.artSize
        x: horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        opacity: clampedProgress

        Image {
    id: artImage
    anchors.fill: parent
    source: currentArtUrl
    fillMode: Image.PreserveAspectCrop

    sourceSize: Qt.size(64, 64)
    cache: true
    visible: false
}

        Rectangle {
            id: artMask
            anchors.fill: parent
            radius: width / 2
            visible: false
        }

OpacityMask {
            anchors.fill: parent
            source: artImage
            maskSource: artMask
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
        }
    }
    
    
    SwipeCavaBars {
        id: cavaBars
        visible: root.lyricMostlyVisible
        levels: root.cavaLevels
        anchors.right: parent.right
        anchors.rightMargin: horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        opacity: clampedProgress
    }
    Text {
        renderType: Text.NativeRendering
        visible: previousLyricText !== ""
        x: lyricX
        width: textWidth
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -14 * lyricChangeProgress
        text: previousLyricText
        color: "white"
        opacity: clampedProgress * (1 - lyricChangeProgress)
        font.pixelSize: textPixelSize
        font.family: textFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }

    Text {
        renderType: Text.NativeRendering
        visible: activeLyricText !== ""
        x: lyricX
        width: textWidth
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: previousLyricText !== "" ? 12 * (1 - lyricChangeProgress) : 0
        text: activeLyricText
        color: "white"
        opacity: clampedProgress * (previousLyricText !== "" ? lyricChangeProgress : 1)
        font.pixelSize: textPixelSize
        font.family: textFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }

Column {
    id: timeCluster
    x: timeX
    width: textWidth
    anchors.verticalCenter: parent.verticalCenter
    spacing: -6
    opacity: 1 - clampedProgress
    visible: timeText !== "" && showSecondaryText

    Text {
        renderType: Text.NativeRendering
        width: parent.width
        text: timeText
        color: IslandMotion.textPrimary
        font.pixelSize: textPixelSize - 1
        font.family: timeFontFamily
        font.weight: Font.Bold
        font.letterSpacing: -0.35
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }

    Text {
        renderType: Text.NativeRendering
        width: parent.width
        text: Qt.formatDate(new Date(), "ddd, MMM d")
        color: IslandMotion.textSecondary
        font.pixelSize: Math.max(11, textPixelSize * 0.42)
        font.family: textFontFamily
        font.weight: Font.Bold
        font.letterSpacing: 0.2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap

        transform: Translate {
            y: -3
        }
    }
}

    RecordingIndicator {
        id: timeRecordingIndicator
        active: root.recordingActive
            && root.showSecondaryText
            && root.timeText !== ""
            && root.clampedProgress < 0.001
        contentOpacity: 1 - root.clampedProgress
        x: root.timeRecordingDotX
        anchors.verticalCenter: parent.verticalCenter
    }
    
   Row {
        anchors.right: parent.right
        anchors.rightMargin: horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: trayIconSpacing
        opacity: 1 - clampedProgress
        visible: clampedProgress < 0.1 && showTray

        Repeater {
            id: trayRepeater
            model: SystemTray.items

            delegate: Item {
                width: root.trayIconSize
                height: root.trayIconSize

                PopupWindow {
                    id: menuPopup
                    visible: false
                    color: "transparent"
                    anchor.item: trayIcon
                    anchor.rect.x: -200 + trayIcon.width
                    anchor.rect.y: trayIcon.height + 8
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

delegate: Item {
                                    id: menuItemRect
                                    width: parent.width
                                    height: modelData.isSeparator ? 0 : 28
                                    visible: !modelData.isSeparator
                                    clip: false

                                    Text {
                                        renderType: Text.NativeRendering
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        text: (modelData.text || "") + (modelData.hasChildren ? " ▶" : "")
                                        color: "white"
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        id: menuItemArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (modelData.hasChildren) {
                                                submenuPopup.visible = !submenuPopup.visible
                                            } else {
                                                if (modelData.triggered)
                                                    modelData.triggered()
                                                menuPopup.visible = false
                                            }
                                        }
                                    }

                                    QsMenuOpener {
                                        id: subMenuOpener
                                        menu: modelData.hasChildren ? modelData : null
                                    }

                                    // Submenu renders as its own popup window, anchored
                                    // beside this item, rather than expanding inline —
                                    // inline expansion required the outer Column to grow
                                    // exactly in sync with async-loaded submenu content,
                                    // which drifted out of sync and caused overlap.
                                    PopupWindow {
                                        id: submenuPopup
                                        visible: false
                                        color: "transparent"
                                        anchor.item: menuItemRect
                                        anchor.rect.x: menuItemRect.width
                                        anchor.rect.y: 0
                                        implicitWidth: 200
                                        implicitHeight: submenuColumn.implicitHeight + 16

                                        Rectangle {
                                            anchors.fill: parent
                                            color: "#1e1e1e"
                                            radius: 8

                                            Column {
                                                id: submenuColumn
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.margins: 8
                                                spacing: 2

                                                Repeater {
                                                    model: subMenuOpener.children ? subMenuOpener.children.values : []

                                                    delegate: Rectangle {
                                                        width: parent.width
                                                        height: 28
                                                        color: subMenuArea.containsMouse ? "#333333" : "transparent"
                                                        radius: 4
                                                        visible: !modelData.isSeparator

                                                        Text {
                                                            renderType: Text.NativeRendering
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            anchors.left: parent.left
                                                            anchors.leftMargin: 8
                                                            text: modelData.text || ""
                                                            color: "white"
                                                            font.pixelSize: 12
                                                        }

                                                        MouseArea {
                                                            id: subMenuArea
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            onClicked: {
                                                                if (modelData.triggered)
                                                                    modelData.triggered()
                                                                submenuPopup.visible = false
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
                    }
                }

                Image {
                    id: trayIcon
                    anchors.fill: parent
                    source: {
                        const icon = modelData.icon
                        if (!icon || icon === "") return ""
                        if (icon.startsWith("/") || icon.startsWith("file://")) return icon
                        return icon
                    }
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                    sourceSize: Qt.size(root.trayIconSize * 2, root.trayIconSize * 2)
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
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        mouse.accepted = true
                        if (mouse.button === Qt.RightButton || modelData.onlyMenu) {
                            menuPopup.visible = !menuPopup.visible
                        } else {
                            modelData.activate()
                        }
                    }
                }
            }
        }
    }
}
