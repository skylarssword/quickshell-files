import QtQuick

// single-line text; when too long it waits, scrolls to reveal the end, pauses and slides back
Item {
    id: mq
    property string text: ""
    property color  color: "white"
    property string family: ""
    property real   pixelSize: 14
    property int    weight: Font.Normal
    property bool   active: true
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    height: label.height
    clip: true

    Text {
        id: label
        renderType: Text.NativeRendering
        x: 0
        text: mq.text
        color: mq.color
        font.family: mq.family
        font.pixelSize: mq.pixelSize
        font.weight: mq.weight
        onTextChanged: { x = 0; if (anim.running) anim.restart() }
    }
    SequentialAnimation {
        id: anim
        running: mq.overflow > 0 && mq.active
        loops: Animation.Infinite
        onRunningChanged: if (!running) label.x = 0
        PauseAnimation { duration: 2500 }
        NumberAnimation { target: label; property: "x"; to: -mq.overflow
            duration: Math.min(7000, Math.max(900, mq.overflow * 16)); easing.type: Easing.InOutSine }
        PauseAnimation { duration: 1500 }
        NumberAnimation { target: label; property: "x"; to: 0; duration: 500; easing.type: Easing.InOutSine }
    }
}
