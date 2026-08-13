import QtQuick
import IslandBackend
import "../shared"

Item {
    id: root

    property string iconFontFamily: "monospace"
    property string textFontFamily: "sans-serif"
    property var notificationHistory: []
    property bool showCondition: true
    property int expandedIndex: -1

    readonly property int contentHeight: 92 + Math.max(1, notificationHistory.length) * 64

    signal clearRequested()
    signal closeRequested()
    signal dismissRequested(int entryId)

    onNotificationHistoryChanged: {
        if (notificationHistory.length === 0)
            expandedIndex = -1
    }

    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: showCondition ? IslandMotion.contentEnterDelay : 0 }
            NumberAnimation {
                duration: showCondition ? IslandMotion.contentEnterDuration : IslandMotion.contentExitDuration
                easing.type: showCondition ? IslandMotion.easeMove : IslandMotion.easeOut
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 18

        Text {
            renderType: Text.NativeRendering
            id: titleText
            text: "Notifications"
            color: IslandMotion.textPrimary
            font.family: root.textFontFamily
            font.pixelSize: 18
            font.weight: Font.Medium
            anchors.top: parent.top
            anchors.left: parent.left
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            width: 30; height: 30; radius: 15
            color: bellMouse.pressed
                   ? Qt.rgba(0.85, 0.15, 0.15, 0.30)
                   : (bellMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.08))
            border.width: 1
            border.color: bellMouse.pressed
                          ? Qt.rgba(1, 0.3, 0.3, 0.7)
                          : (bellMouse.containsMouse ? Qt.rgba(1,1,1,0.4) : Qt.rgba(1,1,1,0.2))

            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            scale: bellMouse.pressed ? 0.90 : 1.0
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: "\uf0f3"
                font.family: root.iconFontFamily
                font.pixelSize: 14
                color: bellMouse.pressed ? Qt.rgba(1, 0.4, 0.4, 0.95) : StyleTokens.white
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            MouseArea {
                id: bellMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearRequested()
            }
        }

        Text {
            renderType: Text.NativeRendering
            anchors.centerIn: parent
            text: "No notifications"
            color: IslandMotion.textFaint
            font.family: root.textFontFamily
            font.pixelSize: 13
            visible: root.notificationHistory.length === 0
        }

        ListView {
            id: notifCenterListView
            anchors.top: titleText.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 8
            clip: true
            visible: root.notificationHistory.length > 0
            model: root.notificationHistory.length
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 3000
            maximumFlickVelocity: 2400

            delegate: Item {
                id: notifRow
                required property int index
                property var entry: root.notificationHistory[index] || {}
                readonly property bool isExpanded: root.expandedIndex === index
                readonly property bool hasBody: (entry.body || "") !== "" && entry.body !== entry.summary
                width: ListView.view.width
                height: isExpanded ? (hasBody ? 92 : 64) : 56

                property real dragX: 0
                property bool dragging: false
                property bool pendingDismiss: false
                readonly property real maxSwipe: -88
                readonly property real dismissThreshold: -56

                Behavior on height {
                    NumberAnimation { duration: 220; easing.type: Easing.OutQuart }
                }

                Behavior on dragX {
                    enabled: !notifRow.dragging
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutQuart
                        onRunningChanged: {
                            if (!running && notifRow.pendingDismiss) {
                                notifRow.pendingDismiss = false;
                                root.dismissRequested(notifRow.entry.id);
                            }
                        }
                    }
                }

                function relativeTime() {
                    if (!entry.timestamp) return ""
                    const diffMs = Date.now() - entry.timestamp
                    const mins = Math.floor(diffMs / 60000)
                    if (mins < 1) return "now"
                    if (mins < 60) return mins + "m ago"
                    const hrs = Math.floor(mins / 60)
                    if (hrs < 24) return hrs + "h ago"
                    return Math.floor(hrs / 24) + "d ago"
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(0, -notifRow.dragX)
                    radius: 12
                    clip: true
                    color: StyleTokens.danger
                    visible: notifRow.dragX < -4

                    Text {
                        renderType: Text.NativeRendering
                        anchors.right: parent.right
                        anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf1f8"
                        font.family: root.iconFontFamily
                        font.pixelSize: 15
                        color: StyleTokens.white
                        opacity: Math.min(1, -notifRow.dragX / -notifRow.dismissThreshold)
                    }
                }

                Rectangle {
                    id: notifCard
                    x: notifRow.dragX
                    y: 0
                    width: parent.width
                    height: parent.height
                    radius: 12
                    clip: true

                    color: notifCardMouse.containsMouse || notifRow.isExpanded
       			? Qt.rgba(1,1,1,0.09)
     			  : Qt.rgba(1,1,1,0.05)

                    border.width: IslandMotion.surfaceBorderWidth
                    border.color: IslandMotion.surfaceBorderColor

                    Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }

                    Item {
                        width: 26; height: 26
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 9

                        Image {
                            id: notifCenterIconImg
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true; cache: true
                            visible: status === Image.Ready
                            source: notifRow.entry.appIcon && notifRow.entry.appIcon !== ""
                                    ? "file://" + notifRow.entry.appIcon : ""
                        }
                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            visible: !notifCenterIconImg.visible
                            text: "\uf0f3"
                            font.family: root.iconFontFamily
                            font.pixelSize: 13
                            color: IslandMotion.textFaint
                            opacity: 0.6
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 9
                        text: notifRow.relativeTime()
                        color: IslandMotion.textFaint
                        font.pixelSize: 9
                        font.family: root.textFontFamily
                        opacity: 0.6
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 44
                        anchors.rightMargin: 12
                        anchors.topMargin: 6
                        spacing: 2

                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            text: notifRow.entry.appName || "Notification"
                            color: IslandMotion.textFaint
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.family: root.textFontFamily
                            elide: Text.ElideRight
                        }
                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            text: notifRow.entry.summary || ""
                            color: IslandMotion.textPrimary
                            font.pixelSize: 12
                            font.family: root.textFontFamily
                            elide: notifRow.isExpanded ? Text.ElideNone : Text.ElideRight
                            wrapMode: notifRow.isExpanded ? Text.WordWrap : Text.NoWrap
                            maximumLineCount: notifRow.isExpanded ? 2 : 1
                        }
                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            visible: notifRow.isExpanded && notifRow.hasBody
                            text: notifRow.entry.body || ""
                            color: IslandMotion.textFaint
                            opacity: 0.85
                            font.pixelSize: 10
                            font.family: root.textFontFamily
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: notifCardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        property real pressX: 0
                        property bool moved: false

                        onPressed: function(mouse) {
                            pressX = mouse.x;
                            moved = false;
                            notifRow.dragging = true;
                        }

                        onPositionChanged: function(mouse) {
                            if (!pressed) return;
                            let delta = mouse.x - pressX;
                            if (delta > 0) delta = 0;
                            if (!moved && Math.abs(delta) > 4) moved = true;
                            if (moved) notifRow.dragX = Math.max(notifRow.maxSwipe, delta);
                        }

                        onReleased: {
                            notifRow.dragging = false;

                            if (moved) {
                                if (notifRow.dragX <= notifRow.dismissThreshold) {
                                    notifRow.pendingDismiss = true;
                                    notifRow.dragX = -notifRow.width;
                                } else {
                                    notifRow.dragX = 0;
                                }
                                return;
                            }

                            root.expandedIndex = notifRow.isExpanded ? -1 : index;
                        }

                        onCanceled: {
                            notifRow.dragging = false;
                            notifRow.dragX = 0;
                        }
                    }
                }
            }
        }
    }
}
