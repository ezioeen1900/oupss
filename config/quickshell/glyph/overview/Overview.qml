import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

// Nothing OS 点阵风格多工作区 + 双暂存区实时窗口画面缩略图总览 (Alt+Tab)：
// 左侧 2×5 普通工作区 (01–10) + 右侧独立双暂存区列 (SPECIAL / MIN)，全部带 ScreencopyView 实时画面预览与双向跨区拖拽
PanelWindow {
    id: root

    property bool open: false
    property var clientMap: ({})     // normalized hex address -> client json
    property string openSpecial: ""  // 当前显示器已展开的暂存区名 ("special" | "min" | "")
    property int dragTargetSlot: -1  // 1..10 普通工作区, 11=special:special, 12=special:min
    property string draggingAddr: ""

    function normAddr(a) {
        return String(a || "").toLowerCase().replace(/^0x/, "");
    }

    function slotOfClient(c) {
        const wn = c?.workspace?.name ?? "";
        if (wn === "special:special") return 11;
        if (wn === "special:min") return 12;
        const wid = c?.workspace?.id ?? -1;
        return (wid >= 1 && wid <= 10) ? wid : -1;
    }

    function refreshState() {
        if (!stateProc.running) stateProc.running = true;
    }

    function toggle() { open = !open; }
    function close() {
        open = false;
        dragTargetSlot = -1;
        draggingAddr = "";
    }

    onOpenChanged: {
        if (open) {
            refreshState();
            panel.forceActiveFocus();
        } else {
            dragTargetSlot = -1;
            draggingAddr = "";
        }
    }

    // 一次性读取 clients + 当前显示器打开的 specialWorkspace
    Process {
        id: stateProc
        command: ["sh", "-c", "hyprctl clients -j; printf '\\n---SPLIT---\\n'; hyprctl monitors -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parts = this.text.split("\n---SPLIT---\n");
                    const arr = JSON.parse(parts[0] || "[]");
                    const mons = JSON.parse(parts[1] || "[]");
                    const map = {};
                    for (const c of arr) {
                        if (!c.mapped) continue;
                        map[root.normAddr(c.address)] = c;
                    }
                    const fm = mons.find(m => m.focused) ?? mons[0];
                    const sn = String(fm?.specialWorkspace?.name ?? "");
                    root.openSpecial = sn.startsWith("special:") ? sn.slice(8) : "";
                    root.clientMap = map;
                } catch (e) {}
            }
        }
    }

    Timer {
        id: refreshDebounce
        interval: 80
        onTriggered: if (root.open) root.refreshState()
    }

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (!root.open) return;
            if (["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode", "activespecial"].includes(ev.name)) {
                refreshDebounce.restart();
            }
        }
    }

    readonly property var monInfo: {
        const fm = Hyprland.focusedMonitor;
        const sc = Quickshell.screens.find(s => s.name === fm?.name) ?? Quickshell.screens[0];
        return {
            w: sc?.width ?? 2048,
            h: sc?.height ?? 1280,
            x: fm?.x ?? 0,
            y: fm?.y ?? 0
        };
    }

    readonly property int activeWs: Hyprland.focusedWorkspace?.id ?? 1

    property var pendingCmds: []
    Timer {
        id: jumpTimer
        interval: 35
        onTriggered: {
            const cmds = root.pendingCmds;
            root.pendingCmds = [];
            for (const c of cmds) Hyprland.dispatch(c);
        }
    }

    function closeAndRun(cmds) {
        root.pendingCmds = cmds;
        root.open = false;
        jumpTimer.restart();
    }

    // 激活格子：1..10 为普通工作区，11=special，12=min
    function activateSlot(slot) {
        const curSpec = root.openSpecial;
        const cmds = [];
        if (slot === 11) {
            if (curSpec === "min") cmds.push('hl.dsp.workspace.toggle_special("min")');
            if (curSpec !== "special") cmds.push('hl.dsp.workspace.toggle_special("special")');
        } else if (slot === 12) {
            if (curSpec === "special") cmds.push('hl.dsp.workspace.toggle_special("special")');
            if (curSpec !== "min") cmds.push('hl.dsp.workspace.toggle_special("min")');
        } else if (slot >= 1 && slot <= 10) {
            if (curSpec !== "") cmds.push(`hl.dsp.workspace.toggle_special("${curSpec}")`);
            cmds.push(`hl.dsp.focus({ workspace = "${slot}" })`);
        }
        closeAndRun(cmds);
    }

    function focusWin(addr, slot) {
        const curSpec = root.openSpecial;
        const cmds = [];
        if (slot === 11) {
            if (curSpec === "min") cmds.push('hl.dsp.workspace.toggle_special("min")');
            if (curSpec !== "special") cmds.push('hl.dsp.workspace.toggle_special("special")');
        } else if (slot === 12) {
            if (curSpec === "special") cmds.push('hl.dsp.workspace.toggle_special("special")');
            if (curSpec !== "min") cmds.push('hl.dsp.workspace.toggle_special("min")');
        } else if (slot >= 1 && slot <= 10) {
            if (curSpec !== "") cmds.push(`hl.dsp.workspace.toggle_special("${curSpec}")`);
            cmds.push(`hl.dsp.focus({ workspace = "${slot}" })`);
        }
        cmds.push(`hl.dsp.focus({ window = "address:0x${addr}" })`);
        closeAndRun(cmds);
    }

    function closeWin(addr) {
        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:0x${addr}" })`);
        refreshDebounce.restart();
    }

    function moveWinToSlot(addr, slot) {
        if (slot === 11) {
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = "special:special", follow = false, window = "address:0x${addr}" })`);
        } else if (slot === 12) {
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = "special:min", follow = false, window = "address:0x${addr}" })`);
        } else if (slot >= 1 && slot <= 10) {
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${slot}", follow = false, window = "address:0x${addr}" })`);
        }
        refreshDebounce.restart();
    }

    property real t: open ? 1 : 0
    Behavior on t { enabled: root.open; NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-overview"

    // 半透明背景遮罩（点击面板外部关闭）
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.62 * root.t
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Stage {
        id: stage

        readonly property int cols: 5
        readonly property real cellGap: 14
        readonly property real specSplitGap: 32 // 普通工作区与右侧暂存区之间的分隔留白
        readonly property real cellW: 244
        readonly property real cellH: Math.round(cellW * (root.monInfo.h / Math.max(1, root.monInfo.w)))
        readonly property real normalGridW: cols * cellW + (cols - 1) * cellGap
        readonly property real totalBoardW: normalGridW + specSplitGap + cellW
        readonly property real totalBoardH: 2 * cellH + cellGap

        Rectangle {
            id: panel
            width: stage.totalBoardW + 60
            height: bodyCol.height + 54
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2 + 18 * (1 - root.t)
            opacity: root.t
            radius: Theme.corner(38)
            color: "#000000"
            border { width: 1; color: Theme.s2 }
            focus: true

            // 注意：此处拦截面板空白处点击，子卡片统一使用 MouseArea（不与 TapHandler 抢事件！）
            MouseArea { anchors.fill: parent }

            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape || (e.key === Qt.Key_Tab && (e.modifiers & Qt.AltModifier))) {
                    root.close();
                } else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                    root.activateSlot(e.key - Qt.Key_0);
                } else if (e.key === Qt.Key_0) {
                    root.activateSlot(10);
                } else if (e.key === Qt.Key_S) {
                    root.activateSlot(11);
                } else if (e.key === Qt.Key_M || e.key === Qt.Key_E) {
                    root.activateSlot(12);
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    root.close();
                } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                    Hyprland.dispatch(`hl.dsp.focus({ workspace = "${root.activeWs % 10 + 1}" })`);
                } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                    Hyprland.dispatch(`hl.dsp.focus({ workspace = "${(root.activeWs + 8) % 10 + 1}" })`);
                } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J || e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                    const next = root.activeWs <= 5 ? root.activeWs + 5 : root.activeWs - 5;
                    Hyprland.dispatch(`hl.dsp.focus({ workspace = "${next}" })`);
                } else {
                    return;
                }
                e.accepted = true;
            }

            Column {
                id: bodyCol
                x: 30
                y: 25
                width: stage.totalBoardW
                spacing: 16

                // 顶部标题栏
                Item {
                    width: parent.width
                    height: 28
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: Theme.nothingRed }
                        Num { anchors.verticalCenter: parent.verticalCenter; text: "OVERVIEW"; font.pixelSize: 28 }
                        Lb { anchors.verticalCenter: parent.verticalCenter; leftPadding: 6; text: `ws 01–10 + scratchpads · ${Object.keys(root.clientMap).length} windows` }
                    }
                    Lb {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: "click jump · drag across ws & scratchpads · mid-click close"
                        color: Theme.mute
                        px: 9
                    }
                }

                // 12 格主画布：01–10 普通工作区 + 右侧 SPECIAL (11) / MIN (12) 暂存区
                Item {
                    id: board
                    width: stage.totalBoardW
                    height: stage.totalBoardH

                    function slotRect(slot) {
                        if (slot === 11) {
                            return { x: stage.normalGridW + stage.specSplitGap, y: 0, w: stage.cellW, h: stage.cellH };
                        }
                        if (slot === 12) {
                            return { x: stage.normalGridW + stage.specSplitGap, y: stage.cellH + stage.cellGap, w: stage.cellW, h: stage.cellH };
                        }
                        const idx = slot - 1;
                        const c = idx % stage.cols;
                        const r = Math.floor(idx / stage.cols);
                        return {
                            x: c * (stage.cellW + stage.cellGap),
                            y: r * (stage.cellH + stage.cellGap),
                            w: stage.cellW,
                            h: stage.cellH
                        };
                    }

                    function slotAtPoint(px, py) {
                        for (let s = 1; s <= 12; s++) {
                            const rc = slotRect(s);
                            if (px >= rc.x && px <= rc.x + rc.w && py >= rc.y && py <= rc.y + rc.h)
                                return s;
                        }
                        return -1;
                    }

                    // 普通工作区与右侧暂存区之间的竖向点阵分隔线
                    Column {
                        x: stage.normalGridW + stage.specSplitGap / 2 - 1.5
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Repeater {
                            model: 20
                            Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.s3 }
                        }
                    }

                    // 1. 12 张工作区 / 暂存区底板卡片（全部使用 MouseArea，确保点击 100% 响应！）
                    Repeater {
                        model: 12

                        Rectangle {
                            id: wsCard
                            required property int index
                            readonly property int slot: index + 1
                            readonly property bool isSpec: slot >= 11
                            readonly property var rc: board.slotRect(slot)
                            readonly property bool isCur: slot === 11 ? (root.openSpecial === "special")
                                                        : slot === 12 ? (root.openSpecial === "min")
                                                        : (root.openSpecial === "" && root.activeWs === slot)
                            readonly property bool isDrop: root.dragTargetSlot === slot

                            x: rc.x
                            y: rc.y
                            width: rc.w
                            height: rc.h
                            radius: Theme.corner(18)
                            color: isDrop ? Theme.s3 : (isCur ? "#151515" : (isSpec ? "#0D0B0C" : "#0A0A0A"))
                            border {
                                width: isDrop ? 2 : (isCur ? 1.5 : 1)
                                color: isDrop ? Theme.nothingRed
                                     : isCur ? (isSpec ? Theme.nothingRed : Theme.fg)
                                     : wsMouse.containsMouse ? Theme.grey
                                     : (isSpec ? Theme.s3 : Theme.s2)
                            }

                            // 暂存区左上角专属标签
                            Row {
                                visible: wsCard.isSpec
                                x: 10
                                y: 8
                                spacing: 5
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 5; height: 5; radius: 2.5
                                    color: wsCard.slot === 11 ? Theme.nothingRed : Theme.grey
                                }
                                Lb {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: wsCard.slot === 11 ? "special · up" : "min · down"
                                    px: 9
                                    color: wsCard.isCur ? Theme.fg : Theme.grey
                                }
                            }

                            // 右下角大号点阵水印
                            Num {
                                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 12; bottomMargin: 6 }
                                text: wsCard.slot === 11 ? "SP" : wsCard.slot === 12 ? "MN" : String(wsCard.slot).padStart(2, "0")
                                font.pixelSize: wsCard.isSpec ? 28 : 32
                                color: wsCard.isCur ? Theme.grey : Theme.s2
                                opacity: 0.6
                            }

                            // 普通工作区当前激活红点
                            Rectangle {
                                visible: !wsCard.isSpec && wsCard.isCur
                                x: 10
                                y: 10
                                width: 6
                                height: 6
                                radius: 3
                                color: Theme.nothingRed
                            }

                            MouseArea {
                                id: wsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activateSlot(wsCard.slot)
                            }
                        }
                    }

                    // 2. 实时窗口画面缩略图层 (ScreencopyView，含 01–10 + SPECIAL + MIN 全部窗口！)
                    Repeater {
                        model: ScriptModel {
                            values: {
                                if (!root.open) return [];
                                const map = root.clientMap;
                                return ToplevelManager.toplevels.values.filter(tl => {
                                    const addr = root.normAddr(tl.HyprlandToplevel?.address);
                                    return root.slotOfClient(map[addr]) >= 1;
                                });
                            }
                        }

                        Item {
                            id: winThumb
                            required property var modelData
                            readonly property string addr: root.normAddr(modelData.HyprlandToplevel?.address)
                            readonly property var cData: root.clientMap[addr] ?? null
                            readonly property int slot: root.slotOfClient(cData)
                            readonly property var cell: board.slotRect(Math.max(1, slot))

                            readonly property real sx: (stage.cellW - 12) / Math.max(1, root.monInfo.w)
                            readonly property real sy: (stage.cellH - 12) / Math.max(1, root.monInfo.h)

                            readonly property real thumbW: Math.max(46, Math.min(stage.cellW - 12, (cData?.size?.[0] ?? 400) * sx))
                            readonly property real thumbH: Math.max(32, Math.min(stage.cellH - 12, (cData?.size?.[1] ?? 300) * sy))
                            readonly property real rawX: ((cData?.at?.[0] ?? 0) - root.monInfo.x) * sx
                            readonly property real rawY: ((cData?.at?.[1] ?? 0) - root.monInfo.y) * sy
                            readonly property real baseX: cell.x + 6 + Math.max(0, Math.min(stage.cellW - 12 - thumbW, rawX))
                            readonly property real baseY: cell.y + 6 + Math.max(0, Math.min(stage.cellH - 12 - thumbH, rawY))

                            property bool dragging: false
                            x: baseX
                            y: baseY
                            width: thumbW
                            height: thumbH
                            z: dragging ? 50 : (thumbArea.containsMouse ? 15 : 5)
                            scale: dragging ? 1.05 : (thumbArea.containsMouse ? 1.02 : 1.0)

                            Behavior on x { enabled: !winThumb.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                            Behavior on y { enabled: !winThumb.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            onBaseXChanged: if (!dragging) x = baseX
                            onBaseYChanged: if (!dragging) y = baseY

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.corner(10)
                                color: Theme.s2
                                clip: true
                                border {
                                    width: thumbArea.containsMouse || winThumb.dragging ? 1.5 : 1
                                    color: winThumb.dragging ? Theme.nothingRed : (thumbArea.containsMouse ? Theme.fg : Theme.s3)
                                }

                                ScreencopyView {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    captureSource: root.open ? winThumb.modelData : null
                                    live: root.open
                                }

                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: 20
                                    color: Qt.rgba(0, 0, 0, 0.78)
                                    opacity: thumbArea.containsMouse ? 1 : 0.84

                                    Row {
                                        anchors { left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                        spacing: 5
                                        Image {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 12
                                            height: 12
                                            source: Quickshell.iconPath(winThumb.cData?.class || "application-x-executable", "application-x-executable")
                                            sourceSize: Qt.size(24, 24)
                                        }
                                        Text {
                                            width: parent.width - 17
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                            text: winThumb.cData?.title || winThumb.cData?.class || ""
                                            font { family: Theme.ui; pixelSize: 10; weight: Font.Medium }
                                            color: Theme.fg
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: thumbArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                cursorShape: winThumb.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                drag.target: winThumb
                                drag.threshold: 6

                                property point startPt: Qt.point(0, 0)
                                property bool moved: false

                                onPressed: m => {
                                    if (m.button === Qt.MiddleButton) {
                                        root.closeWin(winThumb.addr);
                                        m.accepted = true;
                                        return;
                                    }
                                    startPt = Qt.point(winThumb.x, winThumb.y);
                                    moved = false;
                                }
                                onPositionChanged: m => {
                                    if (!(m.buttons & Qt.LeftButton)) return;
                                    if (Math.hypot(winThumb.x - startPt.x, winThumb.y - startPt.y) > 8) {
                                        moved = true;
                                        winThumb.dragging = true;
                                        root.draggingAddr = winThumb.addr;
                                        root.dragTargetSlot = board.slotAtPoint(winThumb.x + winThumb.width / 2, winThumb.y + winThumb.height / 2);
                                    }
                                }
                                onReleased: m => {
                                    if (winThumb.dragging) {
                                        const dst = root.dragTargetSlot;
                                        winThumb.dragging = false;
                                        root.draggingAddr = "";
                                        root.dragTargetSlot = -1;
                                        if (dst >= 1 && dst <= 12 && dst !== winThumb.slot) {
                                            root.moveWinToSlot(winThumb.addr, dst);
                                        } else {
                                            winThumb.x = Qt.binding(() => winThumb.baseX);
                                            winThumb.y = Qt.binding(() => winThumb.baseY);
                                        }
                                        return;
                                    }
                                    if (!moved && m.button === Qt.LeftButton) {
                                        root.focusWin(winThumb.addr, winThumb.slot);
                                    }
                                }
                            }

                            // 右上角关闭圆钮（同样用 MouseArea 保证点击绝对优先）
                            Rectangle {
                                z: 10
                                visible: (thumbArea.containsMouse || closeMouse.containsMouse) && !winThumb.dragging
                                anchors { right: parent.right; top: parent.top; rightMargin: 5; topMargin: 5 }
                                width: 18
                                height: 18
                                radius: 9
                                color: closeMouse.containsMouse ? Theme.nothingRed : Qt.rgba(0, 0, 0, 0.80)
                                Icon { anchors.centerIn: parent; text: "\u{F0156}"; font.pixelSize: 11; color: Theme.fg }
                                MouseArea {
                                    id: closeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.closeWin(winThumb.addr)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
