import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import IslandBackend
import "qml/shared"

// ── BubbleDockWindow ──────────────────────────────────────────────────
// Horizontal pill dock at bottom-center.
// Pin  = always visible.
// Smart = visible only when active workspace has NO windows.
//         A thin hover strip at the very bottom lets you peek the dock
//         even when it's slid away.

PanelWindow {
    id: root

    // ── Props from shell ──────────────────────────────────────────────
    property bool   dockEnabled:        true
    property string dockMode:           "pin"
    property bool   sidebarActive:      false

    property bool   gamemodeActive:     false
    property real   capsuleOpacity:     0.20
    property bool   capsuleUseWalColor: false
    property color  capsuleWalColor:    "#000000"

    property string iconFontFamily:     ""
    property string textFontFamily:     ""

    // ── Geometry ─────────────────────────────────────────────────────
    readonly property int iconSize:   44
    readonly property int pillH:      64
    readonly property int edgePad:    14
    readonly property int iconGap:    8

    // ── Window setup ─────────────────────────────────────────────────
    exclusiveZone: 0
    aboveWindows:  true
    color:         "transparent"
    anchors { bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay

    mask: Region {
        // Pill
        Region {
            x:      Math.floor(pill.x)
            y:      Math.floor(pill.y)
            width:  root.pillActuallyVisible ? Math.ceil(pill.implicitWidth + root.edgePad * 2) : 0
            height: root.pillActuallyVisible ? Math.ceil(root.pillH) : 0
        }
        // Thin hover strip at bottom edge for smart-mode peek
        Region {
            intersection: Intersection.Combine
            x:      0
            y:      root.height - 4
            width:  root.width
            height: 4
        }
    }

    // ── Colour — matches main bar exactly ────────────────────────────
    readonly property color pillColor: root.gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (root.capsuleUseWalColor
            ? Qt.rgba(root.capsuleWalColor.r, root.capsuleWalColor.g, root.capsuleWalColor.b, root.capsuleOpacity)
            : Qt.rgba(0, 0, 0, root.capsuleOpacity))

    // ── Smart mode window detection ───────────────────────────────────
    property bool anyWindowOpen: false
    property bool hoverPeeking:  false   // user hovering the bottom strip

    Process {
        id: windowCountQuery
        property string _buf: ""
        command: ["bash", "-c", "hyprctl activeworkspace -j 2>/dev/null"]
        stdout: SplitParser { onRead: windowCountQuery._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const raw = windowCountQuery._buf
                windowCountQuery._buf = ""
                try {
                    const p = JSON.parse(raw)
                    root.anyWindowOpen = !isNaN(Number(p.windows)) && Number(p.windows) > 0
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 700
        running:  root.dockMode === "smart" && root.dockEnabled
        repeat:   true
        triggeredOnStart: true
        onTriggered: if (!windowCountQuery.running) windowCountQuery.running = true
    }

    // Sidebar hides the dock entirely
    readonly property bool pillActuallyVisible:
        root.dockEnabled
        && !root.sidebarActive
        && (root.dockMode === "pin" || !root.anyWindowOpen || root.hoverPeeking)

    // ── Thin hover strip — lets smart mode peek ───────────────────────
    MouseArea {
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        height: 8
        hoverEnabled: true
        onEntered: root.hoverPeeking = true
        onExited:  root.hoverPeeking = false
        z: -1
    }

    // ── Favourite apps ────────────────────────────────────────────────
    property var favApps:      []
    property var favoritesSet: ({})

    Process {
        id: loadFavProc
        property string _buf: ""
        command: ["bash", "-c",
            "f=\"$HOME/.cache/quickshell/search-favorites.json\"; [ -f \"$f\" ] && cat \"$f\" || printf '{}'"]
        stdout: SplitParser { onRead: loadFavProc._buf += data }
        onRunningChanged: {
            if (!running) {
                try {
                    const p = JSON.parse(loadFavProc._buf.trim() || "{}")
                    const favs = Array.isArray(p.favorites) ? p.favorites : []
                    const set = {}
                    for (let i = 0; i < favs.length; i++) set[favs[i]] = true
                    root.favoritesSet = set
                } catch (e) {}
                loadFavProc._buf = ""
                loadAppsProc.running = true
            }
        }
    }

    Process {
        id: loadAppsProc
        property string _buf: ""
        command: ["python3", Quickshell.shellDir + "/scripts/list-apps.py"]
        stdout: SplitParser { onRead: loadAppsProc._buf += data }
        onRunningChanged: {
            if (!running) {
                try {
                    const parsed = JSON.parse(loadAppsProc._buf)
                    if (Array.isArray(parsed)) {
                        root.favApps = parsed
                            .filter(a => root.favoritesSet[a.exec || ""] === true)
                            .map(a => ({ appName: a.name || "", appExec: a.exec || "", appIcon: a.icon || "" }))
                    }
                } catch (e) {}
                loadAppsProc._buf = ""
            }
        }
    }

    Component.onCompleted: loadFavProc.running = true

    FileView {
        path: StandardPaths.writableLocation(StandardPaths.HomeLocation)
              + "/.cache/quickshell/search-favorites.json"
        watchChanges: true; preload: false; printErrors: false
        onFileChanged: loadFavProc.running = true
    }

    // ── Active windows (non-favourite, deduplicated by class) ─────────
    property var activeApps: []

    // Icon lookup queue for active windows
    property var _iconQueue: []

    Process {
        id: activeAppsQuery
        property string _buf: ""
        command: ["bash", "-c", "hyprctl clients -j 2>/dev/null"]
        stdout: SplitParser { onRead: activeAppsQuery._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const raw = activeAppsQuery._buf
                activeAppsQuery._buf = ""
                try {
                    const clients = JSON.parse(raw)
                    const seen = {}
                    const result = []
                    for (let i = 0; i < clients.length; i++) {
                        const c   = clients[i]
                        const cls = String(c.class || "").toLowerCase()
                        const ttl = String(c.title || "")
                        if (!cls || seen[cls]) continue
                        // Skip if already in favourites (match by exec or name)
                        const inFav = root.favApps.some(f => {
                            const ex = String(f.appExec).toLowerCase()
                            const nm = String(f.appName).toLowerCase()
                            return ex.indexOf(cls) >= 0 || cls.indexOf(nm) >= 0
                        })
                        if (inFav) continue
                        seen[cls] = true
                        result.push({ appName: ttl || cls, appClass: cls, appIcon: "" })
                    }
                    root.activeApps = result
                    // Queue icon lookups for apps with no icon
                    root._iconQueue = result.map(a => ({ appClass: a.appClass }))
                    processNextIconLookup()
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 2000
        running:  root.dockEnabled
        repeat:   true
        triggeredOnStart: true
        onTriggered: if (!activeAppsQuery.running) activeAppsQuery.running = true
    }

    // Icon lookup — find icon file by window class using same method as notification lookup
    Process {
        id: iconLookupProc
        property string _appClass: ""
        property string _buf: ""
        stdout: SplitParser { onRead: iconLookupProc._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const found = iconLookupProc._buf.trim()
                const cls   = iconLookupProc._appClass
                iconLookupProc._buf = ""
                if (found !== "" && cls !== "") {
                    // Patch the icon into activeApps
                    root.activeApps = root.activeApps.map(function(a) {
                        if (a.appClass !== cls) return a
                        const n = Object.assign({}, a)
                        n.appIcon = found
                        return n
                    })
                }
                iconLookupProc._appClass = ""
                processNextIconLookup()
            }
        }
    }

    function processNextIconLookup() {
        if (iconLookupProc.running || root._iconQueue.length === 0) return
        const item  = root._iconQueue.shift()
        const cls   = item.appClass
        // Only look up if we don't already have an icon
        const existing = root.activeApps.find(a => a.appClass === cls)
        if (existing && existing.appIcon !== "") { processNextIconLookup(); return }
        iconLookupProc._appClass = cls
        iconLookupProc.command = ["bash", "-c",
            "n='" + cls + "'; " +
            "f=\"$HOME/.cache/quickshell/dock-apps-v2.tsv\"; " +
            "if [ -f \"$f\" ]; then " +
              "r=$(awk -F'\\t' -v n=\"$n\" '{ ln=tolower($1); if (index(ln, n) > 0 && $3 != \"\") { print $3; exit } }' \"$f\"); " +
              "[ -n \"$r\" ] && echo \"$r\" && exit 0; " +
            "fi; " +
            "icon=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons 2>/dev/null " +
              "-type f \\( -name \"${n}.png\" -o -name \"${n}.svg\" \\) " +
              "| grep -i '48x48\\|scalable\\|256x256' | head -1); " +
            "[ -z \"$icon\" ] && " +
              "icon=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons 2>/dev/null " +
              "-type f \\( -name \"${n}.png\" -o -name \"${n}.svg\" \\) | head -1); " +
            "[ -n \"$icon\" ] && echo \"$icon\" && exit 0; " +
            "desktop=$(grep -ril \"^Name=.*${n}\\|^Exec=.*${n}\" /usr/share/applications $HOME/.local/share/applications 2>/dev/null | head -1); " +
            "if [ -n \"$desktop\" ]; then " +
              "iname=$(grep -m1 '^Icon=' \"$desktop\" | cut -d= -f2); " +
              "[ -n \"$iname\" ] && [ -f \"$iname\" ] && echo \"$iname\" && exit 0; " +
              "r=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons 2>/dev/null " +
                "-type f \\( -name \"${iname}.png\" -o -name \"${iname}.svg\" \\) " +
                "| grep -i '48x48\\|scalable\\|256x256' | head -1); " +
              "[ -z \"$r\" ] && " +
                "r=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons 2>/dev/null " +
                "-type f \\( -name \"${iname}.png\" -o -name \"${iname}.svg\" \\) | head -1); " +
              "[ -n \"$r\" ] && echo \"$r\"; " +
            "fi"
        ]
        iconLookupProc.running = true
    }

    // ── Launch / focus helpers ────────────────────────────────────────
    Process { id: launchProc }
    Process { id: focusProc }
    function launch(cmd) {
        launchProc.command = ["bash", "-c", "nohup " + cmd + " &"]
        launchProc.running = true
    }
    function focusWindow(cls) {
        focusProc.command = ["bash", "-c",
            "hyprctl dispatch focuswindow class:'" + cls + "' 2>/dev/null"]
        focusProc.running = true
    }

    // ── Systray toggle ────────────────────────────────────────────────
    property bool systrayOpen: false

    // ── Divider — matches surfaceBorderColor ──────────────────────────
    component DockDivider: Rectangle {
        width:  1; height: 28; radius: 1
        color:  IslandMotion.surfaceBorderColor
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    // ── App button ────────────────────────────────────────────────────
    component AppButton: Item {
        id: appBtn
        property string iconPath:  ""
        property string label:     ""
        property bool   isRunning: false
        signal tapped()

        width:  root.iconSize
        height: root.iconSize + 16  // extra room for tooltip above

        property bool hov: false

        // Tooltip above
        Rectangle {
            id: tooltipBox
            anchors.bottom: iconArea.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 4
            visible: appBtn.hov
            width:  tooltipText.implicitWidth + 12
            height: 20
            radius: 6
            color:  Qt.rgba(0,0,0,0.75)
            border.width: 1
            border.color: Qt.rgba(1,1,1,0.15)

            Text {
                id: tooltipText
                renderType:       Text.NativeRendering
                anchors.centerIn: parent
                text:             appBtn.label
                color:            "white"
                font.pixelSize:   11
                font.family:      root.textFontFamily
            }
        }

        // Icon container — bounces on hover
        Item {
            id: iconArea
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width:  root.iconSize
            height: root.iconSize

            transform: Translate {
                y: appBtn.hov ? -5 : 0
                Behavior on y {
                    NumberAnimation { duration: IslandMotion.fast; easing.type: Easing.OutBack }
                }
            }

            Image {
                id: iconImg
                anchors.fill:    parent
                anchors.margins: 2
                source:   appBtn.iconPath !== "" ? "file://" + appBtn.iconPath : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true; smooth: true
                visible:  status === Image.Ready
                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
            }

            // Fallback
            Rectangle {
                anchors.fill: parent; anchors.margins: 4
                visible: !iconImg.visible
                radius:  10
                color:   Qt.rgba(1,1,1,0.12)
                border.width: 1; border.color: Qt.rgba(1,1,1,0.20)
                Text {
                    renderType:       Text.NativeRendering
                    anchors.centerIn: parent
                    text:  appBtn.label.length > 0 ? appBtn.label[0].toUpperCase() : "?"
                    color: "white"
                    font.pixelSize: 18; font.family: root.textFontFamily
                    font.weight: Font.Medium
                }
            }

            // Running dot
            Rectangle {
                visible:  appBtn.isRunning
                width: 4; height: 4; radius: 2
                color: "white"; opacity: 0.75
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: -1
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill:   iconArea
            anchors.margins: -4
            hoverEnabled:   true
            cursorShape:    Qt.PointingHandCursor
            onEntered:      appBtn.hov = true
            onExited:       appBtn.hov = false
            onClicked:      appBtn.tapped()
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // ── The pill ─────────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════
    Item {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom:           parent.bottom
        anchors.bottomMargin:     10

        implicitWidth:  pillRow.implicitWidth + root.edgePad * 2
        implicitHeight: root.pillH + 16   // +16 for tooltip space above

        // Slide: visible → bottom margin, hidden → off screen below
        property real slideY: root.pillActuallyVisible ? 0 : (root.pillH + 26)
        transform: Translate { y: pill.slideY }
        Behavior on slideY {
            NumberAnimation {
                duration: IslandMotion.standard
                easing.type: IslandMotion.easeArrive
            }
        }

        // Background — positioned at bottom of item (below tooltip space)
        Rectangle {
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.bottom: parent.bottom
            height: root.pillH
            radius: height / 2
            color:  root.pillColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            Behavior on color {
                ColorAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove }
            }
        }

        // Content row — centred in the lower pillH region
        Row {
            id: pillRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom:           parent.bottom
            anchors.bottomMargin:     (root.pillH - root.iconSize) / 2
            spacing: root.iconGap

            // ── Favourites ────────────────────────────────────────────
            Repeater {
                model: root.favApps
                delegate: AppButton {
                    iconPath:  modelData.appIcon
                    label:     modelData.appName
                    isRunning: root.activeApps.some(a => {
                        const ex = String(modelData.appExec).toLowerCase()
                        const nm = String(modelData.appName).toLowerCase()
                        return ex.indexOf(a.appClass) >= 0 || a.appClass.indexOf(nm) >= 0
                    })
                    onTapped: root.launch(modelData.appExec)
                }
            }

            // Divider — only if both sections have items
            DockDivider {
                visible:              root.favApps.length > 0 && root.activeApps.length > 0
                anchors.verticalCenter: parent.verticalCenter
            }

            // ── Active non-favourite windows ──────────────────────────
            Repeater {
                model: root.activeApps
                delegate: AppButton {
                    iconPath:  modelData.appIcon
                    label:     modelData.appName
                    isRunning: true
                    onTapped:  root.focusWindow(modelData.appClass)
                }
            }

            // Divider before systray
            DockDivider { anchors.verticalCenter: parent.verticalCenter }

            // ── Systray icons (slide in) ──────────────────────────────
            Row {
                id: trayIconsRow
                spacing: root.iconGap
                anchors.verticalCenter: parent.verticalCenter
                clip: true

                width: root.systrayOpen
                    ? (trayRepeater.count * (root.iconSize - 12 + root.iconGap) + (root.iconGap + 1 + root.iconGap))
                    : 0

                Behavior on width {
                    NumberAnimation {
                        duration: IslandMotion.standard
                        easing.type: IslandMotion.easeArrive
                    }
                }

                Repeater {
                    id: trayRepeater
                    model: SystemTray.items

                    delegate: Item {
                        id: trayDel
                        width:  root.iconSize - 12
                        height: root.iconSize - 12
                        anchors.verticalCenter: parent.verticalCenter

                        PopupWindow {
                            id: trayPopup
                            visible: false
                            color:   "transparent"
                            anchor.item: trayDel
                            anchor.rect.x: -(130 - trayDel.width / 2)
                            anchor.rect.y: -(trayDel.height + 8 + 120)
                            implicitWidth:  260
                            implicitHeight: trayMenuCol.implicitHeight + 16

                            QsMenuOpener {
                                id: trayOpener
                                menu: modelData.hasMenu ? modelData.menu : null
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: "#1e1e1e"; radius: 8

                                Column {
                                    id: trayMenuCol
                                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                                    spacing: 2

                                    Repeater {
                                        model: trayOpener.children ? trayOpener.children.values : []
                                        delegate: Column {
                                            id: trayMI; width: trayMenuCol.width
                                            spacing: 2; property bool subExp: false

                                            Rectangle {
                                                width: parent.width
                                                height: modelData.isSeparator ? 0 : 28
                                                visible: !modelData.isSeparator; radius: 4
                                                color: trayMIArea.containsMouse ? "#333333" : "transparent"
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Text {
                                                    renderType: Text.NativeRendering
                                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                                                    text: (modelData.text || "") + (modelData.hasChildren ? " ▶" : "")
                                                    color: trayMIArea.containsMouse ? "white" : Qt.rgba(1,1,1,0.75)
                                                    font.pixelSize: 12
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                                MouseArea {
                                                    id: trayMIArea; anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (modelData.hasChildren) trayMI.subExp = !trayMI.subExp
                                                        else {
                                                            if (modelData.triggered) modelData.triggered()
                                                            else if (modelData.activate) modelData.activate()
                                                            trayPopup.visible = false
                                                        }
                                                    }
                                                }
                                            }
                                            Column {
                                                visible: trayMI.subExp && modelData.hasChildren
                                                width: parent.width; spacing: 2
                                                QsMenuOpener { id: traySub; menu: modelData.hasChildren ? modelData : null }
                                                Repeater {
                                                    model: traySub.children ? traySub.children.values : []
                                                    delegate: Rectangle {
                                                        width: parent.width
                                                        height: modelData.isSeparator ? 0 : 28
                                                        visible: !modelData.isSeparator; radius: 4
                                                        color: traySubArea.containsMouse ? "#333333" : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                        Text {
                                                            renderType: Text.NativeRendering
                                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 16 }
                                                            text: modelData.text || ""
                                                            color: traySubArea.containsMouse ? "white" : Qt.rgba(1,1,1,0.75)
                                                            font.pixelSize: 12
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }
                                                        MouseArea {
                                                            id: traySubArea; anchors.fill: parent
                                                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (modelData.triggered) modelData.triggered()
                                                                else if (modelData.activate) modelData.activate()
                                                                trayPopup.visible = false
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
                            id: trayImg; anchors.fill: parent
                            source: { const ic = modelData.icon; return (!ic || ic === "") ? "" : ic }
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                            sourceSize: Qt.size((root.iconSize - 12) * 2, (root.iconSize - 12) * 2)
                            opacity: trayMA.containsMouse ? 1.0 : 0.75
                            scale:   trayMA.containsMouse ? 1.15 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        }

                        Rectangle {
                            anchors.fill: parent; color: "transparent"
                            visible: !trayImg.visible
                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text:  modelData.title ? modelData.title[0] : "?"
                                color: "white"
                                font.pixelSize: root.iconSize - 20
                                opacity: trayMA.containsMouse ? 1.0 : 0.75
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: trayMA
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton || modelData.onlyMenu)
                                    trayPopup.visible = !trayPopup.visible
                                else if (modelData.activate)
                                    modelData.activate()
                            }
                        }
                    }
                }

                // Divider before chevron (inside sliding section, only when open)
                DockDivider {
                    visible:              root.systrayOpen && trayRepeater.count > 0
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ── Chevron ›/‹ ──────────────────────────────────────────
            Item {
                width:  28
                height: root.iconSize
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    id: chevImg
                    anchors.centerIn: parent
                    width: 18; height: 18
                    source: Quickshell.shellDir + "/qml/shared/assets/chevron-double-left.svg"
                    sourceSize: Qt.size(28, 28)
                    fillMode: Image.PreserveAspectFit
                    // chevron-double-left points left; rotate 180 = points right (›) at rest
                    rotation: root.systrayOpen ? 0 : 180
                    opacity:  chevMA.containsMouse ? 1.0 : 0.60
                    scale:    chevMA.containsMouse ? 1.2 : (chevMA.pressed ? 0.85 : 1.0)
                    Behavior on opacity  { NumberAnimation { duration: IslandMotion.micro } }
                    Behavior on scale    { NumberAnimation { duration: IslandMotion.fast; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: IslandMotion.standard; easing.type: IslandMotion.easeArrive } }
                }

                MouseArea {
                    id: chevMA; anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.systrayOpen = !root.systrayOpen
                }
            }
        }
    }
}
