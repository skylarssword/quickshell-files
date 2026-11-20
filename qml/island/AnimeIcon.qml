import QtQuick

// drawn icon for the Anime Hub (2x canvas shown at 0.5 so it stays crisp)
Item {
    id: ico
    property string kind: "home"
    property real   sz: 18
    property color  col: "white"
    width: sz; height: sz
    Canvas {
        anchors.centerIn: parent
        width: ico.sz * 2; height: ico.sz * 2
        scale: 0.5; smooth: true
        property string k: ico.kind
        property color  c: ico.col
        onKChanged: requestPaint()
        onCChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, width, height)
            ctx.setTransform(width / 20, 0, 0, height / 20, 0, 0)
            ctx.strokeStyle = c; ctx.fillStyle = c
            ctx.lineWidth = 1.8; ctx.lineCap = "round"; ctx.lineJoin = "round"
            switch (k) {
            case "home":
                ctx.beginPath(); ctx.moveTo(3, 10); ctx.lineTo(10, 3.5); ctx.lineTo(17, 10); ctx.lineTo(17, 17)
                ctx.lineTo(12, 17); ctx.lineTo(12, 12); ctx.lineTo(8, 12); ctx.lineTo(8, 17); ctx.lineTo(3, 17)
                ctx.closePath(); ctx.fill(); break
            case "search":
                ctx.beginPath(); ctx.arc(8.5, 8.5, 5.6, 0, 6.283); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(12.7, 12.7); ctx.lineTo(17, 17); ctx.stroke(); break
            case "list":
                for (let i = 0; i < 3; i++) {
                    ctx.beginPath(); ctx.moveTo(8, 5 + i * 5); ctx.lineTo(17, 5 + i * 5); ctx.stroke()
                    ctx.beginPath(); ctx.arc(3.8, 5 + i * 5, 1.2, 0, 6.283); ctx.fill()
                }
                break
            case "play":
                ctx.beginPath(); ctx.moveTo(5, 3.2); ctx.lineTo(16.5, 10); ctx.lineTo(5, 16.8); ctx.closePath(); ctx.fill(); break
            case "clock":
                ctx.beginPath(); ctx.arc(10, 10, 7.3, 0, 6.283); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(10, 5.5); ctx.lineTo(10, 10); ctx.lineTo(13.5, 12); ctx.stroke(); break
            case "trash":
                ctx.beginPath(); ctx.moveTo(4, 6); ctx.lineTo(16, 6); ctx.moveTo(8, 6); ctx.lineTo(8, 3.5); ctx.lineTo(12, 3.5); ctx.lineTo(12, 6); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(5.5, 6); ctx.lineTo(6.5, 16.5); ctx.lineTo(13.5, 16.5); ctx.lineTo(14.5, 6); ctx.stroke(); break
            }
        }
    }
}
