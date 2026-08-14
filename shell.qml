import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import IslandBackend
import "qml/shared"
import "qml/sidebar"

Scope {
    id: shellRoot

    // ── Global Font Loaders ─────────────────────────────────────────────
    // Font paths are defined in qml/shared/IslandConfiguration.qml
    FontLoader { id: mainFont; source: IslandConfiguration.fontRegular }
    FontLoader { source: IslandConfiguration.fontMedium }
    FontLoader { source: IslandConfiguration.fontBold }

    readonly property bool screenRecordingActive: SystemServices.screenRecordingActive
    property bool shuttingDown: false

    readonly property var userConfig: UserConfig

    function forEachWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window)
                callback(window);
        }
    }

    function showNotificationAll(appName, summary, body) {
        if (shellRoot.sidebarActive) {
            // Sidebar is visible — only route to sidebar windows
            const sidebarWindows = sidebarVariants.instances ? sidebarVariants.instances : [];
            for (let i = 0; i < sidebarWindows.length; i++) {
                const sw = sidebarWindows[i];
                if (sw && sw.showNotification)
                    sw.showNotification(appName, summary, body);
            }
        } else {
            // Main bar is visible — only route to island windows
            shellRoot.forEachWindow((window) => {
                if (window && window.showNotification)
                    window.showNotification(appName, summary, body);
            });
        }
    }

    function sidebarToggleAppLauncher() {
        const sw = sidebarVariants.instances[0]
        if (sw) sw.ipcToggleAppLauncher()
    }
    function sidebarToggleControlCenter() {
        const sw = sidebarVariants.instances[0]
        if (sw) sw.ipcToggleControlCenter()
    }
    function sidebarTogglePowerMenu() {
        const sw = sidebarVariants.instances[0]
        if (sw) sw.ipcTogglePowerMenu()
    }
    function sidebarToggleNotifCenter() {
        const sw = sidebarVariants.instances[0]
        if (sw) sw.ipcToggleNotifCenter()
    }

    function anyOverviewOpen() {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.overviewPhase !== "closed")
                return true;
        }

        return false;
    }

    function prepareOverviewAll() {
        shellRoot.forEachWindow((window) => window.prepareOverview());
    }

    function cancelPreparedOverviewAll() {
        shellRoot.forEachWindow((window) => window.cancelPreparedOverview());
    }

    function openOverviewAll() {
        shellRoot.forEachWindow((window) => window.openOverview());
    }

    function closeOverviewAll() {
        shellRoot.forEachWindow((window) => window.closeOverview());
    }

    function toggleOverviewAll() {
        if (shellRoot.anyOverviewOpen())
            shellRoot.closeOverviewAll();
        else
            shellRoot.openOverviewAll();
    }

    IpcHandler {
        target: "overview"

        function toggle() {
            shellRoot.toggleOverviewAll();
        }

        function open() {
            shellRoot.openOverviewAll();
        }

        function close() {
            shellRoot.closeOverviewAll();
        }

        function refreshWallpaperCache() {
            shellRoot.forEachWindow((window) => {
                if (window && window.prewarmWallpaperCache)
                    window.prewarmWallpaperCache();
            });
        }
    }

    GlobalShortcut {
        appid: userConfig.overviewGlobalShortcutAppid
        name: userConfig.overviewGlobalShortcutName

        onPressed: shellRoot.toggleOverviewAll()
    }

    // ── Notification Sound ───────────────────────────────────────────────
    // Query DND fresh on every notification so there's no stale cache
    // window where DND is on but the old poll value says otherwise.
    property bool _pendingSound: false

    Process {
        id: shellDndQuery
        property string _buf: ""
        command: ["bash", "-c", "swaync-client -D 2>/dev/null"]
        stdout: SplitParser { onRead: shellDndQuery._buf += data }
        onRunningChanged: {
            if (!running) {
                const dnd = shellDndQuery._buf.trim() === "true"
                shellDndQuery._buf = ""
                if (shellRoot._pendingSound && !dnd)
                    notificationSound.play()
                shellRoot._pendingSound = false
            }
        }
    }

    SoundEffect {
        id: notificationSound
        source: Quickshell.shellDir + "/qml/shared/assets/sounds/notification.wav"
        volume: IslandConfiguration.notificationSoundVolume / 100.0
    }

    Connections {
        target: SystemServices

        function onNotificationReceived(appName, summary, body) {
            shellRoot.showNotificationAll(appName, summary, body);
            if (IslandConfiguration.notificationSoundEnabled) {
                shellRoot._pendingSound = true
                shellDndQuery.running = true
            }
        }
    }

    property bool sidebarActive: false

    // ── Dock shared state — synced from DynamicIslandWindow ─────────────
    property bool   dockEnabled:        true
    property string dockMode:           "pin"
    property bool   gamemodeActive:     false
    property real   capsuleOpacity:     0.20
    property bool   capsuleUseWalColor: false
    property color  capsuleWalColor:    "#000000"

    property real _lastVolume: -1
    property real _lastBrightness: -1

    Connections {
        target: SysBackend

        function onVolumeChanged(volPercentage, isMuted) {
            if (!shellRoot.sidebarActive) return
            const level = volPercentage / 100.0
            if (Math.abs(level - shellRoot._lastVolume) < 0.01 && shellRoot._lastVolume >= 0) return
            shellRoot._lastVolume = level
            const instances = osdVariants.instances ?? []
            for (let i = 0; i < instances.length; i++)
                if (instances[i]) instances[i].showVolume(level, isMuted)
        }

        function onBrightnessChanged(value) {
            if (!shellRoot.sidebarActive) return
            if (Math.abs(value - shellRoot._lastBrightness) < 0.01 && shellRoot._lastBrightness >= 0) return
            shellRoot._lastBrightness = value
            const instances = osdVariants.instances ?? []
            for (let i = 0; i < instances.length; i++)
                if (instances[i]) instances[i].showBrightness(value)
        }
    }

    Component.onDestruction: {
        shuttingDown = true;
    }

    Component.onCompleted: {
        if (mainFont.name !== "") {
            Qt.application.font.family = mainFont.name;
        }

        SystemServices.ensureSetupComplete(Quickshell.shellDir);
        SystemServices.requestScreenRecordingSnapshot();
    }

    Variants {
        id: panelVariants
        model: Quickshell.screens
        DynamicIslandWindow {
            required property var modelData
            screen: modelData
            shellRootController: shellRoot

            // Sync appearance state up to shellRoot so BubbleDockWindow can bind to it
            onGamemodeActiveChanged:      if (shellRoot.gamemodeActive     !== gamemodeActive)      shellRoot.gamemodeActive     = gamemodeActive
            onCapsuleOpacityChanged:      if (shellRoot.capsuleOpacity     !== capsuleOpacity)      shellRoot.capsuleOpacity     = capsuleOpacity
            onCapsuleUseWalColorChanged:  if (shellRoot.capsuleUseWalColor !== capsuleUseWalColor)  shellRoot.capsuleUseWalColor = capsuleUseWalColor
            onCapsuleWalColorChanged:     if (shellRoot.capsuleWalColor    !== capsuleWalColor)     shellRoot.capsuleWalColor    = capsuleWalColor
            onDockEnabledChanged:         shellRoot.dockEnabled = dockEnabled
            onDockModeChanged:            shellRoot.dockMode    = dockMode
        }
    }

    // ── Sidebar pill — one per screen, self-contained polling inside
    // SidebarWindow.qml keeps this block clean. ──────────────────────
    Variants {
        id: sidebarVariants
        model: Quickshell.screens
        SidebarWindow {
            required property var modelData
            screen: modelData
            onSidebarEnabledChanged: shellRoot.sidebarActive = sidebarEnabled
        }
    }

    // ── Sidebar OSD toast — volume/brightness, one per screen ────────
    Variants {
        id: osdVariants
        model: Quickshell.screens
        SidebarOsdToast {
            required property var modelData
            screen: modelData
            textFontFamily: shellRoot.userConfig.textFontFamily
            iconFontFamily: shellRoot.userConfig.iconFontFamily
        }
    }

    // ── Bubble Dock — one per screen ────────────────────────────────────
    Variants {
        id: dockVariants
        model: Quickshell.screens
        BubbleDockWindow {
            required property var modelData
            screen:              modelData
            dockEnabled:         shellRoot.dockEnabled
            dockMode:            shellRoot.dockMode
            sidebarActive:       shellRoot.sidebarActive
            gamemodeActive:      shellRoot.gamemodeActive
            capsuleOpacity:      shellRoot.capsuleOpacity
            capsuleUseWalColor:  shellRoot.capsuleUseWalColor
            capsuleWalColor:     shellRoot.capsuleWalColor
            iconFontFamily:      shellRoot.userConfig.iconFontFamily
            textFontFamily:      shellRoot.userConfig.textFontFamily
        }
    }

    // One instance only, following whichever monitor is currently
    // focused. Toggled via `qs ipc call wallpaper-picker toggle`
    WallpaperPickerWindow {
        screen: Hyprland.focusedMonitor
            ? (Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0])
            : Quickshell.screens[0]
    }
}
