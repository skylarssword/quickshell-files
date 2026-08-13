import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import IslandBackend
import "qml/shared"

PanelWindow {
    id: root

    property bool pickerVisible: false
    readonly property string iconFontFamily: UserConfig.iconFontFamily

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: -1
    visible: pickerVisible
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: pickerVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    focusable: pickerVisible

    mask: Region {
        Region {
            x: 0; y: 0
            width:  pickerVisible ? root.width  : 0
            height: pickerVisible ? root.height : 0
        }
    }

    IpcHandler {
        target: "wallpaper-picker"
        function toggle(): void { root.pickerVisible = !root.pickerVisible }
        function open(): void   { root.pickerVisible = true }
        function close(): void  { root.pickerVisible = false }
    }

    onPickerVisibleChanged: {
        if (pickerVisible) {
            loadAppearanceState()
            focusTimer.restart()
            if (allWallpapers.length === 0) {
                staticScanner.running = true
                videoScanner.running  = true
            }
        }
    }

    // ── Appearance state ─────────────────────────────────────────────────
    property real capsuleOpacity: 0.20
    property bool capsuleUseWalColor: false
    property var  capsuleWalColors: []
    property int  capsuleWalColorIndex: 0
    readonly property color capsuleWalColor:
        (capsuleWalColorIndex >= 0 && capsuleWalColorIndex < capsuleWalColors.length)
            ? capsuleWalColors[capsuleWalColorIndex] : "#000000"
    property bool gamemodeActive: false

    function loadAppearanceState() {
        appearanceLoader.running = true
        walColorLoader.running   = true
        gamemodeLoader.running   = true
    }

    Process {
        id: appearanceLoader
        property string _buf: ""
        command: ["bash", "-c", "cat \"$HOME/.cache/quickshell/appearance-settings.json\" 2>/dev/null"]
        stdout: SplitParser { onRead: appearanceLoader._buf += data }
        onRunningChanged: {
            if (!running) {
                const raw = appearanceLoader._buf.trim()
                appearanceLoader._buf = ""
                if (raw.length > 0) {
                    try {
                        const parsed = JSON.parse(raw)
                        if (typeof parsed.capsuleOpacity       === "number")  root.capsuleOpacity       = parsed.capsuleOpacity
                        if (typeof parsed.capsuleUseWalColor   === "boolean") root.capsuleUseWalColor   = parsed.capsuleUseWalColor
                        if (typeof parsed.capsuleWalColorIndex === "number")  root.capsuleWalColorIndex = parsed.capsuleWalColorIndex
                    } catch (e) {}
                }
            }
        }
    }

    Process {
        id: walColorLoader
        property string _buf: ""
        command: ["bash", "-c", "cat \"$HOME/.cache/wal/colors\" 2>/dev/null"]
        stdout: SplitParser { onRead: walColorLoader._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const lines = walColorLoader._buf.trim().split("\n")
                walColorLoader._buf = ""
                const parsed = []
                for (let i = 0; i < lines.length; i++) {
                    const raw = lines[i].trim()
                    if (/^#?[0-9A-Fa-f]{6}$/.test(raw))
                        parsed.push(raw.startsWith("#") ? raw : ("#" + raw))
                }
                if (parsed.length > 0) {
                    root.capsuleWalColors = parsed
                    if (root.capsuleWalColorIndex >= parsed.length)
                        root.capsuleWalColorIndex = 0
                }
            }
        }
    }

    Process {
        id: gamemodeLoader
        property string _buf: ""
        command: ["bash", "-c",
            "[ -f \"$HOME/.config/ml4w/settings/gamemode-enabled\" ] && echo 1 || echo 0"]
        stdout: SplitParser { onRead: gamemodeLoader._buf += data }
        onRunningChanged: {
            if (!running) {
                root.gamemodeActive = gamemodeLoader._buf.trim() === "1"
                gamemodeLoader._buf = ""
            }
        }
    }

    // Focus: give it a tick so the window is mapped first
    Timer {
        id: focusTimer
        interval: 50; repeat: false
        onTriggered: {
            focusScope.forceActiveFocus()
            carousel.forceActiveFocus()
        }
    }

    // ── Config ───────────────────────────────────────────────────────────
    readonly property string wallpaperFolder: IslandConfiguration.wallpaperFolder
    readonly property string thumbCacheDir:   IslandConfiguration.thumbCacheDir
    readonly property string postCommand:     IslandConfiguration.postCommand
    readonly property string colorCacheFile:  IslandConfiguration.colorCacheFile

    readonly property string awwwFlags:
        "--transition-type grow --transition-step 90 --transition-angle 0 " +
        "--transition-duration 2 --transition-fps 60"

    // ── State ────────────────────────────────────────────────────────────
    property var staticWalls:   []
    property var videoWalls:    []
    property var allWallpapers: staticWalls.concat(videoWalls)
    property var thumbMap:      ({})
    property var colorMap:      ({})
    property string selectedBucket: "all"
    property string mediaFilter:    "all"

    property var filteredWallpapers: {
        let base = allWallpapers
        if      (mediaFilter === "photo") base = base.filter(p => !root.isVideo(p))
        else if (mediaFilter === "video") base = base.filter(p =>  root.isVideo(p))
        if (selectedBucket === "all") return base
        return base.filter(p => bucketFor(colorMap[p]) === selectedBucket)
    }

    function cycleMediaFilter() {
        const order = ["all", "photo", "video"]
        mediaFilter = order[(order.indexOf(mediaFilter) + 1) % order.length]
    }

    property string currentWallpaper:    ""
    property string lastStaticWallpaper: ""
    property string _staticBuf: ""
    property string _videoBuf:  ""

    function isVideo(path) { return /\.(mp4|mkv|webm|mov|avi|gif)$/i.test(path) }

    // ── Scanners ─────────────────────────────────────────────────────────
    Process {
        id: staticScanner
        command: ["bash", "-c",
            "find \"" + root.wallpaperFolder + "\" -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
            "-o -iname '*.webp' -o -iname '*.bmp' \\) 2>/dev/null | sort"]
        stdout: SplitParser { onRead: root._staticBuf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                root.staticWalls = root._staticBuf.trim().split("\n").filter(l => l.trim() !== "")
                root._staticBuf  = ""
                Qt.callLater(root.rebuildThumbMap)
            }
        }
    }

    Process {
        id: videoScanner
        command: ["bash", "-c",
            "find \"" + root.wallpaperFolder + "\" -type f " +
            "\\( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' " +
            "-o -iname '*.mov' -o -iname '*.avi' -o -iname '*.gif' \\) 2>/dev/null | sort"]
        stdout: SplitParser { onRead: root._videoBuf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                root.videoWalls = root._videoBuf.trim().split("\n").filter(l => l.trim() !== "")
                root._videoBuf  = ""
                Qt.callLater(root.rebuildThumbMap)
            }
        }
    }

    // ── Thumb map ────────────────────────────────────────────────────────
    Process {
        id: thumbMapProc
        property string _buf: ""
        stdout: SplitParser { onRead: thumbMapProc._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                let lines = thumbMapProc._buf.trim().split("\n").filter(l => l.trim() !== "")
                let map = {}
                for (let line of lines) {
                    let spaceIdx = line.indexOf("  ")
                    if (spaceIdx < 0) continue
                    let hash = line.substring(0, spaceIdx).trim()
                    let path = line.substring(spaceIdx + 2).trim()
                    map[path] = root.thumbCacheDir + "/" + hash + ".png"
                }
                root.thumbMap     = map
                thumbMapProc._buf = ""
                root.queueMissingThumbs()
            }
        }
    }

    function rebuildThumbMap() {
        let all = root.allWallpapers
        if (all.length === 0) return
        let paths = all.map(p => JSON.stringify(p)).join(" ")
        thumbMapProc.command = ["bash", "-c",
            "for f in " + paths + "; do " +
            "r=$(readlink -f \"$f\"); " +
            "h=$(printf '%s' \"$r\" | md5sum | cut -d' ' -f1); " +
            "echo \"$h  $f\"; done"]
        thumbMapProc.running = true
    }

    property var  missingThumbQueue: []
    property bool thumbGenBusy: false

    function queueMissingThumbs() {
        let queue = []
        for (let path of root.allWallpapers) {
            let target = root.thumbMap[path]
            if (!target || target === "") continue
            queue.push({ path: path, target: target })
        }
        root.missingThumbQueue = queue
        processNextMissingThumb()
    }

    function processNextMissingThumb() {
        if (root.thumbGenBusy) return
        if (root.missingThumbQueue.length === 0) { root.loadColorCache(); return }
        let item = root.missingThumbQueue[0]
        root.missingThumbQueue = root.missingThumbQueue.slice(1)
        thumbGenProc.command = ["bash", "-c",
            "[ -f " + JSON.stringify(item.target) + " ] || " +
            "ffmpeg -y -i " + JSON.stringify(item.path) +
            " -vframes 1 -vf scale=1280:-1 -f image2 " +
            JSON.stringify(item.target) + " >/dev/null 2>&1"]
        root.thumbGenBusy = true
        thumbGenProc.running = true
    }

    Process {
        id: thumbGenProc
        onRunningChanged: {
            if (!running) { root.thumbGenBusy = false; root.processNextMissingThumb() }
        }
    }

    // ── Color cache ──────────────────────────────────────────────────────
    Process {
        id: colorCacheLoader
        property string _buf: ""
        command: ["bash", "-c", "cat " + JSON.stringify(root.colorCacheFile) + " 2>/dev/null"]
        stdout: SplitParser { onRead: colorCacheLoader._buf += data }
        onRunningChanged: {
            if (!running) {
                let raw = colorCacheLoader._buf.trim()
                colorCacheLoader._buf = ""
                if (raw.length > 0) {
                    try { root.colorMap = JSON.parse(raw) } catch (e) { root.colorMap = {} }
                }
                root.queueMissingColors()
            }
        }
    }

    function loadColorCache() { colorCacheLoader.running = true }

    property var  missingColorQueue: []
    property bool colorGenBusy: false

    function queueMissingColors() {
        let queue = []
        for (let path of root.allWallpapers) {
            if (root.colorMap[path]) continue
            let target = root.thumbMap[path]
            if (!target || target === "") continue
            queue.push({ path: path, target: target })
        }
        root.missingColorQueue = queue
        processNextMissingColor()
    }

    function processNextMissingColor() {
        if (root.colorGenBusy) return
        if (root.missingColorQueue.length === 0) { saveColorCacheTimer.restart(); return }
        let item = root.missingColorQueue[0]
        root.missingColorQueue = root.missingColorQueue.slice(1)
        colorExtractProc.pendingPath = item.path
        colorExtractProc.command = ["bash", "-c",
            "convert " + JSON.stringify(item.target) + " -resize 1x1 txt:- 2>/dev/null | " +
            "tail -1 | grep -oE '#[0-9A-Fa-f]{6}' | head -1"]
        root.colorGenBusy = true
        colorExtractProc.running = true
    }

    Process {
        id: colorExtractProc
        property string pendingPath: ""
        property string _buf: ""
        stdout: SplitParser { onRead: colorExtractProc._buf += data }
        onRunningChanged: {
            if (!running) {
                let hex = colorExtractProc._buf.trim()
                colorExtractProc._buf = ""
                if (hex !== "") {
                    let updated = Object.assign({}, root.colorMap)
                    updated[colorExtractProc.pendingPath] = hex
                    root.colorMap = updated
                }
                root.colorGenBusy = false
                root.processNextMissingColor()
            }
        }
    }

    Timer { id: saveColorCacheTimer; interval: 300; repeat: false; onTriggered: colorCacheSaveExec.running = true }

    Process {
        id: colorCacheSaveExec
        command: ["bash", "-c",
            "mkdir -p \"$(dirname " + JSON.stringify(root.colorCacheFile) + ")\" && printf '%s' '" +
            JSON.stringify(root.colorMap) + "' > " + JSON.stringify(root.colorCacheFile)]
    }

    // ── Color bucketing ──────────────────────────────────────────────────
    function bucketFor(hex) {
        if (!hex) return "mono"
        let m = /^#?([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})$/.exec(hex)
        if (!m) return "mono"
        let r = parseInt(m[1],16)/255, g = parseInt(m[2],16)/255, b = parseInt(m[3],16)/255
        let max = Math.max(r,g,b), min = Math.min(r,g,b)
        let s = max === 0 ? 0 : (max-min)/max
        if (s < 0.15 || max < 0.12) return "mono"
        let h = 0, d = max-min
        if (d !== 0) {
            if      (max===r) h = 60*(((g-b)/d)%6)
            else if (max===g) h = 60*((b-r)/d+2)
            else              h = 60*((r-g)/d+4)
        }
        if (h < 0) h += 360
        if (h<15||h>=345) return "red";   if (h<45)  return "orange"
        if (h<70)  return "yellow";        if (h<170) return "green"
        if (h<255) return "blue";          if (h<290) return "purple"
        return "pink"
    }

    // ── Wallpaper setters ────────────────────────────────────────────────
    Process { id: awwwProc }
    function setStaticWallpaper(path) {
        root.currentWallpaper = path; root.lastStaticWallpaper = path
        awwwProc.command = ["bash", "-c",
            "pkill -x mpvpaper 2>/dev/null\n" +
            "awww img " + JSON.stringify(path) + " " + root.awwwFlags + " && " +
            root.postCommand + " " + JSON.stringify(path) + " --skip > /dev/null 2>&1"]
        awwwProc.running = true
    }

    Process { id: mpvProc }
    function setVideoWallpaper(path) {
        root.currentWallpaper = path
        mpvProc.command = ["bash", "-c",
            "pkill -x mpvpaper 2>/dev/null\nsleep 0.15\n" +
            "SOCKET=/tmp/ambxst_mpv_socket_ALL\n" +
            "MPV_OPTS=\"no-audio loop hwdec=auto scale=bilinear interpolation=no " +
            "video-sync=display-resample panscan=1.0 video-scale-x=1.0 " +
            "video-scale-y=1.0 load-scripts=no input-ipc-server=$SOCKET\"\n" +
            "nohup mpvpaper -o \"$MPV_OPTS\" ALL " + JSON.stringify(path) +
            " >/tmp/mpvpaper.log 2>&1 &\n" +
            root.postCommand + " " + JSON.stringify(path) + " --skip > /dev/null 2>&1 &"]
        mpvProc.running = true
    }

    function applySelected() {
        if (carousel.currentIndex < 0 || carousel.currentIndex >= root.filteredWallpapers.length) return
        let path = root.filteredWallpapers[carousel.currentIndex]
        if (root.isVideo(path)) root.setVideoWallpaper(path)
        else root.setStaticWallpaper(path)
    }

    function applyRandom() {
        let list = root.filteredWallpapers
        if (list.length === 0) return
        let idx = Math.floor(Math.random() * list.length)
        carousel.currentIndex = idx
        let path = list[idx]
        if (root.isVideo(path)) root.setVideoWallpaper(path)
        else root.setStaticWallpaper(path)
    }

    // ── UI constants ─────────────────────────────────────────────────────
    // cellWidth is the LIST item slot width (selected card fills it at scale 1.0)
    // cellHeight is fixed and independent of carousel height — cards are tall rectangles
    // The carousel itself fills available vertical space; cards are vertically centered within
    readonly property int cellWidth:       1100  // wider, more horizontal
    readonly property int cellHeight:      440   // flatter height ratio
    readonly property int skew:            70    // aggressive parallelogram slant
    readonly property int bottomBarHeight: 64

    // ── Full-screen backdrop ─────────────────────────────────────────────
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: root.gamemodeActive
            ? Qt.rgba(0,0,0,0.96)
            : (root.capsuleUseWalColor
                ? Qt.rgba(root.capsuleWalColor.r, root.capsuleWalColor.g,
                          root.capsuleWalColor.b, Math.min(root.capsuleOpacity + 0.60, 0.92))
                : Qt.rgba(0,0,0,0.82))
        opacity: root.pickerVisible ? 1 : 0
        visible: opacity > 0.01
        Behavior on color   { ColorAnimation  { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove } }
        Behavior on opacity { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeOut } }

        FocusScope {
            id: focusScope
            anchors.fill: parent
            focus: root.pickerVisible       // ← keeps focus while open
            activeFocusOnTab: false

            Keys.onEscapePressed: root.pickerVisible = false

            // ── Carousel ─────────────────────────────────────────────────
            ListView {
                id: carousel
                anchors {
                    left: parent.left; right: parent.right
                    top: parent.top
                    bottom: bottomBar.top
                }
                visible: root.filteredWallpapers.length > 0
                model: root.filteredWallpapers.length
                orientation: ListView.Horizontal
                spacing: -620
                clip: false
                focus: true                 // ← carousel gets key events

                highlightFollowsCurrentItem: true
                highlightMoveDuration: 280
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: width / 2 - root.cellWidth / 2
                preferredHighlightEnd:   width / 2 + root.cellWidth / 2
                snapMode: ListView.SnapToItem
                displayMarginBeginning: root.cellWidth * 4
                displayMarginEnd:       root.cellWidth * 4

                onModelChanged: currentIndex = 0

                Keys.onLeftPressed:   if (currentIndex > 0)          currentIndex--
                Keys.onRightPressed:  if (currentIndex < count - 1)  currentIndex++
                Keys.onReturnPressed: root.applySelected()
                Keys.onTabPressed:    root.cycleMediaFilter()

                readonly property var bucketKeyOrder: ["all","red","orange","yellow","green","blue","purple","pink","mono"]
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_R) { root.applyRandom(); event.accepted = true; return }
                    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        const idx = event.key - Qt.Key_1
                        if (idx < carousel.bucketKeyOrder.length) {
                            root.selectedBucket = carousel.bucketKeyOrder[idx]
                            event.accepted = true
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    propagateComposedEvents: true
                    z: -1
                    onWheel: (wheel) => {
                        wheel.accepted = true
                        if (wheel.angleDelta.y > 0 && carousel.currentIndex > 0)
                            carousel.currentIndex--
                        else if (wheel.angleDelta.y < 0 && carousel.currentIndex < carousel.count - 1)
                            carousel.currentIndex++
                    }
                }

                delegate: Item {
                    id: cell
                    width: root.cellWidth
                    height: carousel.height      // slot fills carousel height

                    required property int index
                    property bool   isCurrent:          ListView.isCurrentItem
                    property string wallPath:           root.filteredWallpapers[index] || ""
                    property bool   isCurrentWallpaper: root.currentWallpaper === wallPath
                    property string thumbSrc: {
                        let cached = root.thumbMap[wallPath]
                        if (cached && cached !== "") return "file://" + cached
                        if (!root.isVideo(wallPath))  return "file://" + wallPath
                        return ""
                    }

                    // dist-based scale — independent of carousel height
                    property int  dist:        Math.abs(index - carousel.currentIndex)
                    property real cardScale:   dist === 0 ? 1.0 : dist === 1 ? 0.52 : 0.32
                    property real cardOpacity: dist === 0 ? 1.0 : dist === 1 ? 0.70 : 0.45
                    z: 10 - cell.dist

                    // The actual card — fixed height, centered vertically in the slot
                    Item {
                        id: shapeRoot
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter:   parent.verticalCenter
                        width:  root.cellWidth - 12
                        height: root.cellHeight          // ← fixed tall height, not carousel.height

                        scale:   cell.cardScale
                        opacity: cell.cardOpacity
                        Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 240 } }

                        Canvas {
                            id: mask
                            anchors.fill: parent; visible: false
                            onPaint: {
                                let ctx = getContext("2d"); ctx.reset()
                                let s = root.skew
                                ctx.beginPath()
                                ctx.moveTo(s,0); ctx.lineTo(width,0)
                                ctx.lineTo(width-s,height); ctx.lineTo(0,height)
                                ctx.closePath(); ctx.fillStyle = "white"; ctx.fill()
                            }
                            onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()
                        }

                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: OpacityMask { maskSource: mask }

                            Rectangle { anchors.fill: parent; color: Qt.rgba(1,1,1,0.04) }

                            Image {
                                anchors.fill: parent
                                source: cell.thumbSrc
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true; smooth: true; mipmap: true; cache: true
                                sourceSize.width:  1200
                                sourceSize.height: 750
                                visible: status === Image.Ready
                            }

                            Rectangle {
                                anchors.fill: parent; color: Qt.rgba(1,1,1,0.03)
                                visible: cell.thumbSrc === ""
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left; anchors.right: parent.right
                                height: 28; color: Qt.rgba(0.4, 0.9, 0.55, 0.85)
                                visible: cell.isCurrentWallpaper
                                Text {
                                    anchors.centerIn: parent; text: "ACTIVE"
                                    color: "white"; font.pixelSize: 13
                                    font.family: root.iconFontFamily; font.weight: Font.Bold
                                }
                            }
                        }

                        // Hairline border always
                        Canvas {
                            id: hairlineOutline; anchors.fill: parent
                            onPaint: {
                                let ctx = getContext("2d"); ctx.reset()
                                let s = root.skew
                                ctx.beginPath()
                                ctx.moveTo(s,0); ctx.lineTo(width,0)
                                ctx.lineTo(width-s,height); ctx.lineTo(0,height)
                                ctx.closePath()
                                ctx.lineWidth = IslandMotion.surfaceBorderWidth
                                ctx.strokeStyle = IslandMotion.surfaceBorderColor
                                ctx.stroke()
                            }
                            onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()
                        }

                        // Selection outline (current only)
                        Canvas {
                            id: outline; anchors.fill: parent
                            property real ow: cell.isCurrent ? 2.5 : 0
                            onOwChanged: requestPaint()
                            onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()
                            onPaint: {
                                let ctx = getContext("2d"); ctx.reset()
                                if (ow <= 0) return
                                let s = root.skew
                                ctx.beginPath()
                                ctx.moveTo(s,0); ctx.lineTo(width,0)
                                ctx.lineTo(width-s,height); ctx.lineTo(0,height)
                                ctx.closePath()
                                ctx.lineWidth = ow
                                ctx.strokeStyle = Qt.rgba(1.0,1.0,1.0,0.90)
                                ctx.stroke()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (cell.isCurrent) root.applySelected()
                                else carousel.currentIndex = cell.index
                            }
                        }
                    }
                }
            }

            // Empty / loading placeholder (sits in same space as carousel)
            Text {
                anchors {
                    left: parent.left; right: parent.right
                    top: parent.top; bottom: bottomBar.top
                    topMargin: 0
                }
                visible: root.filteredWallpapers.length === 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment:   Text.AlignVCenter
                text: staticScanner.running || videoScanner.running ? "\uf110" : "\uf03e"
                font.pixelSize: 48; color: "white"; opacity: 0.15
                NumberAnimation on rotation {
                    from: 0; to: 360; duration: 900; loops: Animation.Infinite
                    running: staticScanner.running || videoScanner.running
                }
            }

            // ── Bottom bar ────────────────────────────────────────────────
            Item {
                id: bottomBar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: root.bottomBarHeight

                // Media filter (left)
                Rectangle {
                    id: mediaFilterButton
                    width: 36; height: 36; radius: 18
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 28
                    color: mediaFilterMouse.containsMouse ? Qt.rgba(1,1,1,0.22) : Qt.rgba(1,1,1,0.10)
                    border.color: Qt.rgba(1,1,1,0.35); border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: mediaFilterMouse.pressed ? 0.92 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                    Text {
                        anchors.centerIn: parent
                        text: root.mediaFilter === "photo" ? "\uf03e"
                            : root.mediaFilter === "video" ? "\uf144" : "\uf00a"
                        font.family: root.iconFontFamily; font.pixelSize: 14
                        color: "white"; opacity: 0.85
                    }
                    MouseArea {
                        id: mediaFilterMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: root.cycleMediaFilter()
                    }
                }

                // Color swatches (center)
                Row {
                    anchors.centerIn: parent; spacing: 12
                    Repeater {
                        model: [
                            { key: "all",    color: "transparent" },
                            { key: "red",    color: "#e53935" },
                            { key: "orange", color: "#fb8c00" },
                            { key: "yellow", color: "#fdd835" },
                            { key: "green",  color: "#43a047" },
                            { key: "blue",   color: "#1e88e5" },
                            { key: "purple", color: "#8e24aa" },
                            { key: "pink",   color: "#d81b60" },
                            { key: "mono",   color: "#9e9e9e" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 30; radius: 15
                            color: modelData.key === "all" ? "transparent" : modelData.color
                            border.width: root.selectedBucket === modelData.key ? 3 : 1
                            border.color: root.selectedBucket === modelData.key
                                          ? Qt.rgba(1,1,1,0.95) : Qt.rgba(1,1,1,0.25)
                            Behavior on border.width { NumberAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent; visible: modelData.key === "all"
                                text: "\u2715"; color: "white"; opacity: 0.6; font.pixelSize: 11
                            }
                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedBucket = modelData.key
                            }
                        }
                    }
                }

                // Random (right)
                Rectangle {
                    id: randomButton
                    width: 36; height: 36; radius: 18
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 28
                    color: randomButtonMouse.containsMouse ? Qt.rgba(1,1,1,0.22) : Qt.rgba(1,1,1,0.10)
                    border.color: Qt.rgba(1,1,1,0.35); border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: randomButtonMouse.pressed ? 0.92 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                    Text {
                        anchors.centerIn: parent; text: "\uf522"
                        font.family: root.iconFontFamily; font.pixelSize: 14
                        color: "white"; opacity: 0.85
                    }
                    MouseArea {
                        id: randomButtonMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: root.applyRandom()
                    }
                }
            }
        }
    }
}
