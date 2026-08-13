import QtQuick
import IslandBackend
import "../shared"

// The "time-only" clock display -- redone as a vertical stack (big time on
// top, small date underneath) matching mugen's stacked clock style. This
// component only covers this one state; other clocks (workspace bubble
// title, swipe lyrics panel, etc.) are untouched.
Item {
    id: root

    readonly property var userConfig: UserConfig

    property string currentTime: "00:00"
    property string currentDateLabel: ""
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string heroFontFamily: activeConfig.heroFontFamily
    property string textFontFamily: activeConfig.textFontFamily
    property bool showCondition: false
    property real contentOffsetX: 0
    property int textPixelSize: 18

    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: showCondition ? IslandMotion.contentEnterDuration : IslandMotion.contentExitDuration
            easing.type: showCondition ? IslandMotion.easeMove : IslandMotion.easeOut
        }
    }

    Item {
        width: parent.width
        height: parent.height
        x: contentOffsetX
        clip: true

        Column {
            anchors.centerIn: parent
            spacing: 0

            Text {
                renderType: Text.NativeRendering
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.currentTime
                color: IslandMotion.textPrimary
                font.pixelSize: root.textPixelSize
                font.family: root.heroFontFamily
                font.weight: Font.Bold
                font.letterSpacing: -0.35
                wrapMode: Text.NoWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                renderType: Text.NativeRendering
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.currentDateLabel
                color: IslandMotion.textFaint
                font.pixelSize: Math.max(9, root.textPixelSize * 0.42)
                font.family: root.textFontFamily
                font.letterSpacing: 0.2
                wrapMode: Text.NoWrap
                horizontalAlignment: Text.AlignHCenter
                visible: root.currentDateLabel !== ""
            }
        }
    }
}
