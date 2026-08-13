import QtQuick.Controls
import Quickshell.Io
import QtQuick
import Quickshell
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import "../shared"

// Folder, awww flags, post-command, and thumb cache all match waypaper config.
// it now lives directly inside the parent search capsule (no nested box).

Item {
    id: root

    width: capsuleWidth
    height: capsuleHeight
    implicitWidth: capsuleWidth
    implicitHeight: capsuleHeight

    property string iconFontFamily: ""
    property string textFontFamily: ""

    readonly property int capsuleWidth: viewMode === "quick" ? quickCapsuleWidth : 760
    readonly property int headerHeight: 40
    readonly property int footerHeight: 36
    readonly property int gridRowCount: 2
    readonly property int thumbCellSize: 64   // smaller thumbs, matches app-grid icon cell size
    readonly property int gridCols: Math.max(4, Math.floor((760 - 20) / thumbCellSize))
    readonly property int gridHeight: (thumbCellSize * gridRowCount) + 6
    readonly property int capsuleHeight: viewMode === "quick"
        ? quickHeaderHeight + quickCarouselHeight + quickFooterHeight
        : (headerHeight + gridHeight + footerHeight)

    // ── View mode: "quick" (carousel) or "grid" (existing full grid) ────
    property string viewMode: "quick"
    readonly property int quickCapsuleWidth: 680     // was 620 — more room for the larger carousel below
    readonly property int quickHeaderHeight: 48   // was 40
    readonly property int quickCarouselHeight: 250   // was 220
    readonly property int quickFooterHeight: 36   // was 30
    readonly property int quickCellWidth: 380        // was 340
    readonly property int quickCellHeight: 168        // was 150 (keeps the same ~2.27:1 aspect ratio)
    readonly property int quickSkew: 26
    readonly property real quickNeighborScale: 0.74

    onViewModeChanged: viewModeFocusTimer.restart()

    Timer {
        id: viewModeFocusTimer
        interval: 0
        repeat: false
        onTriggered: root.focusInput()
    }

    signal closeRequested()

    // ── Config — paths from IslandConfiguration singleton ────────────────
    readonly property string wallpaperFolder: IslandConfiguration.wallpaperFolder
    readonly property string thumbCacheDir:   IslandConfiguration.thumbCacheDir
    readonly property string postCommand:     IslandConfiguration.postCommand

    readonly property string awwwFlags:
        "--transition-type grow " +
        "--transition-step 90 " +
        "--transition-angle 0 " +
        "--transition-duration 2 " +
        "--transition-fps 60"

    // ── State ─────────────────────────────────────────────────────────────
    property int    activeTab:        0    // 0 = static, 1 = video
    property var    staticWalls:      []
    property var    videoWalls:       []
    property string searchText:       ""
    property int    selectedIndex:   -1
    property string currentWallpaper: ""
    property string lastStaticWallpaper: ""
    property string statusMessage:    ""
    property bool   statusOk:         true

    property string _staticBuf: ""
    property string _videoBuf:  ""

    property var filteredStatic: {
        if (searchText.trim() === "") return staticWalls
        let q = searchText.toLowerCase()
        return staticWalls.filter(p => p.split("/").pop().toLowerCase().includes(q))
    }
    property var filteredVideo: {
        if (searchText.trim() === "") return videoWalls
        let q = searchText.toLowerCase()
        return videoWalls.filter(p => p.split("/").pop().toLowerCase().includes(q))
    }
    property var activeList: activeTab === 0 ? filteredStatic : filteredVideo

    // ── Boot ─────────────────────────────────────────────────────────────
    Component.onCompleted: {
        staticScanner.running = true
        videoScanner.running  = true
        focusInput()
    }

    function focusInput() {
        if (root.viewMode === "quick") {
            if (quickCarousel) quickCarousel.forceActiveFocus()
        } else {
            searchInput.forceActiveFocus()
        }
    }
    function inputHasFocus() {
        if (root.viewMode === "quick")
            return quickCarousel && quickCarousel.activeFocus
        return searchInput.activeFocus
    }

    function flash(msg, ok) {
        statusMessage = msg
        statusOk = ok !== false
        statusTimer.restart()
    }

    Timer {
        id: statusTimer
        interval: 2400
        repeat: false
        onTriggered: root.statusMessage = ""
    }

    Process {
        id: staticScanner
        command: ["bash", "-c",
            "find \"" + root.wallpaperFolder + "\" -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
            "-o -iname '*.webp' -o -iname '*.bmp' \\) 2>/dev/null | sort"
        ]
        stdout: SplitParser { onRead: root._staticBuf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                root.staticWalls = root._staticBuf.trim().split("\n").filter(l => l.trim() !== "")
                root._staticBuf = ""
            }
        }
    }

    Process {
        id: videoScanner
        command: ["bash", "-c",
            "find \"" + root.wallpaperFolder + "\" -type f " +
            "\\( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' " +
            "-o -iname '*.mov' -o -iname '*.avi' -o -iname '*.gif' \\) " +
            "2>/dev/null | sort"
        ]
        stdout: SplitParser { onRead: root._videoBuf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                root.videoWalls = root._videoBuf.trim().split("\n").filter(l => l.trim() !== "")
                if (root.videoWalls.length > 0)
                    Qt.callLater(rebuildThumbMap)
            }
        }
    }

    // ── Thumbnail path resolver ───────────────────────────────────────────
    property var thumbMap: ({})

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
                root.thumbMap = map
                thumbMapProc._buf = ""
                root.queueMissingVideoThumbs()
            }
        }
    }

    function rebuildThumbMap() {
        let all = root.staticWalls.concat(root.videoWalls)
        if (all.length === 0) return
        let paths = all.map(p => JSON.stringify(p)).join(" ")
        thumbMapProc.command = [
            "bash", "-c",
            "for f in " + paths + "; do " +
            "r=$(readlink -f \"$f\"); " +
            "h=$(printf '%s' \"$r\" | md5sum | cut -d' ' -f1); " +
            "echo \"$h  $f\"; " +
            "done"
        ]
        thumbMapProc.running = true
    }

    property var missingThumbQueue: []
    property bool thumbGenBusy: false

    function queueMissingVideoThumbs() {
        let all = root.videoWalls.concat(root.staticWalls)
        if (all.length === 0) return
        let queue = []
        for (let path of all) {
            let target = root.thumbMap[path]
            if (!target || target === "") continue
            queue.push({ path: path, target: target })
        }
        root.missingThumbQueue = queue
        processNextMissingThumb()
    }

    function processNextMissingThumb() {
        if (root.thumbGenBusy) return
        if (root.missingThumbQueue.length === 0) return
        let item = root.missingThumbQueue[0]
        root.missingThumbQueue = root.missingThumbQueue.slice(1)
        thumbGenProc.targetPath = item.target
        thumbGenProc.command = [
            "bash", "-c",
            "[ -f " + JSON.stringify(item.target) + " ] || " +
            "ffmpeg -y -i " + JSON.stringify(item.path) +
            " -vframes 1 -vf scale=240:-1 -f image2 " +
            JSON.stringify(item.target) + " >/dev/null 2>&1"
        ]
        root.thumbGenBusy = true
        thumbGenProc.running = true
    }
    Process {
        id: thumbGenProc
        property string targetPath: ""
        onRunningChanged: {
            if (!running) {
                root.thumbGenBusy = false
                let updated = Object.assign({}, root.thumbMap)
                root.thumbMap = updated
                processNextMissingThumb()
            }
        }
    }

    onStaticWallsChanged: Qt.callLater(rebuildThumbMap)

    // ── Setters ───────────────────────────────────────────────────────────
    Process {
        id: awwwProc
        onRunningChanged: {
            if (!running) root.flash("Wallpaper applied ✓", true)
        }
    }

    function setStaticWallpaper(path) {
        root.currentWallpaper = path
        root.lastStaticWallpaper = path
        root.flash("Setting wallpaper…", true)
        awwwProc.command = [
            "bash", "-c",
            "pkill -x mpvpaper 2>/dev/null\n" +
            "awww img " + JSON.stringify(path) + " " + root.awwwFlags + " && " +
            root.postCommand + " " + JSON.stringify(path) + " --skip > /dev/null 2>&1"
        ]
        awwwProc.running = true
    }

    Process {
        id: mpvProc
        onRunningChanged: {
            if (!running) root.flash("Video wallpaper applied ✓", true)
        }
    }

    function setVideoWallpaper(path) {
        root.currentWallpaper = path
        root.flash("Starting mpvpaper…", true)
        mpvProc.command = [
            "bash", "-c",
            "pkill -x mpvpaper 2>/dev/null\n" +
            "sleep 0.15\n" +
            "SOCKET=/tmp/ambxst_mpv_socket_ALL\n" +
            "MPV_OPTS=\"no-audio loop hwdec=auto scale=bilinear interpolation=no " +
            "video-sync=display-resample panscan=1.0 video-scale-x=1.0 " +
            "video-scale-y=1.0 load-scripts=no input-ipc-server=$SOCKET\"\n" +
            "nohup mpvpaper -o \"$MPV_OPTS\" ALL " + JSON.stringify(path) +
            " >/tmp/mpvpaper.log 2>&1 &\n" +
            root.postCommand + " " + JSON.stringify(path) + " --skip > /dev/null 2>&1 &"
        ]
        mpvProc.running = true
    }

    Process {
        id: stopAllProc
        onRunningChanged: {
            if (!running) root.flash("Stopped", true)
        }
    }

    function stopAll() {
        let restoreCmd = root.lastStaticWallpaper !== ""
            ? " && awww img " + JSON.stringify(root.lastStaticWallpaper) + " " + root.awwwFlags
            : ""
        stopAllProc.command = [
            "bash", "-c",
            "pkill -x mpvpaper 2>/dev/null" + restoreCmd
        ]
        stopAllProc.running = true
        root.flash("Stopping…", true)
    }

    Process {
        id: randomProc
        onRunningChanged: {
            if (!running) root.flash("Random wallpaper applied ✓", true)
        }
    }

    function applyRandom() {
        let list = root.activeList
        if (list.length === 0) return
        let idx = Math.floor(Math.random() * list.length)
        let path = list[idx]
        root.selectedIndex = idx
        if (root.viewMode === "quick" && quickCarousel)
            quickCarousel.currentIndex = idx
        if (root.activeTab === 0) setStaticWallpaper(path)
        else                      setVideoWallpaper(path)
    }

    function applySelected() {
        if (selectedIndex < 0 || selectedIndex >= root.activeList.length) return
        let path = root.activeList[selectedIndex]
        if (root.activeTab === 0) setStaticWallpaper(path)
        else                      setVideoWallpaper(path)
    }

    function moveSelection(delta) {
        let len = root.activeList.length
        if (len === 0) return
        let next = Math.max(0, Math.min(len - 1, root.selectedIndex + delta))
        root.selectedIndex = next
        wallGrid.positionViewAtIndex(next, GridView.Contain)
    }

    Process { id: openFolderProc }
    Process { id: openConvFolderProc }

    function openTabFolder() {
        let list = root.activeList
        let refPath = ""
        if (root.selectedIndex >= 0 && root.selectedIndex < list.length)
            refPath = list[root.selectedIndex]
        else if (list.length > 0)
            refPath = list[0]

        let targetDir = refPath !== ""
            ? refPath.substring(0, refPath.lastIndexOf("/"))
            : root.wallpaperFolder

        openFolderProc.command = ["xdg-open", targetDir]
        openFolderProc.running = true
    }

    // ── UI ────────────────────────────────────────────────────────────────
    // UI — renders inside parent capsule, no own background

    Column {
        id: gridModeColumn
        anchors.fill: parent
        spacing: 0
        visible: root.viewMode === "grid"

        // ── Header: own search box + tabs ───────────────────────────────
        Item {
            id: topBar
            width: parent.width
            height: root.headerHeight

            Rectangle {
                id: searchPill
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - tabRow.width - 20
                height: 30
                radius: 15
                color: Qt.rgba(1, 1, 1, 0.06)
                border.color: Qt.rgba(1, 1, 1, 0.12)
                border.width: 1

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 6

                    Text {
                        renderType: Text.NativeRendering
                        text: "\uf002"
                        font.family: root.iconFontFamily
                        font.pixelSize: 11
                        color: "white"; opacity: 0.35
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextInput {
                        id: searchInput
                        width: searchPill.width - 56
                        height: 30
                        color: "white"
                        font.pixelSize: 12
                        font.family: root.textFontFamily
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true

                        onTextChanged: {
                            root.searchText = text
                            root.selectedIndex = root.activeList.length > 0 ? 0 : -1
                        }

                        Keys.onEscapePressed: root.closeRequested()
                        Keys.onReturnPressed: root.applySelected()
                        Keys.onLeftPressed:   root.moveSelection(-1)
                        Keys.onRightPressed:  root.moveSelection(1)
                        Keys.onUpPressed:     root.moveSelection(-root.gridCols)
                        Keys.onDownPressed:   root.moveSelection(root.gridCols)
                        Keys.onTabPressed:    root.activeTab = root.activeTab === 0 ? 1 : 0

                        Text {
                            renderType: Text.NativeRendering
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: root.activeTab === 0
                                  ? "Search wallpapers…"
                                  : "Search video wallpapers…"
                            color: "white"; opacity: 0.22
                            font.pixelSize: 12
                            font.family: root.textFontFamily
                            visible: searchInput.text.length === 0
                        }
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf00d"
                    font.family: root.iconFontFamily; font.pixelSize: 10
                    color: "white"
                    opacity: clearMouse.containsMouse ? 0.7 : 0.25
                    visible: searchInput.text.length > 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                    MouseArea {
                        id: clearMouse; anchors.fill: parent
                        anchors.margins: -6; hoverEnabled: true
                        onClicked: { searchInput.text = ""; searchInput.forceActiveFocus() }
                    }
                }
            }

            Row {
                id: tabRow
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                // ── Toggle back to Quickview carousel ───────────────────────
                Rectangle {
                    width: 26; height: 26; radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: toQuickMouse.containsMouse
                           ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.07)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: "\uf066"   // collapse/compress-style icon
                        color: "white"
                        opacity: toQuickMouse.containsMouse ? 0.9 : 0.5
                        font.family: root.iconFontFamily
                        font.pixelSize: 10
                    }
                    MouseArea {
                        id: toQuickMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: root.viewMode = "quick"
                    }
                }

                Repeater {
                    model: [
                        { label: "\uf03e  Static", idx: 0 },
                        { label: "\uf144  Video",  idx: 1 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: tabLabel.implicitWidth + 18; height: 26; radius: 13
                        color: root.activeTab === modelData.idx
                               ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.05)
                        border.color: root.activeTab === modelData.idx
                                      ? Qt.rgba(1,1,1,0.28) : Qt.rgba(1,1,1,0.08)
                        border.width: 1
                        Behavior on color        { ColorAnimation { duration: 160 } }
                        Behavior on border.color { ColorAnimation { duration: 160 } }
                        Text {
                            renderType: Text.NativeRendering
                            id: tabLabel; anchors.centerIn: parent
                            text: modelData.label; color: "white"
                            opacity: root.activeTab === modelData.idx ? 0.9 : 0.4
                            font.pixelSize: 10; font.family: root.textFontFamily
                            font.weight: root.activeTab === modelData.idx
                                         ? Font.Medium : Font.Normal
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                root.activeTab = modelData.idx
                                root.selectedIndex = root.activeList.length > 0 ? 0 : -1
                                searchInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }
        }

        // ── Grid ──────────────────────────────────────────────────────────
        Item {
            id: gridArea
            width: parent.width
            height: root.gridHeight
            clip: true

            Column {
                anchors.centerIn: parent; spacing: 8
                visible: root.activeList.length === 0
                Text {
                    renderType: Text.NativeRendering
                    id: loadingIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: staticScanner.running || videoScanner.running
                          ? "\uf110" : "\uf03e"
                    font.family: root.iconFontFamily; font.pixelSize: 24
                    color: "white"; opacity: 0.15

                    NumberAnimation on rotation {
                        from: 0; to: 360; duration: 900
                        loops: Animation.Infinite
                        running: staticScanner.running || videoScanner.running
                    }
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: staticScanner.running || videoScanner.running
                          ? "Scanning…"
                          : root.searchText !== ""
                            ? "No results for \"" + root.searchText + "\""
                            : root.activeTab === 0
                              ? "No wallpapers found"
                              : "No videos found"
                    color: "white"; opacity: 0.3
                    font.pixelSize: 11; font.family: root.textFontFamily
                }
            }

            GridView {
                id: wallGrid
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                cellWidth:  Math.floor((gridArea.width - 20) / root.gridCols)
                cellHeight: root.thumbCellSize
                model: root.activeList.length
                cacheBuffer: 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 3; radius: 2
                        color: Qt.rgba(1, 1, 1, 0.25)
                    }
                    background: Item {}
                }

                delegate: Item {
                    id: cellItem
                    width:  wallGrid.cellWidth
                    height: wallGrid.cellHeight
                    required property int index

                    property string wallPath:   root.activeList[index] || ""
                    property bool   isSelected: root.selectedIndex === index
                    property bool   isCurrent:  root.currentWallpaper === wallPath

                    property string thumbSrc: {
                        let cached = root.thumbMap[wallPath]
                        if (cached && cached !== "") return "file://" + cached
                        if (root.activeTab === 0) return "file://" + wallPath
                        return ""
                    }

                    Rectangle {
                        id: cellBg
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: 8
                        color: cellItem.isSelected       ? Qt.rgba(1,1,1,0.12)
                             : hoverMouse.containsMouse   ? Qt.rgba(1,1,1,0.08)
                             : Qt.rgba(1,1,1,0.03)
                        border.color: cellItem.isSelected      ? Qt.rgba(0.0, 0.66, 1.0, 0.85)
                                    : cellItem.isCurrent       ? Qt.rgba(0.4,0.9,0.55,0.6)
                                    : hoverMouse.containsMouse ? Qt.rgba(1,1,1,0.2)
                                    : Qt.rgba(1,1,1,0.07)
                        border.width: cellItem.isSelected || cellItem.isCurrent ? 2 : 1
                        Behavior on color        { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Item {
                            id: thumbClip
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: thumbClip.width
                                    height: thumbClip.height
                                    radius: 8
                                    color: "white"
                                    visible: false
                                }
                            }

                            Loader {
                                anchors.fill: parent
                                active: {
                                    let top  = wallGrid.contentY
                                    let bot  = top + wallGrid.height
                                    let iTop = cellItem.y
                                    let iBot = iTop + cellItem.height
                                    return iBot + cellItem.height >= top &&
                                           iTop - cellItem.height <= bot &&
                                           cellItem.thumbSrc !== ""
                                }
                                asynchronous: true
                                sourceComponent: Component {
                                    Image {
                                        source: cellItem.thumbSrc
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true; mipmap: true; cache: true
                                        sourceSize.width:  160
                                        sourceSize.height: 160
                                        opacity: status === Image.Ready ? (cellItem.isSelected ? 0.35: hoverMouse.containsMouse ? 0.85 : 1) : 0
                                        Behavior on opacity { NumberAnimation { duration: 220 } }
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: Qt.rgba(1, 1, 1, 0.03)
                                    visible: parent.status !== Loader.Ready || cellItem.thumbSrc === ""
                                    Text {
                                        renderType: Text.NativeRendering
                                        anchors.centerIn: parent
                                        text: root.activeTab === 0 ? "\uf03e" : "\uf144"
                                        font.family: root.iconFontFamily
                                        font.pixelSize: 13
                                        color: "white"; opacity: 0.1
                                    }
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left; anchors.right: parent.right
                                height: 14
                                color: Qt.rgba(0.4, 0.9, 0.55, 0.82)
                                visible: cellItem.isCurrent
                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.centerIn: parent
                                    text: "ACTIVE"
                                    color: "white"; font.pixelSize: 7
                                    font.family: root.textFontFamily
                                    font.weight: Font.Bold
                                }
                            }

                            Rectangle {
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.margins: 3
                                width: 14; height: 14; radius: 7
                                color: Qt.rgba(0, 0, 0, 0.55)
                                visible: root.activeTab === 1
                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.centerIn: parent; text: "\uf144"
                                    font.family: root.iconFontFamily
                                    font.pixelSize: 7
                                    color: "white"; opacity: 0.85
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.color: cellItem.isSelected      ? Qt.rgba(0.0, 0.66, 1.0, 0.85)
                                        : cellItem.isCurrent       ? Qt.rgba(0.4,0.9,0.55,0.6)
                                        : hoverMouse.containsMouse ? Qt.rgba(1,1,1,0.2)
                                        : Qt.rgba(1,1,1,0.07)
                            border.width: cellItem.isSelected || cellItem.isCurrent ? 2 : 1
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                    }

                    MouseArea {
                        id: hoverMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered:  root.selectedIndex = index
                        onClicked: {
                            root.selectedIndex = index
                            if (root.activeTab === 0)
                                root.setStaticWallpaper(cellItem.wallPath)
                            else
                                root.setVideoWallpaper(cellItem.wallPath)
                        }
                    }
                }
            }
        }

        // ── Footer ────────────────────────────────────────────────────────
        Rectangle {
            id: bottomBar
            width: parent.width
            height: root.footerHeight
            color: Qt.rgba(1, 0, 0, 0.0)

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Rectangle {
                    height: 18; width: countText.implicitWidth + 14; radius: 9
                    color: Qt.rgba(1,1,1,0.07)
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        renderType: Text.NativeRendering
                        id: countText; anchors.centerIn: parent
                        text: root.activeList.length +
                              (root.activeTab === 0 ? " images" : " videos")
                        color: "white"; opacity: 0.4
                        font.pixelSize: 9; font.family: root.textFontFamily
                    }
                }

                Rectangle {
                    height: 18; width: randomLabel.implicitWidth + 14; radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    color: randomMouse.containsMouse
                           ? Qt.rgba(0.67,0.55,0.98,0.25) : Qt.rgba(1,1,1,0.07)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        renderType: Text.NativeRendering
                        id: randomLabel; anchors.centerIn: parent
                        text: "\uf522  Random"
                        color: "white"
                        opacity: randomMouse.containsMouse ? 0.9 : 0.4
                        font.pixelSize: 9; font.family: root.textFontFamily
                    }
                    MouseArea {
                        id: randomMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: root.applyRandom()
                    }
                }

                Rectangle {
                    height: 18; width: stopAllLabel.implicitWidth + 14; radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    color: stopAllMouse.containsMouse
                           ? Qt.rgba(1,0.3,0.3,0.25) : Qt.rgba(1,1,1,0.07)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        renderType: Text.NativeRendering
                        id: stopAllLabel; anchors.centerIn: parent
                        text: "\uf04d  Stop All"
                        color: "white"
                        opacity: stopAllMouse.containsMouse ? 0.9 : 0.4
                        font.pixelSize: 9; font.family: root.textFontFamily
                    }
                    MouseArea {
                        id: stopAllMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: root.stopAll()
                    }
                }

                Rectangle {
                    height: 18; width: 18; radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    color: openFolderMouse.containsMouse
                           ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.07)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: "\uf07b"
                        color: "white"
                        opacity: openFolderMouse.containsMouse ? 0.9 : 0.4
                        font.family: root.iconFontFamily
                        font.pixelSize: 9
                    }
                    MouseArea {
                        id: openFolderMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: root.openTabFolder()
                    }
                }

                Rectangle {
                    height: 18; width: 18; radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    color: openConvMouse.containsMouse
                           ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.07)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: "\uf0c5"
                        color: "white"
                        opacity: openConvMouse.containsMouse ? 0.9 : 0.4
                        font.family: root.iconFontFamily
                        font.pixelSize: 9
                    }
                    MouseArea {
                        id: openConvMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            openConvFolderProc.command = ["xdg-open", IslandConfiguration.videoFolder]
                            openConvFolderProc.running = true
                        }
                    }
                }
            }

            Text {
                renderType: Text.NativeRendering
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.statusMessage
                color: root.statusOk
                       ? Qt.rgba(0.4, 0.9, 0.55, 1)
                       : Qt.rgba(1, 0.4, 0.4, 1)
                font.pixelSize: 10; font.family: root.textFontFamily
                opacity: root.statusMessage !== "" ? 0.9 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            Text {
                renderType: Text.NativeRendering
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "↵ apply  ·  Tab switch tab  ·  Esc close"
                color: "white"; opacity: 0.35
                font.pixelSize: 9; font.family: root.textFontFamily
                visible: root.statusMessage === ""
            }
        }
    } // Closes gridModeColumn

    // ── Quickview: carousel, one large item centered, neighbors peeking ──
    Column {
        id: quickModeColumn
        anchors.fill: parent
        spacing: 0
        visible: root.viewMode === "quick"

        // ── Header: Picture/Video toggle (shared activeTab) + expand icon ─
        Item {
            id: quickTopBar
            width: parent.width
            height: root.quickHeaderHeight

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: [
                        { label: "\uf03e  Picture", idx: 0 },
                        { label: "\uf144  Video",   idx: 1 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: quickTabLabel.implicitWidth + 18; height: 26; radius: 13
                        color: root.activeTab === modelData.idx
                               ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.05)
                        border.color: root.activeTab === modelData.idx
                                      ? Qt.rgba(1,1,1,0.28) : Qt.rgba(1,1,1,0.08)
                        border.width: 1
                        Behavior on color        { ColorAnimation { duration: 160 } }
                        Behavior on border.color { ColorAnimation { duration: 160 } }
                        Text {
                            renderType: Text.NativeRendering
                            id: quickTabLabel; anchors.centerIn: parent
                            text: modelData.label; color: "white"
                            opacity: root.activeTab === modelData.idx ? 0.9 : 0.4
                            font.pixelSize: 10; font.family: root.textFontFamily
                            font.weight: root.activeTab === modelData.idx
                                         ? Font.Medium : Font.Normal
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                root.activeTab = modelData.idx
                                root.selectedIndex = root.activeList.length > 0 ? 0 : -1
                            }
                        }
                    }
                }
            }

            // ── Expand to full grid ─────────────────────────────────────────
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26; radius: 13
                color: toGridMouse.containsMouse
                       ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.07)
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: "\uf065"   // expand-style icon
                    color: "white"
                    opacity: toGridMouse.containsMouse ? 0.9 : 0.5
                    font.family: root.iconFontFamily
                    font.pixelSize: 10
                }
                MouseArea {
                    id: toGridMouse; anchors.fill: parent; hoverEnabled: true
                    onClicked: root.viewMode = "grid"
                }
            }
        }

        // ── Carousel ──────────────────────────────────────────────────────
        Item {
            id: quickCarouselArea
            width: parent.width
            height: root.quickCarouselHeight

            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: root.activeList.length === 0

                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: staticScanner.running || videoScanner.running
                          ? "\uf110" : "\uf03e"
                    font.family: root.iconFontFamily; font.pixelSize: 26
                    color: "white"; opacity: 0.15

                    NumberAnimation on rotation {
                        from: 0; to: 360; duration: 900
                        loops: Animation.Infinite
                        running: staticScanner.running || videoScanner.running
                    }
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: staticScanner.running || videoScanner.running
                          ? "Scanning…"
                          : root.activeTab === 0 ? "No wallpapers found" : "No videos found"
                    color: "white"; opacity: 0.3
                    font.pixelSize: 11; font.family: root.textFontFamily
                }
            }

            ListView {
                id: quickCarousel
                anchors.fill: parent
                visible: root.activeList.length > 0
                model: root.activeList.length
                orientation: ListView.Horizontal
                spacing: 16
                clip: false
                focus: true

                highlightFollowsCurrentItem: true
                highlightMoveDuration: 260
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: width / 2 - root.quickCellWidth / 2
                preferredHighlightEnd: width / 2 + root.quickCellWidth / 2
                snapMode: ListView.SnapToItem

                currentIndex: root.selectedIndex >= 0 ? root.selectedIndex : 0
                onCurrentIndexChanged: root.selectedIndex = currentIndex

                Keys.onEscapePressed: root.closeRequested()
                Keys.onReturnPressed: root.applySelected()
                Keys.onLeftPressed: if (currentIndex > 0) currentIndex--
                Keys.onRightPressed: if (currentIndex < count - 1) currentIndex++
                Keys.onTabPressed: root.activeTab = root.activeTab === 0 ? 1 : 0

                // Any other printable character means "I want to search" —
                // expand to the full grid and forward the keystroke into its
                // search box, matching the "typing expands" behavior.
                Keys.onPressed: (event) => {
                    if (event.text && event.text.length > 0 && /[ -~]/.test(event.text)) {
                        root.viewMode = "grid"
                        Qt.callLater(() => {
                            root.searchText = root.searchText + event.text
                            if (typeof searchInput !== "undefined") {
                                searchInput.text = root.searchText
                                searchInput.forceActiveFocus()
                                searchInput.cursorPosition = searchInput.text.length
                            }
                        })
                        event.accepted = true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    z: -1
                    onWheel: (wheel) => {
                        if (wheel.angleDelta.y > 0 && quickCarousel.currentIndex > 0)
                            quickCarousel.currentIndex--
                        else if (wheel.angleDelta.y < 0 && quickCarousel.currentIndex < quickCarousel.count - 1)
                            quickCarousel.currentIndex++
                    }
                }

                delegate: Item {
                    id: quickCell
                    width: root.quickCellWidth
                    height: quickCarousel.height

                    required property int index
                    property bool isCurrent: ListView.isCurrentItem
                    property string wallPath: root.activeList[index] || ""
                    property bool isCurrentWallpaper: root.currentWallpaper === wallPath

                    property string thumbSrc: {
                        let cached = root.thumbMap[wallPath]
                        if (cached && cached !== "") return "file://" + cached
                        if (root.activeTab === 0) return "file://" + wallPath
                        return ""
                    }

                    Item {
                        id: quickShapeRoot
                        anchors.centerIn: parent
                        width: parent.width - 10
                        height: root.quickCellHeight

                        scale: quickCell.isCurrent ? 1.0 : root.quickNeighborScale
                        opacity: quickCell.isCurrent ? 1.0 : 0.55
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 220 } }

                        // ── Parallelogram mask: top/bottom stay horizontal,
                        // left/right edges slant by root.quickSkew pixels ──
                        Canvas {
                            id: quickParallelogramMask
                            anchors.fill: parent
                            visible: false

                            onPaint: {
                                let ctx = getContext("2d")
                                ctx.reset()
                                let s = root.quickSkew
                                ctx.beginPath()
                                ctx.moveTo(s, 0)
                                ctx.lineTo(width, 0)
                                ctx.lineTo(width - s, height)
                                ctx.lineTo(0, height)
                                ctx.closePath()
                                ctx.fillStyle = "white"
                                ctx.fill()
                            }
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()
                        }

                        Item {
                            id: quickThumbClip
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: quickParallelogramMask
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(1, 1, 1, 0.04)
                            }

                            Image {
                                anchors.fill: parent
                                source: quickCell.thumbSrc
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true; mipmap: true; cache: true
                                sourceSize.width: 460
                                sourceSize.height: 250
                                visible: status === Image.Ready
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(1, 1, 1, 0.03)
                                visible: quickCell.thumbSrc === ""
                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.centerIn: parent
                                    text: root.activeTab === 0 ? "\uf03e" : "\uf144"
                                    font.family: root.iconFontFamily
                                    font.pixelSize: 20
                                    color: "white"; opacity: 0.12
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left; anchors.right: parent.right
                                height: 20
                                color: Qt.rgba(0.4, 0.9, 0.55, 0.85)
                                visible: quickCell.isCurrentWallpaper
                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.centerIn: parent
                                    text: "ACTIVE"
                                    color: "white"; font.pixelSize: 9
                                    font.family: root.textFontFamily
                                    font.weight: Font.Bold
                                }
                            }

                            Rectangle {
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.margins: 6
                                width: 18; height: 18; radius: 9
                                color: Qt.rgba(0, 0, 0, 0.55)
                                visible: root.activeTab === 1
                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.centerIn: parent; text: "\uf144"
                                    font.family: root.iconFontFamily
                                    font.pixelSize: 8
                                    color: "white"; opacity: 0.85
                                }
                            }
                        }

                        // Thin hairline outline on the parallelogram card itself,
                        // matching the shell's border language elsewhere.
