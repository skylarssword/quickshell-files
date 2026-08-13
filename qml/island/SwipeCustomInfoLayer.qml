import QtQuick
import IslandBackend
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import "../shared"

Item {
    id: root

    readonly property var userConfig: UserConfig

    property var items: []
    property var cavaLevels: []
    property string timeText: ""
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string iconFontFamily: activeConfig.iconFontFamily
    property string textFontFamily: activeConfig.textFontFamily
    property string timeFontFamily: activeConfig.timeFontFamily
    property bool showCondition: false
    property bool showSecondaryText: true
    property bool recordingActive: false
    property real transitionProgress: 0
    property real minimumWidth: 220
    property real maximumWidth: minimumWidth
    property real horizontalPadding: 14
    property real hiddenLeftPadding: 18
    property real hiddenRightPadding: 18
    property real groupSpacing: 16
    property real iconSpacing: 8
    property int textPixelSize: 16
    property int iconPixelSize: 16
    property int iconBoxSize: 18
    property int batteryIconWidth: 30
    property int batteryIconHeight: 15
    property int batteryTipWidth: 3
    property int batteryTipHeight: 7
    property int batteryOuterRadius: 5
    property int batteryInnerRadius: 3
    property real iconVerticalOffset: 1
    property int recordingDotSpacing: 12
    readonly property string chargingIconGlyph: "\uf0e7"
property string currentDateLabel: Qt.formatDate(new Date(), "ddd, MMM d")
    readonly property real clampedProgress: Math.max(0, Math.min(1, -transitionProgress))
    readonly property real textWidth: Math.max(0, width - horizontalPadding * 2)
    readonly property real centeredTimeX: horizontalPadding
    readonly property real centeredItemsX: (width - contentRow.implicitWidth) / 2
    readonly property real timeHiddenLeftX: -textWidth - hiddenLeftPadding
    readonly property real itemsHiddenRightX: width + hiddenRightPadding
    readonly property real timeExitDistance: Math.max(0, centeredTimeX - timeHiddenLeftX)
    readonly property real itemsEntryDistance: Math.max(0, itemsHiddenRightX - centeredItemsX)
    readonly property real dragDistance: Math.max(timeExitDistance, itemsEntryDistance)
    readonly property real itemsX: centeredItemsX + (1 - clampedProgress) * dragDistance
    readonly property real timeX: centeredTimeX - clampedProgress * dragDistance
readonly property real visibleTimeWidth: timeCluster.width
    readonly property real timeRecordingDotX: Math.max(
        4,
        timeX + (textWidth - visibleTimeWidth) / 2 - recordingDotSpacing - timeRecordingIndicator.width
    )
property var activePlayer: null
    property string currentArtUrl: ""
    readonly property bool hasActivePlayer: activePlayer !== null

    // nowPlayingCluster now lives as an ordinary first child inside
    // contentRow (below), so its width is automatically folded into
    // contentRow.implicitWidth — no manual reservation needed.
    readonly property real preferredWidth: Math.max(
        minimumWidth,
        Math.min(Math.max(minimumWidth, maximumWidth), contentRow.implicitWidth + horizontalPadding * 2 + 28)
    )

    function toggleNowPlaying() {
        if (!activePlayer || !activePlayer.canControl) return
        if (activePlayer.canTogglePlaying) { activePlayer.togglePlaying(); return }
        if (activePlayer.playbackState === MprisPlaybackState.Playing) {
            if (activePlayer.canPause) activePlayer.pause()
            return
        }
        if (activePlayer.canPlay) activePlayer.play()
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
        id: timeMetrics
        font.family: timeFontFamily
        font.pixelSize: root.textPixelSize + 1
        font.weight: Font.Bold
        text: timeText
    }

Row {
    id: contentRow
    x: itemsX
    height: parent.height
    anchors.verticalCenter: parent.verticalCenter
    opacity: clampedProgress
    spacing: groupSpacing

    // ── Now-playing quick controls — first child, so it renders on
    // the LEFT edge, ahead of the swipe-item Repeater.
    Row {
        id: nowPlayingCluster
        visible: root.hasActivePlayer
        height: parent.height
        spacing: 8

        // Album art — Now the FIRST element, rendering on the leftmost side
        Item {
            width: 26; height: 26
            anchors.verticalCenter: parent.verticalCenter
            visible: root.currentArtUrl !== ""

            Image {
                id: customArtImage
                anchors.fill: parent
                source: root.currentArtUrl
                fillMode: Image.PreserveAspectCrop
                visible: false
                sourceSize: Qt.size(80, 80)
            }
            Rectangle {
                id: customArtMask
                anchors.fill: parent
                radius: width / 2
                visible: false
            }
            OpacityMask {
                anchors.fill: parent
                source: customArtImage
                maskSource: customArtMask
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: IslandMotion.surfaceBorderWidth
                border.color: IslandMotion.surfaceBorderColor
            }
        }

        // Previous
        Item {
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter
            scale: prevQuickArea.pressed ? 0.8 : 1.0
            Behavior on scale { NumberAnimation { duration: 100 } }
            Canvas {
                anchors.fill: parent
                property color fillColor: prevQuickArea.pressed ? "#888" : "white"
                onFillColorChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = fillColor
                    ctx.strokeStyle = fillColor
                    ctx.lineJoin = "round"
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.rect(3, 5, 3, 18)
                    ctx.moveTo(14, 5); ctx.lineTo(6, 14); ctx.lineTo(14, 23)
                    ctx.closePath()
                    ctx.moveTo(23, 5); ctx.lineTo(15, 14); ctx.lineTo(23, 23)
                    ctx.closePath()
                    ctx.fill()
                    ctx.stroke()
                }
            }
            MouseArea {
                id: prevQuickArea
                anchors.fill: parent
                anchors.margins: -10
                preventStealing: true
                onClicked: if (root.activePlayer) root.activePlayer.previous()
            }
        }

        // Play/Pause
        Item {
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter
            scale: playQuickArea.pressed ? 0.8 : 1.0
            Behavior on scale { NumberAnimation { duration: 100 } }
            Row {
                anchors.centerIn: parent
                spacing: 6
                visible: root.activePlayer && root.activePlayer.playbackState === MprisPlaybackState.Playing
                Rectangle { width: 6; height: 20; radius: 2; color: playQuickArea.pressed ? "#888" : "white" }
                Rectangle { width: 6; height: 20; radius: 2; color: playQuickArea.pressed ? "#888" : "white" }
            }
            Canvas {
                anchors.fill: parent
                visible: !root.activePlayer || root.activePlayer.playbackState !== MprisPlaybackState.Playing
                property color fillColor: playQuickArea.pressed ? "#888" : "white"
                onFillColorChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = fillColor
                    ctx.strokeStyle = fillColor
                    ctx.lineJoin = "round"
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.moveTo(8, 4); ctx.lineTo(24, 14); ctx.lineTo(8, 24)
                    ctx.closePath()
                    ctx.fill()
                    ctx.stroke()
                }
            }
            MouseArea {
                id: playQuickArea
                anchors.fill: parent
                anchors.margins: -10
                preventStealing: true
                onClicked: root.toggleNowPlaying()
            }
        }

        // Next
        Item {
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter
            scale: nextQuickArea.pressed ? 0.8 : 1.0
            Behavior on scale { NumberAnimation { duration: 100 } }
            Canvas {
                anchors.fill: parent
                property color fillColor: nextQuickArea.pressed ? "#888" : "white"
                onFillColorChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = fillColor
                    ctx.strokeStyle = fillColor
                    ctx.lineJoin = "round"
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.moveTo(5, 5); ctx.lineTo(13, 14); ctx.lineTo(5, 23)
                    ctx.closePath()
                    ctx.moveTo(14, 5); ctx.lineTo(22, 14); ctx.lineTo(14, 23)
                    ctx.closePath()
                    ctx.rect(22, 5, 3, 18)
                    ctx.fill()
                    ctx.stroke()
                }
            }
            MouseArea {
                id: nextQuickArea
                anchors.fill: parent
                anchors.margins: -10
                preventStealing: true
                onClicked: if (root.activePlayer) root.activePlayer.next()
            }
        }
    } // closes nowPlayingCluster

    Repeater {
        model: root.items

        delegate: Item {
            readonly property bool hasIcon: modelData.icon !== ""
            readonly property bool isCava: modelData.kind === "cava"
            readonly property bool isBattery: modelData.kind === "battery"
            readonly property bool hasLeadingVisual: hasIcon || isBattery
            implicitWidth: isCava
                ? cavaBars.implicitWidth
                : (isBattery && modelData.isCharging ? (chargingIcon.implicitWidth + 4) : 0)
                  + leadingVisual.width + (hasLeadingVisual ? root.iconSpacing : 0) + valueText.implicitWidth
            implicitHeight: root.height
            width: implicitWidth
            height: implicitHeight

            SwipeCavaBars {
                id: cavaBars
                visible: parent.isCava
                anchors.centerIn: parent
                levels: root.cavaLevels
            }

            Text {
                renderType: Text.NativeRendering
                id: chargingIcon
                visible: parent.isBattery && modelData.isCharging
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.chargingIconGlyph
                color: "white"
                font.pixelSize: root.iconPixelSize - 1
                font.family: root.iconFontFamily
            }

            Item {
                id: leadingVisual
                visible: !parent.isCava && parent.hasLeadingVisual
                width: parent.isBattery ? root.batteryIconWidth : (parent.hasIcon ? root.iconBoxSize : 0)
                height: parent.isBattery ? Math.max(root.batteryIconHeight, valueText.implicitHeight) : root.iconBoxSize
                anchors.left: parent.isBattery ? valueText.right : parent.left
                anchors.leftMargin: parent.isBattery ? root.iconSpacing : 0
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.iconVerticalOffset
                    visible: parent.parent.hasIcon && !parent.parent.isBattery
                    text: modelData.icon || ""
                    color: "white"
                    font.pixelSize: root.iconPixelSize
                    font.family: root.iconFontFamily
                }

                Item {
                    visible: parent.parent.isBattery
                    width: root.batteryIconWidth
                    height: root.batteryIconHeight
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: root.batteryTipWidth
                        radius: root.batteryOuterRadius
                        color: "transparent"
                        border.color: IslandMotion.textSecondary
                        border.width: 1

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 2
                            radius: root.batteryInnerRadius
                            width: Math.max(0, (parent.width - 4) * (Math.max(0, Math.min(100, Number(modelData.level || 0))) / 100.0))
                            color: {
                                const level = Math.max(0, Math.min(100, Number(modelData.level || 0)));
                                if (level <= 10) return "#ff3b30";
                                if (level <= 20) return "#ffcc00";
                                return "#34c759";
                            }

                            Behavior on width {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: root.batteryTipWidth
                        height: root.batteryTipHeight
                        radius: Math.round(root.batteryTipWidth / 2)
                        color: IslandMotion.textSecondary
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Text {
                renderType: Text.NativeRendering
                visible: !parent.isCava
                id: valueText
                anchors.left: parent.isBattery 
                    ? (chargingIcon.visible ? chargingIcon.right : parent.left)
                    : leadingVisual.right
                anchors.leftMargin: (parent.isBattery && chargingIcon.visible) 
                    ? 4 
                    : (parent.hasLeadingVisual && !parent.isBattery ? root.iconSpacing : 0)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.text || ""
                color: "white"
                font.pixelSize: root.textPixelSize
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
                font.letterSpacing: -0.15
                wrapMode: Text.NoWrap
            }
        } // closes delegate Item
    } // closes Repeater
} // closes contentRow



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
}
