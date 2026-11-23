import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// Nothing OS 点阵灵动岛顶栏：
// - 收起态：居中纯黑胶囊，滚轮/横滑在「时间+电源」与「实时歌词」两态间切换；左键展开面板，右键呼出 Glyph 控制中心；拖入文件自动张开暂存器
// - 展开态：贴顶液态内凹耳朵变形，顶部切换栏（CALENDAR · FOCUS · NOTES · SHELF）
Scope {
    id: root

    signal powerRequested
    signal settingsRequested
    signal portalRequested
    signal vpnRequested

    property var openScreen: null
    property string panelMode: ""  // "" | "quick" (左键控制中心) | "tabs" (右键日历/专注/便签/暂存)
    property string lastMode: "quick"
    property int activeTab: 0      // 0=CALENDAR, 1=FOCUS, 2=NOTES, 3=SHELF
    property int capsuleMode: 0    // 0=时间+电源, 1=实时歌词
    property bool wantNoteFocus: false
    property int calShift: 0

    readonly property var tabs: [
        { id: "cal",   icon: "\u{F00ED}", label: "CALENDAR" },
        { id: "focus", icon: "\u{F051B}", label: "FOCUS" },
        { id: "notes", icon: "\u{F03A4}", label: "NOTES" },
        { id: "shelf", icon: "\u{F0256}", label: "SHELF" }
    ]

    function targetScreen() {
        return Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null;
    }

    function close() {
        panelMode = "";
        openScreen = null;
        wantNoteFocus = false;
    }

    function toggleQuick() {
        if (openScreen && panelMode === "quick") {
            close();
        } else {
            lastMode = "quick";
            panelMode = "quick";
            wantNoteFocus = false;
            openScreen = targetScreen();
        }
    }

    function toggleOpen() {
        if (openScreen && panelMode === "tabs") {
            close();
        } else {
            lastMode = "tabs";
            panelMode = "tabs";
            calShift = 0;
            openScreen = targetScreen();
        }
    }

    function toggleTab(idx) {
        if (openScreen && panelMode === "tabs" && activeTab === idx) {
            close();
        } else {
            lastMode = "tabs";
            panelMode = "tabs";
            activeTab = idx;
            calShift = 0;
            wantNoteFocus = (idx === 2);
            openScreen = targetScreen();
        }
    }

    // 仅在切到歌词模式时启动后台 lyricsmpris 流
    Binding { target: LyricsFeed; property: "active"; value: root.capsuleMode === 1 }

    // ---- 便签持久化 (~/.local/state/rice/memos.json，无损沿用之前已存便签) ----
    Component.onCompleted: memoFile.waitForJob()

    FileView {
        id: memoFile
        path: Theme.riceState + "/memos.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: Qt.callLater(memoFile.writeAdapter)
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: memoStore
            property var items: []
        }
    }

    readonly property var sortedMemos: {
        const arr = (memoStore.items ?? []).slice();
        arr.sort((a, b) => (Number(!!b.pinned) - Number(!!a.pinned))
                        || (Number(!!a.done) - Number(!!b.done))
                        || ((b.ts ?? 0) - (a.ts ?? 0)));
        return arr;
    }
    readonly property int doneCount: (memoStore.items ?? []).filter(m => m.done).length

    function addMemo(raw) {
        const txt = String(raw || "").trim();
        if (!txt) return false;
        const now = new Date();
        const stamp = `${String(now.getMonth() + 1).padStart(2, "0")}/${String(now.getDate()).padStart(2, "0")} ${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
        memoStore.items = [{
            id: String(Date.now()) + Math.random().toString(16).slice(2, 6),
            text: txt,
            done: false,
            pinned: false,
            time: stamp,
            ts: Date.now()
        }].concat(memoStore.items ?? []);
        return true;
    }
    function toggleDone(id) {
        memoStore.items = (memoStore.items ?? []).map(m => m.id === id ? Object.assign({}, m, { done: !m.done }) : m);
    }
    function togglePin(id) {
        memoStore.items = (memoStore.items ?? []).map(m => m.id === id ? Object.assign({}, m, { pinned: !m.pinned }) : m);
    }
    function removeMemo(id) {
        memoStore.items = (memoStore.items ?? []).filter(m => m.id !== id);
    }
    function clearDone() {
        memoStore.items = (memoStore.items ?? []).filter(m => !m.done);
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var en: Qt.locale("en_US")
    readonly property var bat: UPower.displayDevice
    readonly property int activeWs: Hyprland.focusedWorkspace?.id ?? 1
    readonly property int wsCount: Math.min(10, Math.max(5, activeWs, ...Hyprland.workspaces.values.filter(w => w.id > 0 && w.toplevels.values.length).map(w => w.id)))

    function goWs(ws) { Hyprland.dispatch(`hl.dsp.focus({ workspace = "${ws}" })`); }

    // 充电与播放呼吸节拍（20fps 轻量驱动）
    property real beatPhase: 0
    Timer {
        running: root.bat.state === UPowerDeviceState.Charging || (root.capsuleMode === 1 && LyricsFeed.playing)
        interval: 60
        repeat: true
        onTriggered: root.beatPhase = (root.beatPhase + 0.12) % (Math.PI * 2)
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: scrScope
            required property var modelData
            readonly property bool enabledOnScreen: Theme.state.barAt === "top" && Theme.scr(modelData.name, "bar")
            readonly property bool isOpen: root.openScreen === modelData

            // 1. 顶部 38px 高度占位层（仅占排布空间，完全鼠标穿透）
            PanelWindow {
                screen: scrScope.modelData
                visible: scrScope.enabledOnScreen
                anchors { left: true; right: true; top: true }
                implicitHeight: Math.ceil(38 * Theme.s)
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "glyph-bar"
            }

            // 2. 灵动岛主体与展开层
            PanelWindow {
                id: win
                screen: scrScope.modelData
                visible: scrScope.enabledOnScreen
                anchors { left: true; right: true; top: true; bottom: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: scrScope.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                WlrLayershell.namespace: "glyph-top-island"

                // 精确输入遮罩：收起时仅胶囊可点；展开时全屏点击外部可关；向外拖文件时自动让出底层窗口以便落盘到微信/浏览器！
                mask: Region { item: scrScope.isOpen && !shelfView.draggingOut ? fullHit : capHit }

                Item {
                    id: fullHit
                    anchors.fill: parent
                }

                Item {
                    id: capHit
                    x: Math.floor((islandBox.x - chrome.earSize) * Theme.s) - 4
                    y: 0
                    width: Math.ceil((islandBox.width + chrome.earSize * 2) * Theme.s) + 8
                    height: Math.ceil((islandBox.y + islandBox.height) * Theme.s) + 6
                }

                // 点击岛外区域收起灵动岛（透明遮罩，不让全屏变暗黑闪）
                MouseArea {
                    anchors.fill: parent
                    enabled: scrScope.isOpen && !shelfView.draggingOut
                    visible: enabled
                    onClicked: root.close()
                }

                Stage {
                    id: stage

                    // 测算歌词胶囊自适应宽度
                    TextMetrics {
                        id: lyricMetrics
                        font { family: Theme.ui; pixelSize: 13; weight: Font.Medium }
                        text: LyricsFeed.displayText
                    }

                    Item {
                        id: islandBox
                        focus: scrScope.isOpen

                        property real dockP: scrScope.isOpen ? 1 : 0
                        Behavior on dockP { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }

                        readonly property real restW: root.capsuleMode === 1
                            ? Math.max(250, Math.min(560, lyricMetrics.width + 138))
                            : Math.max(264, timeCapsuleRow.implicitWidth + 36)

                        readonly property string shownMode: scrScope.isOpen ? root.panelMode : root.lastMode
                        readonly property real openW: shownMode === "quick" ? 470 : (root.activeTab === 3 ? 620 : 480)
                        readonly property real openH: {
                            if (shownMode === "quick") return quickPane.implicitHeight;
                            if (root.activeTab === 0) return 52 + calPane.implicitHeight + 26;
                            if (root.activeTab === 1) return 52 + focusPane.implicitHeight + 28;
                            if (root.activeTab === 2) return 52 + notesPane.implicitHeight + 26;
                            return 52 + 212 + 26;
                        }

                        width: scrScope.isOpen ? openW : restW
                        height: scrScope.isOpen ? openH : 32
                        x: (parent.width - width) / 2
                        y: 4 * (1 - dockP)

                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
                        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }

                        Keys.onPressed: e => {
                            if (e.key === Qt.Key_Escape) {
                                root.close();
                                e.accepted = true;
                            } else if (root.panelMode === "tabs" && !memoInput.activeFocus) {
                                if (e.key === Qt.Key_Tab) {
                                    root.activeTab = (root.activeTab + 1) % root.tabs.length;
                                    e.accepted = true;
                                } else if (root.activeTab === 0 && e.key === Qt.Key_Left) {
                                    root.calShift--;
                                    e.accepted = true;
                                } else if (root.activeTab === 0 && e.key === Qt.Key_Right) {
                                    root.calShift++;
                                    e.accepted = true;
                                } else if (root.activeTab === 1 && e.key === Qt.Key_Space) {
                                    Focus.toggle();
                                    e.accepted = true;
                                }
                            }
                        }

                        // 打开便签页时自动聚焦输入框
                        Connections {
                            target: root
                            function onOpenScreenChanged() {
                                if (scrScope.isOpen) {
                                    if (root.panelMode === "tabs" && root.wantNoteFocus && root.activeTab === 2)
                                        Qt.callLater(() => memoInput.forceActiveFocus());
                                    else
                                        islandBox.forceActiveFocus();
                                }
                            }
                            function onActiveTabChanged() {
                                if (scrScope.isOpen && root.panelMode === "tabs" && root.activeTab === 2)
                                    Qt.callLater(() => memoInput.forceActiveFocus());
                            }
                        }

                        // 一体化纯黑胶囊 / 贴顶液态内凹耳朵背景轮廓
                        IslandChrome {
                            id: chrome
                            earSize: 22 * islandBox.dockP
                            x: -earSize
                            y: 0
                            width: islandBox.width + earSize * 2
                            height: islandBox.height
                            topRadius: 16
                            bottomRadius: scrScope.isOpen ? Theme.corner(30) : 16
                            fillColor: "#000000"
                            borderColor: Theme.s2
                        }

                        // 拦截岛内背景点击，防止穿透到外部关闭遮罩
                        MouseArea {
                            anchors.fill: parent
                            enabled: scrScope.isOpen
                            onClicked: islandBox.forceActiveFocus()
                        }

                        // ==================== 1. 收起常态胶囊（时间+电源 ↔ 实时歌词） ====================
                        Item {
                            id: restingContent
                            anchors.fill: parent
                            opacity: Math.max(0, 1 - islandBox.dockP * 2.2)
                            visible: opacity > 0.01
                            clip: true

                            // 拖文件悬停在收起胶囊上 → 自动展开到 SHELF 暂存器！
                            DropArea {
                                anchors.fill: parent
                                onEntered: drag => {
                                    drag.accept(Qt.CopyAction);
                                    root.lastMode = "tabs";
                                    root.panelMode = "tabs";
                                    root.activeTab = 3;
                                    root.openScreen = scrScope.modelData;
                                }
                            }

                            // 滚轮切换「时间+电源」与「实时歌词」（带防抖节流）
                            property real wheelAcc: 0
                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: e => {
                                    const d = e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x;
                                    restingContent.wheelAcc += d;
                                    if (Math.abs(restingContent.wheelAcc) >= 90) {
                                        root.capsuleMode = 1 - root.capsuleMode;
                                        restingContent.wheelAcc = 0;
                                    }
                                    e.accepted = true;
                                }
                            }

                            // 鼠标按住横向轻划也可切换两态；左键单击展开灵动岛，右键单击打开 Glyph 控制中心
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                property real pressX: 0
                                property bool swiped: false

                                onPressed: m => {
                                    pressX = m.x;
                                    swiped = false;
                                }
                                onPositionChanged: m => {
                                    if ((m.buttons & Qt.LeftButton) && Math.abs(m.x - pressX) > 32 && !swiped) {
                                        swiped = true;
                                        root.capsuleMode = 1 - root.capsuleMode;
                                    }
                                }
                                onClicked: m => {
                                    if (swiped) return;
                                    if (m.button === Qt.LeftButton) {
                                        root.toggleQuick();
                                    } else {
                                        root.toggleOpen();
                                    }
                                }
                            }

                            // 态 0：中间工作区点阵 + Doto 时间 + 电池电源信息
                            Row {
                                id: timeCapsuleRow
                                anchors.centerIn: parent
                                spacing: 14
                                opacity: root.capsuleMode === 0 ? 1 : 0
                                visible: opacity > 0.01
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                // 工作区点阵（点击小点直接切工作区）
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 5
                                    Repeater {
                                        model: root.wsCount
                                        Rectangle {
                                            required property int index
                                            readonly property int n: index + 1
                                            readonly property bool on: root.activeWs === n
                                            readonly property bool occ: (Hyprland.workspaces.values.find(w => w.id === n)?.toplevels.values.length ?? 0) > 0
                                            width: on ? 18 : 5
                                            height: 5
                                            radius: 2.5
                                            color: on ? Theme.fg : occ ? Theme.grey : Theme.s3
                                            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }

                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 3; height: 3; radius: 1.5; color: Theme.s3 }

                                // 点阵时间 + 专注/录屏红点
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    Rectangle {
                                        visible: Focus.running || Sys.live
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6.5
                                        height: 6.5
                                        radius: 3.25
                                        color: Theme.nothingRed
                                    }
                                    Num {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: `${Theme.hh(clock.date)}:${Qt.formatTime(clock.date, "mm")}`
                                        font.pixelSize: 20
                                    }
                                }

                                Rectangle {
                                    visible: root.bat.isLaptopBattery
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: Theme.s3
                                }

                                // 电池电源胶囊信息
                                Row {
                                    visible: root.bat.isLaptopBattery
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    readonly property bool ac: !UPower.onBattery
                                    readonly property bool chg: root.bat.state === UPowerDeviceState.Charging
                                    readonly property bool low: UPower.onBattery && root.bat.percentage < 0.15

                                    Icon {
                                        visible: parent.ac
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\u{F140B}"
                                        font.pixelSize: 12
                                        color: parent.chg ? Theme.nothingRed : Theme.fg
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 22
                                        height: 11
                                        radius: 5.5
                                        color: "transparent"
                                        border { width: 1.3; color: Theme.grey }
                                        Rectangle {
                                            x: 2.5
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.max(2, (parent.width - 5) * root.bat.percentage)
                                            height: parent.height - 5
                                            radius: 3
                                            color: parent.parent.low ? Theme.nothingRed : Theme.fg
                                            opacity: parent.parent.chg ? (0.65 + 0.35 * Math.cos(root.beatPhase)) : 1
                                        }
                                    }
                                    Lb {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Math.round(root.bat.percentage * 100)
                                        px: 10
                                        color: Theme.fg
                                    }
                                }
                            }

                            // 态 1：实时滚动歌词 + 点阵迷你律动 + 右侧精简时间
                            Item {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                opacity: root.capsuleMode === 1 ? 1 : 0
                                visible: opacity > 0.01
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                // 左侧封面/红点 + 迷你三柱律动
                                Row {
                                    id: lyrLeft
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    spacing: 7

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: Theme.s2
                                        clip: true
                                        Art {
                                            visible: LyricsFeed.artUrl !== ""
                                            anchors.fill: parent
                                            step: 2
                                            url: LyricsFeed.artUrl
                                        }
                                        Rectangle {
                                            visible: LyricsFeed.artUrl === ""
                                            anchors.centerIn: parent
                                            width: 7
                                            height: 7
                                            radius: 3.5
                                            color: LyricsFeed.playing ? Theme.nothingRed : Theme.grey
                                        }
                                    }

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2.5
                                        Repeater {
                                            model: 3
                                            Rectangle {
                                                required property int index
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 2.5
                                                height: LyricsFeed.playing
                                                    ? (5 + 8 * (0.5 + 0.5 * Math.sin(root.beatPhase * 1.8 + index * 1.5)))
                                                    : 4
                                                radius: 1.25
                                                color: index === 1 && LyricsFeed.playing ? Theme.nothingRed : Theme.fg
                                            }
                                        }
                                    }
                                }

                                // 实时歌词正文
                                Text {
                                    anchors {
                                        left: lyrLeft.right
                                        leftMargin: 10
                                        right: lyrClock.left
                                        rightMargin: 10
                                        verticalCenter: parent.verticalCenter
                                    }
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: LyricsFeed.displayText
                                    font { family: Theme.ui; pixelSize: 13; weight: Font.Medium }
                                    color: LyricsFeed.playing ? Theme.fg : Theme.grey
                                }

                                // 右端紧凑时间
                                Lb {
                                    id: lyrClock
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    text: `${Theme.hh(clock.date)}:${Qt.formatTime(clock.date, "mm")}`
                                    px: 10
                                    color: Theme.grey
                                }
                            }
                        }

                        // ==================== 2A. 左键控制中心（零延迟直接随胶囊同步浮现） ====================
                        Item {
                            anchors.fill: parent
                            clip: true
                            opacity: scrScope.isOpen && root.panelMode === "quick" ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            visible: opacity > 0.01

                            QuickPane {
                                id: quickPane
                                x: (parent.width - width) / 2
                                y: 0
                                active: scrScope.isOpen && root.panelMode === "quick"
                                maxStageHeight: stage.height
                                onCloseRequested: root.close()
                                onSwitchTabsRequested: root.toggleOpen()
                                onPowerRequested: root.powerRequested()
                                onSettingsRequested: root.settingsRequested()
                                onPortalRequested: root.portalRequested()
                                onVpnRequested: root.vpnRequested()
                            }
                        }

                        // ==================== 2B. 右键展开面板（顶部点阵切换栏 + 4 个原生页） ====================
                        Item {
                            id: expandedContent
                            anchors.fill: parent
                            opacity: scrScope.isOpen && root.panelMode === "tabs" ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            visible: opacity > 0.01
                            clip: true

                            // 顶栏 Hub Tab 切换条（支持点击或滚轮左右切，右键收起）
                            Item {
                                id: tabBar
                                x: 24
                                y: 6
                                width: parent.width - 48
                                height: 42
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: root.toggleQuick()
                                }

                                property real wheelAcc: 0
                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: e => {
                                        const d = e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x;
                                        tabBar.wheelAcc += d;
                                        if (Math.abs(tabBar.wheelAcc) >= 90) {
                                            const step = tabBar.wheelAcc < 0 ? 1 : -1;
                                            root.activeTab = (root.activeTab + step + root.tabs.length) % root.tabs.length;
                                            tabBar.wheelAcc = 0;
                                        }
                                        e.accepted = true;
                                    }
                                }

                                readonly property real slotW: width / root.tabs.length
                                property real tabPos: root.activeTab
                                Behavior on tabPos {
                                    enabled: scrScope.isOpen && root.panelMode === "tabs"
                                    NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
                                }

                                Row {
                                    anchors.fill: parent
                                    Repeater {
                                        model: root.tabs
                                        Item {
                                            id: tSlot
                                            required property var modelData
                                            required property int index
                                            width: tabBar.slotW
                                            height: parent.height
                                            readonly property bool cur: root.activeTab === index

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Icon {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: tSlot.modelData.icon
                                                    font.pixelSize: 14
                                                    color: tSlot.cur ? Theme.nothingRed : (tHov.hovered ? Theme.fg : Theme.grey)
                                                }
                                                Lb {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: {
                                                        if (tSlot.index === 1 && Focus.running) return Focus.mmss(Focus.left);
                                                        if (tSlot.index === 2 && root.sortedMemos.length > 0) return `NOTES · ${root.sortedMemos.length}`;
                                                        if (tSlot.index === 3 && shelfView.count > 0) return `SHELF · ${shelfView.count}`;
                                                        return tSlot.modelData.label;
                                                    }
                                                    px: 10
                                                    color: tSlot.cur ? Theme.fg : (tHov.hovered ? Theme.fg : Theme.grey)
                                                }
                                            }
                                            HoverHandler { id: tHov; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: root.activeTab = tSlot.index }
                                        }
                                    }
                                }

                                // Nothing 红色滑动下划线指示条（绑定归一化 tabPos，避免岛宽伸缩时每帧打断重启 Behavior）
                                Rectangle {
                                    width: 34
                                    height: 2.5
                                    radius: 1.25
                                    anchors.bottom: parent.bottom
                                    x: tabBar.tabPos * tabBar.slotW + (tabBar.slotW - width) / 2
                                    color: Theme.nothingRed
                                }

                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: 1
                                    color: Theme.s2
                                }
                            }

                            // ---- Tab 0: CALENDAR (Glyph 原生点阵月历) ----
                            Column {
                                id: calPane
                                visible: root.activeTab === 0
                                x: 26
                                y: 58
                                width: parent.width - 52
                                spacing: 12

                                readonly property var month: new Date(clock.date.getFullYear(), clock.date.getMonth() + root.calShift, 1)
                                readonly property int lead: (month.getDay() + 6) % 7

                                Item {
                                    width: parent.width
                                    height: 40
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 12
                                        Num { anchors.verticalCenter: parent.verticalCenter; text: root.en.standaloneMonthName(calPane.month.getMonth(), Locale.ShortFormat); font.pixelSize: 40 }
                                        Lb { anchors.verticalCenter: parent.verticalCenter; text: calPane.month.getFullYear() }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.calShift = 0 }
                                    }
                                    Row {
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        spacing: 8
                                        RoundBtn { icon: "\u{F0141}"; onClicked: root.calShift-- }
                                        RoundBtn { icon: "\u{F0142}"; onClicked: root.calShift++ }
                                    }
                                }

                                Grid {
                                    width: parent.width
                                    columns: 7
                                    Repeater {
                                        model: ["M", "T", "W", "T", "F", "S", "S"]
                                        Text {
                                            required property string modelData
                                            width: calPane.width / 7
                                            height: 24
                                            horizontalAlignment: Text.AlignHCenter
                                            text: modelData
                                            font { family: Theme.mono; pixelSize: 11 }
                                            color: Theme.grey
                                        }
                                    }
                                    Repeater {
                                        model: 42
                                        Item {
                                            id: dayCell
                                            required property int index
                                            readonly property var d: new Date(calPane.month.getFullYear(), calPane.month.getMonth(), index - calPane.lead + 1)
                                            readonly property bool own: d.getMonth() === calPane.month.getMonth()
                                            readonly property bool today: d.toDateString() === clock.date.toDateString()
                                            width: calPane.width / 7
                                            height: 38
                                            Rectangle { anchors.centerIn: parent; visible: dayCell.today; width: 34; height: 34; radius: 17; color: Theme.fg }
                                            Text {
                                                anchors.centerIn: parent
                                                text: dayCell.d.getDate()
                                                font { family: Theme.mono; pixelSize: 13 }
                                                color: dayCell.today ? Theme.ink : !dayCell.own ? Theme.mute : dayCell.index % 7 > 4 ? Theme.grey : Theme.fg
                                            }
                                        }
                                    }
                                }
                            }

                            // ---- Tab 1: FOCUS (Glyph 原生环形点阵专注计时) ----
                            Row {
                                id: focusPane
                                visible: root.activeTab === 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 66
                                spacing: 26

                                Item {
                                    width: 164
                                    height: 164
                                    Ring { anchors.fill: parent; n: 44; dot: 5; f: Focus.f }
                                    Column {
                                        anchors.centerIn: parent
                                        Num { anchors.horizontalCenter: parent.horizontalCenter; text: Focus.mmss(Focus.left); font.pixelSize: 38 }
                                        Lb {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            topPadding: 8
                                            text: Focus.running ? "focusing" : Focus.paused ? "paused" : "ready"
                                            color: Focus.running ? Theme.nothingRed : Theme.grey
                                            px: 10
                                        }
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 16
                                    Lb { text: "focus · minutes" }
                                    Row {
                                        spacing: 8
                                        Repeater {
                                            model: [15, 25, 45, 60]
                                            Rectangle {
                                                id: fChip
                                                required property int modelData
                                                readonly property bool on: Focus.minutes === modelData
                                                width: 44
                                                height: 44
                                                radius: 22
                                                color: on ? Theme.fg : fHov.hovered ? Theme.s3 : Theme.s2
                                                Text { anchors.centerIn: parent; text: fChip.modelData; font { family: Theme.mono; pixelSize: 13 } color: fChip.on ? Theme.ink : Theme.fg }
                                                HoverHandler { id: fHov; cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: Focus.set(fChip.modelData) }
                                            }
                                        }
                                    }
                                    Row {
                                        spacing: 10
                                        Rectangle {
                                            width: 146
                                            height: 44
                                            radius: Theme.corner(22)
                                            color: Focus.running ? Theme.s2 : Theme.fg
                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 8
                                                Icon { anchors.verticalCenter: parent.verticalCenter; text: Focus.running ? "\u{F03E4}" : "\u{F040A}"; color: Focus.running ? Theme.fg : Theme.ink }
                                                Lb {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: Focus.running ? "pause" : Focus.paused ? "resume" : "start"
                                                    color: Focus.running ? Theme.fg : Theme.ink
                                                }
                                            }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: Focus.toggle() }
                                        }
                                        RoundBtn { icon: "\u{F0450}"; opacity: Focus.running || Focus.paused ? 1 : 0.4; onClicked: Focus.reset() }
                                    }
                                }
                            }

                            // ---- Tab 2: NOTES (Nothing OS 随手便签 / 待办) ----
                            Column {
                                id: notesPane
                                visible: root.activeTab === 2
                                x: 26
                                y: 58
                                width: parent.width - 52
                                spacing: 12

                                Item {
                                    width: parent.width
                                    height: 18
                                    Row {
                                        x: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8
                                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: Theme.nothingRed }
                                        Lb { text: `notes · ${root.sortedMemos.length}` }
                                    }
                                    Lb {
                                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                        visible: root.doneCount > 0
                                        text: `clear done (${root.doneCount})`
                                        color: Theme.fg
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.clearDone() }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 46
                                    radius: Theme.corner(23)
                                    color: Theme.s2
                                    border { width: memoInput.activeFocus ? 1 : 0; color: Theme.s3 }

                                    TextInput {
                                        id: memoInput
                                        anchors {
                                            left: parent.left
                                            leftMargin: 18
                                            right: addBtn.left
                                            rightMargin: 10
                                            verticalCenter: parent.verticalCenter
                                        }
                                        font { family: Theme.ui; pixelSize: 14 }
                                        color: Theme.fg
                                        selectionColor: Theme.s3
                                        clip: true
                                        cursorDelegate: Rectangle {
                                            width: 2
                                            color: Theme.nothingRed
                                            Timer { running: memoInput.activeFocus; interval: 500; repeat: true; onTriggered: parent.opacity = 1 - parent.opacity }
                                        }
                                        Text {
                                            visible: !memoInput.text
                                            text: "写点便签或待办，按 Enter 保存…"
                                            font: memoInput.font
                                            color: Theme.mute
                                        }
                                        Keys.onPressed: e => {
                                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                                if (root.addMemo(memoInput.text)) memoInput.text = "";
                                                e.accepted = true;
                                            } else if (e.key === Qt.Key_Escape) {
                                                root.close();
                                                e.accepted = true;
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: addBtn
                                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                        width: 34
                                        height: 34
                                        radius: 17
                                        color: memoInput.text.trim().length > 0 ? Theme.fg : Theme.s3
                                        Icon {
                                            anchors.centerIn: parent
                                            text: "\u{F0415}"
                                            font.pixelSize: 16
                                            color: memoInput.text.trim().length > 0 ? Theme.ink : Theme.grey
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: { if (root.addMemo(memoInput.text)) memoInput.text = ""; } }
                                    }
                                }

                                Lb {
                                    visible: root.sortedMemos.length === 0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    topPadding: 18
                                    bottomPadding: 18
                                    text: "no notes yet · super+r anytime"
                                    color: Theme.mute
                                    px: 10
                                }

                                ListView {
                                    id: memoList
                                    width: parent.width
                                    height: Math.min(contentHeight, 260)
                                    visible: root.sortedMemos.length > 0
                                    clip: true
                                    spacing: 8
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: root.sortedMemos

                                    delegate: Rectangle {
                                        id: mCard
                                        required property var modelData
                                        readonly property var m: modelData
                                        width: memoList.width
                                        height: Math.max(46, noteBody.height + 20)
                                        radius: Theme.corner(18)
                                        color: Theme.s2
                                        border { width: m.pinned ? 1 : 0; color: m.pinned ? Theme.nothingRed : "transparent" }
                                        HoverHandler { id: mHov }

                                        Rectangle {
                                            id: mChk
                                            x: 14
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 20
                                            height: 20
                                            radius: 10
                                            color: mCard.m.done ? Theme.fg : "transparent"
                                            border { width: 1.5; color: mCard.m.done ? Theme.fg : Theme.grey }
                                            Icon { visible: mCard.m.done; anchors.centerIn: parent; text: "\u{F012C}"; font.pixelSize: 12; color: Theme.ink }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: root.toggleDone(mCard.m.id) }
                                        }

                                        Column {
                                            id: noteBody
                                            anchors { left: mChk.right; leftMargin: 12; right: mActs.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                            spacing: 2
                                            Text {
                                                width: parent.width
                                                wrapMode: Text.Wrap
                                                textFormat: Text.PlainText
                                                text: mCard.m.text
                                                font { family: Theme.ui; pixelSize: 14; strikeout: !!mCard.m.done }
                                                color: mCard.m.done ? Theme.mute : Theme.fg
                                            }
                                            Lb {
                                                visible: !!mCard.m.time
                                                text: (mCard.m.pinned ? "pinned · " : "") + (mCard.m.time ?? "")
                                                px: 9
                                                color: mCard.m.pinned ? Theme.nothingRed : Theme.mute
                                            }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: {
                                                    memoInput.text = mCard.m.text;
                                                    root.removeMemo(mCard.m.id);
                                                    memoInput.forceActiveFocus();
                                                }
                                            }
                                        }

                                        Row {
                                            id: mActs
                                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                            spacing: 4
                                            opacity: mHov.hovered || mCard.m.pinned ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 120 } }

                                            Rectangle {
                                                width: 26; height: 26; radius: 13
                                                color: pHov.hovered ? Theme.s3 : "transparent"
                                                Icon { anchors.centerIn: parent; text: "\u{F0403}"; font.pixelSize: 13; color: mCard.m.pinned ? Theme.nothingRed : Theme.grey }
                                                HoverHandler { id: pHov; cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: root.togglePin(mCard.m.id) }
                                            }
                                            Rectangle {
                                                width: 26; height: 26; radius: 13
                                                color: dHov.hovered ? Theme.s3 : "transparent"
                                                Icon { anchors.centerIn: parent; text: "\u{F0156}"; font.pixelSize: 14; color: dHov.hovered ? Theme.nothingRed : Theme.grey }
                                                HoverHandler { id: dHov; cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: root.removeMemo(mCard.m.id) }
                                            }
                                        }
                                    }
                                }
                            }

                            // ---- Tab 3: SHELF (Nothing OS 文件暂存器) ----
                            ShelfView {
                                id: shelfView
                                visible: root.activeTab === 3
                                x: 26
                                y: 58
                                width: parent.width - 52
                                height: 212
                            }
                        }
                    }
                }
            }
        }
    }

    component RoundBtn: Rectangle {
        property string icon
        signal clicked
        width: 40
        height: 40
        radius: 20
        color: Theme.s2
        Icon { anchors.centerIn: parent; text: parent.icon }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.clicked() }
    }
}
