import QtQuick

// plain transport icon button (no bubble); put the icon inside it.
// hover brightens, press shrinks slightly; the tap area is separate from the shrinking icon.
Item {
    id: tbtn
    property real iconOpacity: 1.0
    default property alias slotData: tslot.data
    signal activated()
    width: 28; height: 28
    anchors.verticalCenter: parent.verticalCenter

    Item {
        id: tslot
        anchors.fill: parent
        opacity: tma.pressed ? tbtn.iconOpacity * 0.6
               : (tma.containsMouse ? Math.min(1, tbtn.iconOpacity + 0.25) : tbtn.iconOpacity)
        scale: tma.pressed ? 0.8 : 1.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        // springs back past 1.0 on release
        Behavior on scale   { NumberAnimation { duration: tma.pressed ? 90 : 340
                                                 easing.type: tma.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 3.2 } }
    }
    MouseArea {
        id: tma
        anchors.fill: parent; anchors.margins: -8
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tbtn.activated()
    }
}