Canvas {
                            id: quickHairline
                            anchors.fill: parent
                            onPaint: {
                                let ctx = getContext("2d")
                                ctx.reset()
                                let s = root.quickSkew
                                ctx.beginPath()
                                ctx.moveTo(s, 0)
                                ctx.lineTo(width, 0)
                                ctx.lineTo(width - s, height)
                                ctx.lineTo(0, height)
                                ctx.closePath()
                                ctx.lineWidth = IslandMotion.surfaceBorderWidth
                                ctx.strokeStyle = IslandMotion.surfaceBorderColor
                                ctx.stroke()
                            }
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()
                        }

                        // ── Slanted outline drawn on top, since border.width
                        // on a Rectangle can't follow a parallelogram path ──
                        Canvas {
                            id: quickOutline
                            anchors.fill: parent
                            property color outlineColor: Qt.rgba(0.0, 0.66, 1.0, 0.85)
                            property real outlineWidth: quickCell.isCurrent ? 2 : 0

                            onOutlineColorChanged: requestPaint()
                            onOutlineWidthChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                let ctx = getContext("2d")
                                ctx.reset()
                                if (outlineWidth <= 0) return
                                let s = root.quickSkew
                                ctx.beginPath()
                                ctx.moveTo(s, 0)
                                ctx.lineTo(width, 0)
                                ctx.lineTo(width - s, height)
                                ctx.lineTo(0, height)
                                ctx.closePath()
                                ctx.lineWidth = outlineWidth
                                ctx.strokeStyle = outlineColor
                                ctx.stroke()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                quickCarousel.currentIndex = quickCell.index
                                if (quickCell.isCurrent) {
                                    if (root.activeTab === 0) root.setStaticWallpaper(quickCell.wallPath)
                                    else root.setVideoWallpaper(quickCell.wallPath)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Footer hint ─────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: root.quickFooterHeight

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: root.statusMessage !== "" ? root.statusMessage
                      : (root.activeList.length + (root.activeTab === 0 ? " images" : " videos")
                         + "   ·   ↵ apply  ·  ←/→ browse  ·  Esc close")
                color: root.statusMessage !== ""
                       ? (root.statusOk ? Qt.rgba(0.4, 0.9, 0.55, 1) : Qt.rgba(1, 0.4, 0.4, 1))
                       : Qt.rgba(1, 1, 1, 0.35)
                font.pixelSize: 9; font.family: root.textFontFamily
            }
        }
    } // Closes quickModeColumn
    }
