import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import IslandBackend
import "../shared"

Item {
    id: root

    property string iconFontFamily: ""
    property string textFontFamily: ""

    property bool showCondition: true

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

    signal closeRequested()
    signal launchRequested(string cmd, bool isCommand)

    readonly property int inputRowHeight: 44
    readonly property int iconCellSize: 92        
    readonly property int iconSize: 40             
    readonly property int gridRowCount: 3   
    readonly property int gridTopMargin: 10  
    readonly property int gridSideMargin: 14
    readonly property int gridBottomMargin: 12

    readonly property int minCols: 6
    readonly property int maxCols: 10
    readonly property int appCountForLayout: isWallpaperMode
        ? 0
        : (filteredApps.length > 0 ? filteredApps.length : allApps.length)
    readonly property int gridCols: {
        if (isWallpaperMode) return wallpaperHubLoader.item ? wallpaperHubLoader.item.gridCols : 8
        let need = Math.ceil(appCountForLayout / gridRowCount)
        return Math.max(minCols, Math.min(maxCols, need))
    }

    readonly property bool hasResults: true   
    readonly property int footerHeight: 18    
    readonly property int appGridHeight: gridTopMargin + (iconCellSize * gridRowCount) + gridBottomMargin + footerHeight

    property int capsuleWidth: isWallpaperMode
        ? (wallpaperHubLoader.item
            ? (wallpaperHubLoader.item.viewMode, wallpaperHubLoader.item.capsuleWidth)
            : 700)
        : Math.max(620, gridCols * iconCellSize + gridSideMargin * 2)
    property int capsuleHeight: isWallpaperMode
        ? (wallpaperHubLoader.item
            ? (wallpaperHubLoader.item.viewMode, root.inputRowHeight + wallpaperHubLoader.item.capsuleHeight)
            : (inputRowHeight + 334))
        : (inputRowHeight + appGridHeight)

    property bool isCommandMode: false
    readonly property bool isLoading: appCacheLoader.running
    property var filteredApps: []
    property var allApps: []
    property var displayApps: filteredApps

    property var favoritesSet: ({})

    function isFavorite(execKey) {
        return !!execKey && root.favoritesSet[execKey] === true
    }

    function toggleFavorite(execKey) {
        if (!execKey) return
        let next = Object.assign({}, root.favoritesSet)
        if (next[execKey]) delete next[execKey]
        else next[execKey] = true
        root.favoritesSet = next
        saveFavoritesProcess.persist(next)
        rebuildFiltered()
    }

    Process {
        id: loadFavoritesProcess
        command: ["bash", "-c",
            "f=\"$HOME/.cache/quickshell/search-favorites.json\"; [ -f \"$f\" ] && cat \"$f\" || printf '{}'"]
        property string _buf: ""
        stdout: SplitParser { onRead: loadFavoritesProcess._buf += data }
        onRunningChanged: {
            if (!running) {
                try {
                    const parsed = JSON.parse(loadFavoritesProcess._buf.trim() || "{}")
                    const favs = Array.isArray(parsed.favorites) ? parsed.favorites : []
                    const set = {}
                    for (let i = 0; i < favs.length; i++) set[favs[i]] = true
                    root.favoritesSet = set
                    root.rebuildFiltered()
                } catch (e) {
                    
                }
                loadFavoritesProcess._buf = ""
            }
        }
    }

    Process {
        id: saveFavoritesProcess
        function persist(setObj) {
            const list = Object.keys(setObj)
            const json = JSON.stringify({ favorites: list })
            const escaped = json.replace(/'/g, "'\\''")
            command = ["bash", "-c",
                "mkdir -p \"$HOME/.cache/quickshell\" && printf '%s' '" + escaped +
                "' > \"$HOME/.cache/quickshell/search-favorites.json\""]
            running = true
        }
    }
    property string searchText: ""

    readonly property bool isWallpaperMode: {
        let q = searchText.trim().toLowerCase()
        return q === "wallpaper"   || q === "wallpapers" ||
               q === "wp"          || q === "background"  ||
               q === "backgrounds" || q === "bg"          ||
               q.startsWith("wallpaper ") || q.startsWith("wp ")
    }
    property int selectedIndex: 0

    onIsWallpaperModeChanged: {
        if (isWallpaperMode) {
            
            wallpaperFocusTimer.restart()
        } else {
            
            searchInput.text = ""
            root.searchText = ""
            searchInput.forceActiveFocus()
        }
    }

    Timer {
        id: wallpaperFocusTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (wallpaperHubLoader.item) wallpaperHubLoader.item.focusInput()
        }
    }

    onSearchTextChanged: {
        selectedIndex = 0
        rebuildFiltered()
    }

    property string lastAppsJson: ""
    property bool appsLoaded: false

    function loadApps() {
        if (appsLoaded) {
            rebuildFiltered()
        }
        if (!appCacheLoader.running) {
            appCacheLoader.running = true
        }
    }

    Process {
        id: appCacheLoader
        command: ["python3", Quickshell.shellDir + "/scripts/list-apps.py"]
        property string _buf: ""

        stdout: SplitParser {
            onRead: { appCacheLoader._buf += data }
        }
        onRunningChanged: {
            if (!running) {
                const out = appCacheLoader._buf
                appCacheLoader._buf = ""
                try {
                    if (out.trim().length === 0 || out === root.lastAppsJson) return
                    const parsed = JSON.parse(out)
                    if (!Array.isArray(parsed)) return

                    root.lastAppsJson = out
                    root.allApps = parsed.map(function(a) {
                        return {
                            appName: a.name || "",
                            appExec: a.exec || "",
                            appIcon: a.icon || "",
                            appKeys: a.keywords || ""
                        }
                    })
                    root.appsLoaded = true
                    root.rebuildFiltered()
                } catch (e) {
                    
                }
            }
        }
    }

    function focusInput() {
        searchInput.forceActiveFocus()
    }

    function inputHasFocus() {
        return searchInput.activeFocus || (wallpaperHubLoader.item && wallpaperHubLoader.item.inputHasFocus && wallpaperHubLoader.item.inputHasFocus())
    }

    onVisibleChanged: {
        if (visible) {
            searchInput.text = ""
            selectedIndex = 0
            loadApps()
            if (root.isWallpaperMode) wallpaperFocusTimer.restart()
            else searchInput.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        loadApps()
        loadFavoritesProcess.running = true
        searchInput.forceActiveFocus()
    }

    function rebuildFiltered() {
        if (isWallpaperMode) {
            
            return
        }

        let q = searchText.toLowerCase().trim()
        if (q === "") {
            let favs = []
            let rest = []
            for (let i = 0; i < allApps.length; i++) {
                if (isFavorite(allApps[i].appExec)) favs.push(allApps[i])
                else rest.push(allApps[i])
            }
            filteredApps = favs.concat(rest)
        } else {
            filteredApps = allApps.filter(a =>
                a.appName.toLowerCase().includes(q) ||
                (a.appKeys && a.appKeys.toLowerCase().includes(q))
            )
        }

        let raw = searchText.trim()
        isCommandMode = raw.length > 0 && (
            raw.startsWith("/") ||
            raw.includes(" ") ||
            (filteredApps.length === 0 && raw.length > 1)
        )
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        propagateComposedEvents: true
        enabled: !root.isWallpaperMode
        onEntered: searchInput.forceActiveFocus()
        onClicked: (mouse) => mouse.accepted = false
        onPressed: (mouse) => mouse.accepted = false
    }

    Column {
        id: contentColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        Item {
            width: parent.width
            height: root.inputRowHeight

            Row {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    renderType: Text.NativeRendering
                    text: root.isCommandMode ? "\uf120" : "\uf002"
                    font.family: root.iconFontFamily
                    font.pixelSize: 14
                    color: root.isCommandMode ? "#a78bfa" : "white"
                    opacity: root.isCommandMode ? 0.9 : 0.5
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: IslandMotion.micro } }
                }

                TextInput {
                    id: searchInput
                    renderType: TextInput.NativeRendering
                    width: root.capsuleWidth - 60
                    height: 38
                    color: "white"
                    font.pixelSize: 14
                    font.family: root.textFontFamily
                    verticalAlignment: TextInput.AlignVCenter
                    activeFocusOnPress: true
                    clip: true
                    
                    enabled: !root.isWallpaperMode

                    onTextChanged: root.searchText = text

                    Keys.onEscapePressed: root.closeRequested()
                    Keys.onReturnPressed: {
                        if (root.isCommandMode) {
                            root.launchRequested(
                                "kitty -- bash -c " + JSON.stringify(root.searchText + "; echo; read -rsp 'Press any key...' -n1"),
                                true
                            )
                        } else if (root.filteredApps.length > 0) {
                            root.launchRequested(root.filteredApps[root.selectedIndex].appExec, false)
                        }
                    }
                    Keys.onLeftPressed: {
                        if (!root.isCommandMode && root.filteredApps.length > 0)
                            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                    }
                    Keys.onRightPressed: {
                        if (!root.isCommandMode && root.filteredApps.length > 0)
                            root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + 1)
                    }
                    Keys.onUpPressed: {
                        if (!root.isCommandMode && root.filteredApps.length > 0)
                            root.selectedIndex = Math.max(0, root.selectedIndex - root.gridCols)
                    }
                    Keys.onDownPressed: {
                        if (!root.isCommandMode && root.filteredApps.length > 0)
                            root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + root.gridCols)
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Search apps or run a command…"
                        color: "white"; opacity: 0.25
                        font.pixelSize: 14; font.family: root.textFontFamily
                        visible: searchInput.text.length === 0
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    text: "\uf00d"
                    font.family: root.iconFontFamily
                    font.pixelSize: 12
                    color: "white"
                    opacity: closeMouse.containsMouse ? 0.7 : 0.3
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length > 0
                    Behavior on opacity { NumberAnimation { duration: IslandMotion.micro } }
                    MouseArea {
                        id: closeMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: { searchInput.text = ""; searchInput.forceActiveFocus() }
                    }
                }
            }
        }

        Loader {
            id: wallpaperHubLoader
            width: parent.width
            height: item ? item.height : 0
            active: root.isWallpaperMode
            visible: active
            asynchronous: false

            sourceComponent: Component {
                WallpaperHub {
                    iconFontFamily: root.iconFontFamily
                    textFontFamily: root.textFontFamily
                    onCloseRequested: root.closeRequested()
                }
            }
        }

        Item {
            width: parent.width
            height: root.appGridHeight
            visible: root.isCommandMode && !root.isWallpaperMode

            Column {
                anchors.centerIn: parent
                spacing: 10

                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\uf120"
                    font.family: root.iconFontFamily
                    font.pixelSize: 28
                    color: "white"; opacity: 0.2
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Run in terminal"
                    color: "white"; opacity: 0.4
                    font.pixelSize: 11; font.family: root.textFontFamily
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(cmdRunLabel.implicitWidth + 32, 460)
                    height: 36; radius: 12
                    color: cmdRunMouse.containsMouse
                           ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.12)
                    Behavior on color { ColorAnimation { duration: IslandMotion.micro } }
                    scale: cmdRunMouse.pressed ? 0.97 : 1.0
                    Behavior on scale {
                        NumberAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeSpring }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        id: cmdRunLabel
                        anchors.centerIn: parent
                        text: "\uf120  " + root.searchText
                        color: "white"; font.pixelSize: 13
                        font.family: "monospace"; font.weight: Font.Bold
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 430)
                    }
                    MouseArea {
                        id: cmdRunMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            root.launchRequested(
                                "kitty -- bash -c " + JSON.stringify(root.searchText + "; echo; read -rsp 'Press any key...' -n1"),
                                true
                            )
                        }
                    }
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Press Enter or click above"
                    color: "white"; opacity: 0.25
                    font.pixelSize: 9; font.family: root.textFontFamily
                }
            }
        }

        GridView {
            id: searchGridView
            width: parent.width
            height: root.appGridHeight - root.footerHeight
            anchors.leftMargin: root.gridSideMargin
            anchors.rightMargin: root.gridSideMargin
            visible: !root.isCommandMode && !root.isWallpaperMode
            clip: true

            cellWidth: Math.floor((root.capsuleWidth - root.gridSideMargin * 2) / Math.max(1, root.gridCols))
            cellHeight: root.iconCellSize

            model: root.filteredApps

            interactive: true
            boundsBehavior: Flickable.StopAtBounds

            property int trackedIndex: root.selectedIndex
            onTrackedIndexChanged: {
                let row = Math.floor(trackedIndex / Math.max(1, root.gridCols))
                let rowY = row * cellHeight
                let visibleTop = contentY
                let visibleBottom = contentY + height

                if (rowY < visibleTop) {
                    contentY = rowY
                } else if (rowY + cellHeight > visibleBottom) {
                    contentY = rowY + cellHeight - height
                }
            }

            delegate: Item {
                width: GridView.view.cellWidth
                height: GridView.view.cellHeight

                property var app: modelData || {}
                property bool isSelected: root.selectedIndex === index

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 6
                    height: parent.height - 6
                    radius: 14
                    color: parent.isSelected
                           ? Qt.rgba(1, 1, 1, 0.16)
                           : (gridAppMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0))
                    Behavior on color { ColorAnimation { duration: IslandMotion.micro } }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Item {
                        width: root.iconSize; height: root.iconSize
                        anchors.horizontalCenter: parent.horizontalCenter
                        scale: parent.parent.parent.isSelected ? 1.12
                               : (gridAppMouse.containsMouse ? 1.08 : 1.0)
                        Behavior on scale {
                            NumberAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeSpring }
                        }

                        Image {
                            id: gridAppIcon
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true; cache: true
                            source: app.appIcon && app.appIcon !== ""
                                    ? "file://" + app.appIcon : ""
                        }
                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: "\uf1b2"
                            font.family: root.iconFontFamily
                            font.pixelSize: root.iconSize * 0.7
                            color: "white"; opacity: 0.2
                            visible: gridAppIcon.status !== Image.Ready
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -4
                            anchors.topMargin: -4
                            text: "\u2605"
                            font.pixelSize: 11
                            color: IslandMotion.textPrimary
                            visible: root.isFavorite(app.appExec)
                            opacity: 0.9
                            z: 2
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: app.appName || ""
                        color: "white"
                        opacity: parent.parent.isSelected ? 0.95 : 0.65
                        font.pixelSize: 9
                        font.family: root.textFontFamily
                        font.weight: parent.parent.isSelected ? Font.Medium : Font.Normal
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Behavior on opacity { NumberAnimation { duration: IslandMotion.micro } }
                    }
                }

                MouseArea {
                    id: gridAppMouse
                    anchors.fill: parent; hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: root.selectedIndex = index
                    onClicked: (mouse) => {
                        root.selectedIndex = index
                        if (mouse.button === Qt.RightButton) {
                            root.toggleFavorite(app.appExec)
                        } else {
                            root.launchRequested(app.appExec, false)
                        }
                    }
                }
            }
        }

        Text {
            renderType: Text.NativeRendering
            width: parent.width
            height: root.footerHeight
            visible: !root.isCommandMode && !root.isWallpaperMode
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: {
                if (root.isLoading) return "Loading…"
                if (root.searchText.trim() === "" && Object.keys(root.favoritesSet).length === 0)
                    return "Right-click to favorite"
                return root.filteredApps.length + " apps"
            }
            color: IslandMotion.textFaint
            font.pixelSize: 10
            font.family: root.textFontFamily
            opacity: 0.85
        }
    }
}
