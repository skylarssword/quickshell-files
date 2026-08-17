import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import IslandBackend
import "qml/shared"

PanelWindow {
    id: root

    // ── Props ─────────────────────────────────────────────────────────
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
    readonly property int iconSize: 44
    readonly property int pillH:    64
    readonly property int edgePad:  14
    readonly property int iconGap:  8

    // ── Window ────────────────────────────────────────────────────────
    exclusiveZone: 0
    aboveWindows:  true
    color:         "transparent"
    anchors { bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay

    mask: Region {
        Region {
            x:      Math.floor(pill.x)
            y:      Math.floor(pill.y)
            width:  root.pillActuallyVisible ? Math.ceil(pill.implicitWidth) : 0
            height: root.pillActuallyVisible ? Math.ceil(root.pillH) : 0
        }
        Region {
            intersection: Intersection.Combine
            x: 0; y: root.height - 4
            width: root.width; height: 4
        }
    }

    readonly property color pillColor: root.gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (root.capsuleUseWalColor
            ? Qt.rgba(root.capsuleWalColor.r, root.capsuleWalColor.g, root.capsuleWalColor.b, root.capsuleOpacity)
            : Qt.rgba(0, 0, 0, root.capsuleOpacity))

    // ── Smart-mode window count ───────────────────────────────────────
    property bool anyWindowOpen: false

    Process {
        id: windowCountQuery
        property string _buf: ""
        command: ["bash", "-c", "hyprctl activeworkspace -j 2>/dev/null"]
        stdout: SplitParser { onRead: windowCountQuery._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                try { root.anyWindowOpen = (JSON.parse(windowCountQuery._buf).windows|0) > 0 } catch(e) {}
                windowCountQuery._buf = ""
            }
        }
    }
    Timer {
        interval: 700; repeat: true; triggeredOnStart: true
        running: root.dockMode === "smart" && root.dockEnabled
        onTriggered: if (!windowCountQuery.running) windowCountQuery.running = true
    }

    readonly property bool pillActuallyVisible:
        root.dockEnabled && !root.sidebarActive
        && (root.dockMode === "pin" || !root.anyWindowOpen || root.hoverPeeking)

    // Simple hover peeking — bottom strip sets true, clears on exit with debounce
    // so moving mouse from strip onto the pill doesn't immediately hide it.
    property bool hoverPeeking: false

    Timer {
        id: hoverExitTimer
        interval: 800; repeat: false
        onTriggered: root.hoverPeeking = false
    }

    // Bottom-edge peek strip
    MouseArea {
        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        height: 8; hoverEnabled: true; z: -1
        onEntered: { hoverExitTimer.stop(); root.hoverPeeking = true }
        onExited:  hoverExitTimer.restart()
    }

    // ── App data ──────────────────────────────────────────────────────
    // _appIconMap: built from list-apps.py output so active window icons
    // use GTK-resolved paths instead of a slow bash find fallback.
    property var _appIconMap: ({})

    function _buildIconMap(appList) {
        const map = {}
        for (let i = 0; i < appList.length; i++) {
            const a    = appList[i]
            const icon = a.icon || ""
            if (!icon) continue
            const wc  = (a.wmClass || "").toLowerCase()
            const al  = Array.isArray(a.wmClassAliases) ? a.wmClassAliases : []
            const exB = (a.exec || "").replace(/\s.*/, "").split("/").pop().toLowerCase()
            const nm  = (a.name || "").toLowerCase()
            if (wc)  map[wc]  = map[wc]  || icon
            if (exB) map[exB] = map[exB] || icon
            if (nm)  map[nm]  = map[nm]  || icon
            for (let j = 0; j < al.length; j++) {
                const k = al[j].toLowerCase()
                if (k) map[k] = map[k] || icon
            }
        }
        return map
    }

    // ── Favorites ─────────────────────────────────────────────────────
    property bool _pendingFavReload: false

    // Simple chain identical to the original: loadFavProc always triggers
    // loadAppsProc unconditionally. loadAppsProc filters with current favoritesSet.
    // No caching, no guards, no flags — just like the original that worked.
    property var favApps:      []
    property var favoritesSet: ({})

    Process {
        id: loadFavProc
        property string _buf: ""
        command: ["bash", "-c",
            "f=\"$HOME/.cache/quickshell/search-favorites.json\";" +
            " [ -f \"$f\" ] && cat \"$f\" || printf '{}'"]
        stdout: SplitParser { onRead: loadFavProc._buf += data }
        onRunningChanged: {
            if (!running) {
                try {
                    const p    = JSON.parse(loadFavProc._buf.trim() || "{}")
                    const favs = Array.isArray(p.favorites) ? p.favorites : []
                    const set  = {}
                    for (let i = 0; i < favs.length; i++) set[favs[i]] = true
                    root.favoritesSet = set
                } catch(e) {}
                const rawSnap = loadFavProc._buf.trim().slice(0, 120)
                loadFavProc._buf = ""
                root._pendingFavReload = false
                // Always need loadAppsProc to refilter — if it's already running,
                // set pending so it re-runs the full chain when it finishes.
                if (loadAppsProc.running) {
                    root._pendingFavReload = true
                } else {
                    loadAppsProc.running = true
                }
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
                        // Build icon map for active window icon resolution
                        root._appIconMap = root._buildIconMap(parsed)
                        // Filter to favorites using current favoritesSet
                        root.favApps = parsed
                            .filter(function(a) { return root.favoritesSet[a.exec || ""] === true })
                            .map(function(a) {
                                return {
                                    appName:    a.name    || "",
                                    appExec:    a.exec    || "",
                                    appIcon:    a.icon    || "",
                                    appWmClass: (a.wmClass || "").toLowerCase()
                                }
                            })
                    }
                } catch(e) {}
                loadAppsProc._buf = ""
                if (root._pendingFavReload) {
                    root._pendingFavReload = false
                    loadFavProc.running = true
                }
            }
        }
    }

    Component.onCompleted: loadFavProc.running = true

    // Safety net: re-run the chain every 5s if favApps count is wrong
    Timer {
        interval: 5000; repeat: true; running: root.dockEnabled
        onTriggered: {
            const expected = Object.keys(root.favoritesSet).length
            if (expected > 0 && root.favApps.length !== expected
                    && !loadFavProc.running && !loadAppsProc.running) {
                loadFavProc.running = true
            }
        }
    }

    // Poll favorites file every 3s for changes — more reliable than FileView
    // since FileView with preload:false may not activate its watcher.
    property string _lastFavRaw: ""
    Timer {
        interval: 3000; repeat: true; running: root.dockEnabled
        onTriggered: {
            if (!loadFavProc.running && !loadAppsProc.running)
                favPollProc.running = true
        }
    }
    Process {
        id: favPollProc
        property string _buf: ""
        command: ["bash", "-c",
            "f=\"$HOME/.cache/quickshell/search-favorites.json\";" +
            " [ -f \"$f\" ] && cat \"$f\" || printf '{}'"]
        stdout: SplitParser { onRead: favPollProc._buf += data }
        onRunningChanged: {
            if (!running) {
                const raw = favPollProc._buf.trim()
                favPollProc._buf = ""
                if (raw !== root._lastFavRaw) {
                    root._lastFavRaw = raw
                    // Parse and update directly
                    try {
                        const p    = JSON.parse(raw || "{}")
                        const favs = Array.isArray(p.favorites) ? p.favorites : []
                        const set  = {}
                        for (let i = 0; i < favs.length; i++) set[favs[i]] = true
                        root.favoritesSet = set
                    } catch(e) {}
                    if (!loadAppsProc.running) loadAppsProc.running = true
                }
            }
        }
    }

    // ── Active windows ────────────────────────────────────────────────
    // BUG FIX: Show ALL windows, not one per class.
    // Each window gets its own button with its own address for focus.
    // Deduplication is by ADDRESS (unique), not class.
    property var activeApps:   []
    property var allWindows:   []   // ALL open windows unfiltered — for fav isRunning + focus
    property var _activeIconCache: ({})
    property var _iconQueue:       []

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
                    const seenAddr = {}
                    const result   = []
                    const allWin   = []
                    for (let i = 0; i < clients.length; i++) {
                        const c      = clients[i]
                        const cls    = String(c.class   || "")
                        const clsLow = cls.toLowerCase()
                        const addr   = String(c.address || "")
                        const ttl    = String(c.title   || "")
                        if (!addr || seenAddr[addr]) continue
                        seenAddr[addr] = true

                        // Store in allWindows before any filtering
                        allWin.push({ appClass: cls, appClassLow: clsLow, appAddress: addr })

                        // Skip if already shown as a favourite
                        let inFav = false
                        for (let j = 0; j < root.favApps.length; j++) {
                            const f   = root.favApps[j]
                            const wc  = String(f.appWmClass || "")
                            const ex  = String(f.appExec || "").split("/").pop().toLowerCase().replace(/\s.*/, "")
                            if (wc && (wc === clsLow || clsLow.startsWith(wc) || wc.startsWith(clsLow))) { inFav = true; break }
                            if (ex && ex.length > 2 && (ex === clsLow || clsLow.startsWith(ex) || ex.startsWith(clsLow) || clsLow.includes(ex) || ex.includes(clsLow))) { inFav = true; break }
                        }
                        if (inFav) continue

                        // Icon: try GTK map first, then persistent cache, then queue bash lookup
                        const mapIcon   = root._appIconMap[clsLow] || root._appIconMap[ttl.toLowerCase()] || ""
                        const cacheIcon = root._activeIconCache[clsLow] || ""
                        const icon      = mapIcon || cacheIcon
                        if (mapIcon && !root._activeIconCache[clsLow]) {
                            const c2 = Object.assign({}, root._activeIconCache)
                            c2[clsLow] = mapIcon
                            root._activeIconCache = c2
                        }

                        result.push({
                            appName:     ttl || cls,
                            appClass:    cls,
                            appClassLow: clsLow,
                            appAddress:  addr,
                            appIcon:     icon
                        })
                    }
                    result.sort(function(a, b) { return a.appAddress < b.appAddress ? -1 : 1 })
                    root.activeApps = result
                    root.allWindows = allWin

                    // Queue bash icon lookups only for windows with no icon yet
                    for (let i = 0; i < result.length; i++) {
                        const w = result[i]
                        if (!w.appIcon) {
                            const already = root._iconQueue.some(function(q) { return q.appClass === w.appClassLow })
                            if (!already) root._iconQueue.push({ appClass: w.appClassLow })
                        }
                    }
                    processNextIconLookup()
                } catch(e) {}
            }
        }
    }

    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: root.dockEnabled
        onTriggered: if (!activeAppsQuery.running) activeAppsQuery.running = true
    }

    // Bash fallback icon lookup (only runs when GTK map didn't have the icon)
    Process {
        id: iconLookupProc
        property string _appClass: ""
        property string _buf: ""
        stdout: SplitParser { onRead: iconLookupProc._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const found = iconLookupProc._buf.trim()
                const cls   = iconLookupProc._appClass
                iconLookupProc._buf      = ""
                iconLookupProc._appClass = ""
                if (found !== "" && cls !== "") {
                    const cache = Object.assign({}, root._activeIconCache)
                    cache[cls] = found
                    root._activeIconCache = cache
                    // Patch ALL windows with this class (multiple kitty windows, etc.)
                    root.activeApps = root.activeApps.map(function(a) {
                        if (a.appClassLow !== cls) return a
                        return Object.assign({}, a, { appIcon: found })
                    })
                }
                processNextIconLookup()
            }
        }
    }

    function processNextIconLookup() {
        if (iconLookupProc.running || root._iconQueue.length === 0) return
        const item = root._iconQueue.shift()
        const cls  = item.appClass
        if (root._activeIconCache[cls]) {
            root.activeApps = root.activeApps.map(function(a) {
                if (a.appClassLow !== cls || a.appIcon !== "") return a
                return Object.assign({}, a, { appIcon: root._activeIconCache[cls] })
            })
            processNextIconLookup()
            return
        }
        iconLookupProc._appClass = cls
        iconLookupProc.command = ["bash", "-c",
            "n='" + cls + "'; " +
            // 1. TSV cache
            "f=\"$HOME/.cache/quickshell/dock-apps-v2.tsv\"; " +
            "if [ -f \"$f\" ]; then " +
              "r=$(awk -F'\\t' -v n=\"$n\" '{ ln=tolower($1); if (index(ln, n) > 0 && $3 != \"\") { print $3; exit } }' \"$f\"); " +
              "[ -n \"$r\" ] && echo \"$r\" && exit 0; " +
            "fi; " +
            // 2. Direct icon search by class name
            "icon=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons $HOME/.local/share/pixmaps 2>/dev/null " +
              "-type f \\( -name \"${n}.png\" -o -name \"${n}.svg\" -o -name \"${n}.xpm\" \\) " +
              "| grep -i '48x48\\|scalable\\|256x256\\|128x128' | head -1); " +
            "[ -z \"$icon\" ] && " +
              "icon=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons $HOME/.local/share/pixmaps 2>/dev/null " +
              "-type f \\( -name \"${n}.png\" -o -name \"${n}.svg\" \\) | head -1); " +
            "[ -n \"$icon\" ] && echo \"$icon\" && exit 0; " +
            // 3. Find .desktop by FILENAME containing class (e.g. net.lutris.reverse-1999-game-8.desktop)
            "desktop=$(find /usr/share/applications $HOME/.local/share/applications 2>/dev/null " +
              "-name \"*${n}*.desktop\" -type f | head -1); " +
            // 4. Search by StartupWMClass= content (exact)
            "[ -z \"$desktop\" ] && " +
              "desktop=$(grep -rli \"^StartupWMClass=${n}$\" /usr/share/applications $HOME/.local/share/applications 2>/dev/null | head -1); " +
            // 5. Search by StartupWMClass= partial / Name= / Exec=
            "[ -z \"$desktop\" ] && " +
              "desktop=$(grep -rli \"^StartupWMClass=.*${n}\\|^Name=.*${n}\\|^Exec=.*${n}\" /usr/share/applications $HOME/.local/share/applications 2>/dev/null | head -1); " +
            "if [ -n \"$desktop\" ]; then " +
              "iname=$(grep -m1 '^Icon=' \"$desktop\" | cut -d= -f2); " +
              "[ -z \"$iname\" ] && exit 0; " +
              "[ -f \"$iname\" ] && echo \"$iname\" && exit 0; " +
              "r=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons $HOME/.local/share/pixmaps 2>/dev/null " +
                "-type f \\( -name \"${iname}.png\" -o -name \"${iname}.svg\" \\) " +
                "| grep -i '48x48\\|scalable\\|256x256\\|128x128' | head -1); " +
              "[ -z \"$r\" ] && " +
                "r=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons $HOME/.local/share/pixmaps 2>/dev/null " +
                "-type f \\( -name \"${iname}.png\" -o -name \"${iname}.svg\" \\) | head -1); " +
              "[ -n \"$r\" ] && echo \"$r\"; " +
            "fi"
        ]
        iconLookupProc.running = true
    }

    // ── Focus window — Hyprland Lua API ──────────────────────────────
    function focusWindow(addr, clsOrig) {
        let selector = ""
        if (addr && addr !== "") {
            const a = addr.trim().toLowerCase()
            const hex = a.startsWith("0x") ? a : "0x" + a
            if (hex !== "0x") selector = "address:" + hex
        }
        if (selector === "" && clsOrig && clsOrig !== "")
            selector = "class:" + clsOrig
        if (selector !== "")
            Hyprland.dispatch("hl.dsp.focus({ window = \"" + selector + "\" })")
    }

    // ── Launch ────────────────────────────────────────────────────────
    Process { id: launchProc }
    function launch(cmd) {
        launchProc.command = ["bash", "-c", "nohup " + cmd + " &"]
        launchProc.running = true
    }

    // ── Systray ───────────────────────────────────────────────────────
    property bool systrayOpen: false

    // ── Divider ───────────────────────────────────────────────────────
    component DockDivider: Rectangle {
        width: 1; height: 36; radius: 1
        color: IslandMotion.surfaceBorderColor
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    // ── App button ────────────────────────────────────────────────────
    component AppButton: Item {
        id: appBtn
        property string iconPath:  ""
        property string label:     ""
        property bool   isRunning: false
        signal tapped()
        signal middleClicked()

        width: root.iconSize; height: root.iconSize
        property bool hov: false

        // Appear animation — scale+fade in when button is created
        opacity: 0
        scale: 0.5
        Component.onCompleted: { opacity = 1; scale = 1 }
        Behavior on opacity { NumberAnimation { duration: IslandMotion.standard; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.standard; easing.type: Easing.OutBack  } }

        // Tooltip floats above (outside item bounds, z:20)
        Rectangle {
            y: -(height + 8); z: 20
            anchors.horizontalCenter: parent.horizontalCenter
            visible: appBtn.hov
            width: tooltipTxt.implicitWidth + 14; height: 22; radius: 6
            color: Qt.rgba(0,0,0,0.82)
            border.width: 1; border.color: Qt.rgba(1,1,1,0.15)
            Text {
                id: tooltipTxt; renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: appBtn.label; color: "white"
                font.pixelSize: 11; font.family: root.textFontFamily
            }
        }

        Item {
            id: iconArea; anchors.centerIn: parent
            width: root.iconSize; height: root.iconSize
            transform: Translate {
                y: appBtn.hov ? -5 : 0
                Behavior on y { NumberAnimation { duration: IslandMotion.fast; easing.type: Easing.OutBack } }
            }

            Image {
                id: iconImg; anchors.fill: parent; anchors.margins: 2
                source:   appBtn.iconPath !== "" ? "file://" + appBtn.iconPath : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true; smooth: true
                visible:  status === Image.Ready
                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
            }

            // Fallback letter tile when image not loaded
            Rectangle {
                anchors.fill: parent; anchors.margins: 4
                visible: !iconImg.visible; radius: 10
                color: Qt.rgba(1,1,1,0.12)
                border.width: 1; border.color: Qt.rgba(1,1,1,0.20)
                Text {
                    renderType: Text.NativeRendering; anchors.centerIn: parent
                    text:  appBtn.label.length > 0 ? appBtn.label[0].toUpperCase() : "?"
                    color: "white"; font.pixelSize: 18
                    font.family: root.textFontFamily; font.weight: Font.Medium
                }
            }

            // Running dot — 4 px below icon
            Rectangle {
                visible: appBtn.isRunning
                width: 4; height: 4; radius: 2; color: "white"; opacity: 0.85
                anchors.top: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 4
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: iconArea
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onEntered: { appBtn.hov = true; hoverExitTimer.stop(); root.hoverPeeking = true }
            onExited:  { appBtn.hov = false; hoverExitTimer.restart() }
            onClicked: (mouse) => {
                if (mouse.button === Qt.MiddleButton) appBtn.middleClicked()
                else appBtn.tapped()
            }
        }
    }

    // Hover zone over the visible pill — must be a SIBLING of pill, not a child,
    // because Translate only moves rendering; child MouseAreas stay at layout coords.
    // Tracks pill's visual position: pill.y (layout) + pill.slideY (Translate offset)
    // + the pillH band at the bottom of the pill item.
    MouseArea {
        x:      pill.x
        y:      pill.y + pill.slideY + (pill.height - root.pillH)
        width:  pill.width
        height: root.pillH
        hoverEnabled: true; acceptedButtons: Qt.NoButton; propagateComposedEvents: true
        onEntered: { hoverExitTimer.stop(); root.hoverPeeking = true }
        onExited:  hoverExitTimer.restart()
        z: -1
    }

    // ═══════════════════════════════════════════════════════════════════
    // ── Pill ─────────────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════
    Item {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom:           parent.bottom
        anchors.bottomMargin:     10

        width:          pillRow.implicitWidth + root.edgePad * 2
        implicitWidth:  width
        height:         root.pillH + 20   // +20 for tooltip headroom above
        implicitHeight: height

        // slideY: 0 when visible, positive = slid off bottom
        property real slideY: root.pillActuallyVisible ? 0 : (root.pillH + 30)
        transform: Translate { y: pill.slideY }
        Behavior on slideY {
            NumberAnimation { duration: IslandMotion.standard; easing.type: IslandMotion.easeArrive }
        }

        // Pill background sits in the lower pillH band
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: root.pillH; radius: height / 2
            color:  root.pillColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            Behavior on color { ColorAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove } }
        }

        // Content row — centred in pillH, shifted up 4px for running dot room
        Row {
            id: pillRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom:           parent.bottom
            anchors.bottomMargin:     (root.pillH - root.iconSize) / 2 + 4
            spacing: root.iconGap

            // ── Favourites ─────────────────────────────────────────────
            Repeater {
                model: root.favApps
                delegate: AppButton {
                    iconPath:  modelData.appIcon
                    label:     modelData.appName
                    isRunning: {
                        const wc = modelData.appWmClass || ""
                        const ex = (modelData.appExec || "").split("/").pop().toLowerCase().replace(/\s.*/, "")
                        const nm = (modelData.appName || "").toLowerCase()
                        return root.allWindows.some(function(a) {
                            const acl = a.appClassLow || ""
                            if (wc && wc.length > 0 && (wc === acl || acl.startsWith(wc) || wc.startsWith(acl))) return true
                            if (ex && ex.length > 2 && (ex === acl || acl.startsWith(ex) || ex.startsWith(acl) || acl.includes(ex) || ex.includes(acl))) return true
                            if (nm && nm.length > 3 && (acl.includes(nm) || nm.includes(acl))) return true
                            return false
                        })
                    }
                    onTapped: {
                        const wc = modelData.appWmClass || ""
                        const ex = (modelData.appExec || "").split("/").pop().toLowerCase().replace(/\s.*/, "")
                        const nm = (modelData.appName || "").toLowerCase()
                        let win = null
                        for (let i = 0; i < root.allWindows.length; i++) {
                            const a = root.allWindows[i]
                            const acl = a.appClassLow || ""
                            if (wc && wc.length > 0 && (wc === acl || acl.startsWith(wc) || wc.startsWith(acl))) { win = a; break }
                            if (ex && ex.length > 2 && (ex === acl || acl.startsWith(ex) || ex.startsWith(acl) || acl.includes(ex) || ex.includes(acl))) { win = a; break }
                            if (nm && nm.length > 3 && (acl.includes(nm) || nm.includes(acl))) { win = a; break }
                        }
                        if (win) root.focusWindow(win.appAddress, win.appClass)
                        else     root.launch(modelData.appExec)
                    }
                }
            }

            DockDivider { visible: root.favApps.length > 0 && root.activeApps.length > 0 }

            // ── Active non-favourite windows (ALL windows, not one per class) ──
            Repeater {
                model: root.activeApps
                delegate: AppButton {
                    iconPath:  modelData.appIcon
                    label:     modelData.appName
                    isRunning: true
                    onTapped:        root.focusWindow(modelData.appAddress, modelData.appClass)
                    onMiddleClicked: {
                        let raw = String(modelData.appAddress).trim().toLowerCase()
                        if (!raw.startsWith("0x")) raw = "0x" + raw
                        const sel = "address:" + raw
                        Hyprland.dispatch("hl.dsp.window.close({ window = \"" + sel + "\" })")
                    }
                }
            }

            DockDivider {}

            // ── Systray slide-in ───────────────────────────────────────
            Row {
                id: trayIconsRow
                spacing: root.iconGap
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                width: root.systrayOpen
                    ? (trayRepeater.count * (root.iconSize - 12 + root.iconGap) + root.iconGap * 2 + 1)
                    : 0
                Behavior on width {
                    NumberAnimation { duration: IslandMotion.standard; easing.type: IslandMotion.easeArrive }
                }

                Repeater {
                    id: trayRepeater
                    model: SystemTray.items
                    delegate: Item {
                        id: trayDel
                        width: root.iconSize - 12; height: root.iconSize - 12
                        anchors.verticalCenter: parent.verticalCenter

                        PopupWindow {
                            id: trayPopup
                            visible: false; color: "transparent"
                            anchor.item: trayDel
                            anchor.rect.x: -(130 - trayDel.width / 2)
                            anchor.rect.y: -(trayDel.height + 8 + 120)
                            implicitWidth: 260
                            implicitHeight: trayMenuCol.implicitHeight + 16

                            QsMenuOpener { id: trayOpener; menu: modelData.hasMenu ? modelData.menu : null }

                            Rectangle {
                                anchors.fill: parent; color: "#1e1e1e"; radius: 8
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
                                                width: parent.width; height: modelData.isSeparator ? 0 : 28
                                                visible: !modelData.isSeparator; radius: 4
                                                color: miArea.containsMouse ? "#333333" : "transparent"
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Text {
                                                    renderType: Text.NativeRendering
                                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                                                    text: (modelData.text || "") + (modelData.hasChildren ? " ▶" : "")
                                                    color: miArea.containsMouse ? "white" : Qt.rgba(1,1,1,0.75)
                                                    font.pixelSize: 12
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                                MouseArea {
                                                    id: miArea; anchors.fill: parent
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
                                                        width: parent.width; height: modelData.isSeparator ? 0 : 28
                                                        visible: !modelData.isSeparator; radius: 4
                                                        color: subArea.containsMouse ? "#333333" : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                        Text {
                                                            renderType: Text.NativeRendering
                                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 16 }
                                                            text: modelData.text || ""
                                                            color: subArea.containsMouse ? "white" : Qt.rgba(1,1,1,0.75)
                                                            font.pixelSize: 12
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }
                                                        MouseArea {
                                                            id: subArea; anchors.fill: parent
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
                            fillMode: Image.PreserveAspectFit; visible: status === Image.Ready
                            sourceSize: Qt.size((root.iconSize-12)*2, (root.iconSize-12)*2)
                            opacity: trayMA.containsMouse ? 1.0 : 0.75
                            scale:   trayMA.containsMouse ? 1.15 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        }
                        Rectangle {
                            anchors.fill: parent; color: "transparent"
                            visible: !trayImg.visible
                            Text {
                                renderType: Text.NativeRendering; anchors.centerIn: parent
                                text: modelData.title ? modelData.title[0] : "?"
                                color: "white"; font.pixelSize: root.iconSize - 20
                                opacity: trayMA.containsMouse ? 1.0 : 0.75
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: trayMA
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: { hoverExitTimer.stop(); root.hoverPeeking = true }
                            onExited:  hoverExitTimer.restart()
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton || modelData.onlyMenu)
                                    trayPopup.visible = !trayPopup.visible
                                else if (modelData.activate)
                                    modelData.activate()
                            }
                        }
                    }
                }

                DockDivider {
                    visible: root.systrayOpen && trayRepeater.count > 0
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ── Chevron ›/‹ ───────────────────────────────────────────
            Item {
                width: root.iconSize; height: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    id: chevImg; anchors.centerIn: parent; width: 26; height: 26
                    source: Quickshell.shellDir + "/qml/shared/assets/chevron-double-left.svg"
                    sourceSize: Qt.size(52, 52); fillMode: Image.PreserveAspectFit
                    rotation: root.systrayOpen ? 0 : 180
                    opacity: chevMA.containsMouse ? 1.0 : 0.70
                    scale:   chevMA.containsMouse ? 1.15 : (chevMA.pressed ? 0.85 : 1.0)
                    Behavior on opacity  { NumberAnimation { duration: IslandMotion.micro } }
                    Behavior on scale    { NumberAnimation { duration: IslandMotion.fast; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: IslandMotion.standard; easing.type: IslandMotion.easeArrive } }
                }
                MouseArea {
                    id: chevMA; anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onEntered: { hoverExitTimer.stop(); root.hoverPeeking = true }
                    onExited:  hoverExitTimer.restart()
                    onClicked: root.systrayOpen = !root.systrayOpen
                }
            }
        }
    }


}