import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

// Nothing OS 原生点阵全功能原位截图工作台（融合 Flameshot / 微信截图直觉 + Glyph 点阵美学）：
// - 未锁定时：12× 点阵像素放大镜 + 自动窗口高亮识别（单击捕窗 / 拖拽框选）+ 区域/窗口/全屏/录屏/延时模式切换
// - 框选松手后：不弹新窗口，原地锁定选区，支持八向手柄像素微调（带实时放大镜）+ 框下悬浮点阵标注工具栏：
//   移动微调 · 画笔 · 荧光笔 · 直线 · 箭头 · 矩形 · 椭圆 · ①②③序号圆标 · 文字 · 马赛克 · 吸管取色
//   撤销/重做/清空 · OCR文字与二维码识别 · 桌面悬浮贴图(Pin) · 暂存进灵动岛(Shelf) · 保存 · 一键复制完成
Scope {
    id: root

    readonly property var modes: ["region", "window", "screen", "record"]
    readonly property var delays: [0, 3, 10]
    readonly property string run: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    // 标注工具定义（tool === -1 表示选区移动/八向缩放态）
    readonly property var toolDefs: [
        { id: "pen",     icon: "\u{F03EB}", tip: "画笔 · P",       key: Qt.Key_P },
        { id: "marker",  icon: "\u{F0652}", tip: "荧光笔 · M",     key: Qt.Key_M },
        { id: "line",    icon: "\u{F0374}", tip: "直线 · L",       key: Qt.Key_L, rot: -38 },
        { id: "arrow",   icon: "\u{F005C}", tip: "箭头 · A",       key: Qt.Key_A },
        { id: "rect",    icon: "\u{F0765}", tip: "矩形 · R",       key: Qt.Key_R },
        { id: "circle",  icon: "\u{F0766}", tip: "椭圆 · O",       key: Qt.Key_O },
        { id: "counter", label: "1",        tip: "序号标 · N",     key: Qt.Key_N },
        { id: "text",    icon: "\u{F0284}", tip: "文字 · T",       key: Qt.Key_T },
        { id: "blur",    icon: "\u{F02C1}", tip: "马赛克 · B",     key: Qt.Key_B }
    ]

    readonly property var inks: [
        Theme.nothingRed, // #D71921 Nothing Red
        "#FFFFFF",        // Pure White
        "#F5C542",        // Signal Yellow
        "#3DD68C",        // Matrix Green
        "#4DA3FF",        // Cyber Blue
        "#0B0B0B"         // Pitch Black
    ]
    readonly property var sizes: [2.5, 5, 9, 14]

    property int mode: 0
    property int delay: 0
    property string frozen: ""
    property var scr: null
    property var wins: []

    property bool locked: false
    property bool resizingHandle: false
    property rect drag: Qt.rect(0, 0, 0, 0)
    property real mx: 0
    property real my: 0

    property int tool: -1       // -1 = 移动/微调选区, 0..8 = 标注工具
    property int ink: 0
    property int sizeIdx: 1
    property var marks: []      // 舞台坐标系标注列表
    property var redoStack: []  // 重做栈
    property var live: null     // 正在绘制的标注
    property string statusToast: ""
    property string hoverTip: ""

    readonly property real strokeW: sizes[sizeIdx]

    readonly property var hover: wins.find(w => mx >= w.x && mx < w.x + w.w && my >= w.y && my < w.y + w.h) ?? null
    readonly property rect sel: {
        if (locked) return drag;
        if (mode === 2) return Qt.rect(0, 0, stage.width, stage.height);
        if (mode === 1) return hover ? Qt.rect(hover.x, hover.y, hover.w, hover.h) : Qt.rect(0, 0, 0, 0);
        if (drag.width > 0 && drag.height > 0) return drag;
        return hover ? Qt.rect(hover.x, hover.y, hover.w, hover.h) : Qt.rect(0, 0, 0, 0);
    }
    readonly property real k: frozenImg.sourceSize.width / Math.max(1, stage.width)

    // 底部完成卡片状态
    property string shot: ""
    property string shotWhat: ""
    property string shotDims: ""
    property rect shotRect
    property bool shotRec: false

    Timer {
        id: toastTimer
        interval: 1600
        onTriggered: root.statusToast = ""
    }
    function flashToast(msg) {
        statusToast = msg;
        toastTimer.restart();
    }

    function nextCounterNum() {
        let n = 1;
        for (const m of marks) {
            if (m.k === "counter" && m.num >= n) n = m.num + 1;
        }
        return n;
    }

    function open() {
        if (aim.visible) return;
        const mon = Hyprland.focusedMonitor;
        scr = Quickshell.screens.find(s => s.name === mon?.name) ?? Quickshell.screens[0];
        Hyprland.refreshToplevels();
        picker.unloadImage(frozenImg.source);
        freeze.next = `${run}/glyph-frozen-${Date.now()}.ppm`;
        freeze.exec(["sh", "-c", 'rm -f "$3"/glyph-frozen-*; grim -t ppm -o "$1" "$2" && echo ok', "sh", scr.name, freeze.next, run]);
    }

    function close() {
        commitWord();
        typing.visible = false;
        live = null;
        aim.shown = false;
    }

    function resetSelection() {
        commitWord();
        locked = false;
        tool = -1;
        marks = [];
        redoStack = [];
        live = null;
        drag = Qt.rect(0, 0, 0, 0);
        stage.forceActiveFocus();
    }

    function commitWord() {
        if (!typing.visible) return;
        const txt = typing.text.trim();
        if (txt) {
            marks = marks.concat([{
                k: "text",
                c: inks[ink],
                s: typing.font.pixelSize,
                x: typing.stageX,
                y: typing.stageY,
                t: txt
            }]);
            redoStack = [];
        }
        typing.text = "";
        typing.visible = false;
        stage.forceActiveFocus();
    }

    function undo() {
        commitWord();
        if (!marks.length) return;
        const last = marks[marks.length - 1];
        marks = marks.slice(0, -1);
        redoStack = redoStack.concat([last]);
    }

    function redo() {
        commitWord();
        if (!redoStack.length) return;
        const last = redoStack[redoStack.length - 1];
        redoStack = redoStack.slice(0, -1);
        marks = marks.concat([last]);
    }

    function copyHex() {
        const hx = picker.hex;
        Quickshell.execDetached(["wl-copy", hx]);
        flashToast(`已复制色值 ${hx}`);
    }

    // 录屏启动（mode === 3）
    function startRecord() {
        const r = sel.width > 4 && sel.height > 4 ? sel : Qt.rect(0, 0, stage.width, stage.height);
        const full = Math.abs(r.width - stage.width) < 2 && Math.abs(r.height - stage.height) < 2;
        const s = Theme.s, w = Math.round(r.width * s), h = Math.round(r.height * s);
        const x = Math.round(scr.x + r.x * s), y = Math.round(scr.y + r.y * s);
        shotRect = r;
        shotRec = true;
        shotWhat = `record · ${Qt.formatTime(new Date(), "hh:mm")}`;
        shotDims = `${w}×${h}`;
        aim.snap = true;
        aim.shown = false;
        const g = full ? `-w ${scr.name}` : `-w region -region ${w}x${h}+${x}+${y}`;
        Quickshell.execDetached(["sh", "-c", `sleep ${delays[delay]}; notify-send -a "shot · rec" "Recording." "ctrl+alt+r — stop"; `
            + `gpu-screen-recorder ${g} ${Sys.recArgs()} -o "$(xdg-user-dir VIDEOS)/rec-$(date +%F_%H-%M-%S).mp4"`]);
        fx.restart();
    }

    // 统一高清物理分辨率导出：action = "copy" | "save" | "pin" | "shelf" | "ocr"
    function finish(action) {
        if (mode === 3) return startRecord();
        commitWord();

        const r = (sel.width > 2 && sel.height > 2) ? sel : Qt.rect(0, 0, stage.width, stage.height);
        // 若延时截图且无原位标注，走延时实拍
        if (delays[delay] > 0 && marks.length === 0 && (action === "copy" || action === "save")) {
            const s = Theme.s, w = Math.round(r.width * s), h = Math.round(r.height * s);
            const x = Math.round(scr.x + r.x * s), y = Math.round(scr.y + r.y * s);
            shotRect = r;
            shotRec = false;
            shotWhat = `timer · ${Qt.formatTime(new Date(), "hh:mm")}`;
            shotDims = `${Math.round(r.width * k)}×${Math.round(r.height * k)}`;
            aim.snap = true;
            aim.shown = false;
            take.exec(["sh", "-c", `d="$HOME/Pictures/Screenshots"; mkdir -p "$d"; f="$d/shot-$(date +%F_%H-%M-%S).png"; sleep "$1"; grim -g "$2" "$f" && wl-copy -t image/png < "$f" && printf '%s' "$f"`,
                "sh", String(delays[delay]), `${x},${y} ${w}x${h}`]);
            return;
        }

        // 确保未锁定直接回车时也能准确导出当前选区/全屏
        if (!locked) {
            drag = r;
            locked = true;
        }

        const pw = Math.max(1, Math.round(r.width * k));
        const ph = Math.max(1, Math.round(r.height * k));
        const logX = r.x * Theme.s;
        const logY = r.y * Theme.s;
        const logW = r.width * Theme.s;
        const logH = r.height * Theme.s;
        const targetScr = scr;

        Qt.callLater(() => {
            exportCanvas.grabToImage(res => {
                const ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
                if (action === "copy") {
                    const tmp = `${run}/glyph-clip-${Date.now()}.png`;
                    if (!res.saveToFile(tmp)) return;
                    shotRect = r;
                    shotRec = false;
                    aim.snap = true;
                    aim.shown = false;
                    Quickshell.execDetached(["sh", "-c", 'wl-copy -t image/png < "$1"; sleep 2; rm -f "$1"', "sh", tmp]);
                } else if (action === "save") {
                    const tmp = `${run}/glyph-save-${Date.now()}.png`;
                    if (!res.saveToFile(tmp)) return;
                    shotRect = r;
                    shotRec = false;
                    shotWhat = `saved · ${Qt.formatTime(new Date(), "hh:mm")}`;
                    shotDims = `${pw}×${ph}`;
                    aim.snap = true;
                    aim.shown = false;
                    take.exec(["sh", "-c", 'd="$HOME/Pictures/Screenshots"; mkdir -p "$d"; f="$d/shot-$2.png"; mv "$1" "$f" && wl-copy -t image/png < "$f" && printf "%s" "$f"', "sh", tmp, ts]);
                } else if (action === "pin") {
                    const pinPath = `${run}/glyph-pin-${Date.now()}.png`;
                    if (!res.saveToFile(pinPath)) return;
                    Quickshell.execDetached(["sh", "-c", 'wl-copy -t image/png < "$1"', "sh", pinPath]);
                    aim.snap = true;
                    aim.shown = false;
                    pins.add(pinPath, targetScr, logX, logY, logW, logH);
                } else if (action === "shelf") {
                    const tmp = `${run}/glyph-shelf-${Date.now()}.png`;
                    if (!res.saveToFile(tmp)) return;
                    aim.snap = true;
                    aim.shown = false;
                    shelfPush.exec(["python3", "-c", `
import json, os, pathlib, shutil
src, ts = os.sys.argv[1], os.sys.argv[2]
d = pathlib.Path.home() / "Pictures/Screenshots"
d.mkdir(parents=True, exist_ok=True)
dst = d / f"shot-{ts}.png"
shutil.move(src, dst)
sp = pathlib.Path(os.environ.get("XDG_STATE_HOME") or (pathlib.Path.home() / ".local/state")) / "rice/shelf.json"
sp.parent.mkdir(parents=True, exist_ok=True)
try:
    data = json.loads(sp.read_text())
except Exception:
    data = {"list": []}
lst = data.get("list") or []
fp = str(dst)
lst = [x for x in lst if x.get("filePath") != fp]
lst.insert(0, {"uri": dst.as_uri(), "filePath": fp, "name": dst.name, "ext": "PNG", "icon": "image-x-generic"})
data["list"] = lst
sp.write_text(json.dumps(data, indent=2, ensure_ascii=False))
`, tmp, ts]);
                } else if (action === "ocr") {
                    const tmp = `${run}/glyph-ocr-${Date.now()}.png`;
                    if (!res.saveToFile(tmp)) return;
                    flashToast("正在识别文字 / 二维码…");
                    ocrProc.exec(["sh", "-c", `
out=$(zbarimg -q --raw "$1" 2>/dev/null)
if [ -z "$out" ]; then
    out=$(tesseract "$1" stdout -l chi_sim+eng --psm 6 2>/dev/null | sed -e 's/[[:space:]]*$//')
fi
rm -f "$1"
if [ -n "$out" ]; then
    printf '%s' "$out" | wl-copy
    printf '%s' "$out"
fi
`, "sh", tmp]);
                }
            }, Qt.size(pw, ph));
        });
    }

    Process { id: shelfPush }
    Process {
        id: ocrProc
        stdout: StdioCollector {
            onStreamFinished: {
                const res = text.trim();
                if (res) {
                    const preview = res.replace(/\s+/g, " ").slice(0, 60);
                    Quickshell.execDetached(["notify-send", "-a", "glyph · ocr", "OCR 已复制到剪贴板", preview]);
                    aim.snap = true;
                    aim.shown = false;
                } else {
                    root.flashToast("未识别到文字或二维码");
                }
            }
        }
    }

    Process {
        id: freeze
        property string next
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return;
                root.frozen = freeze.next;
                root.mode = 0;
                root.locked = false;
                root.tool = -1;
                root.marks = [];
                root.redoStack = [];
                root.live = null;
                root.statusToast = "";
                root.drag = Qt.rect(0, 0, 0, 0);
                const s = Theme.s;
                root.wins = Hyprland.toplevels.values
                    .filter(t => t.workspace?.id === Hyprland.focusedMonitor?.activeWorkspace?.id && t.lastIpcObject?.size)
                    .sort((a, b) => (b.lastIpcObject.floating ?? false) - (a.lastIpcObject.floating ?? false))
                    .map(t => ({
                        x: Math.max(0, (t.lastIpcObject.at[0] - root.scr.x) / s),
                        y: Math.max(0, (t.lastIpcObject.at[1] - root.scr.y) / s),
                        w: t.lastIpcObject.size[0] / s,
                        h: t.lastIpcObject.size[1] / s
                    }));
                aim.snap = false;
                aim.shown = true;
                stage.forceActiveFocus();
            }
        }
    }

    Process {
        id: take
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text) return;
                root.shot = text;
                fx.restart();
            }
        }
    }

    Editor { id: editor }
    Pins { id: pins }

    // ============ 主截图与原位标注层 ============
    PanelWindow {
        id: aim

        property bool shown: false
        property bool snap: false
        property real t: shown ? 1 : 0
        Behavior on t { enabled: !aim.snap; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

        screen: root.scr
        visible: t > 0
        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "glyph-shot"

        Stage {
            id: stage
            opacity: aim.shown ? 1 : aim.t
            focus: true

            Keys.onPressed: e => {
                if (typing.visible && typing.activeFocus) return;

                if (e.key === Qt.Key_Escape) {
                    if (root.live) root.live = null;
                    else root.close();
                    e.accepted = true;
                    return;
                }
                if ((e.key === Qt.Key_Z) && (e.modifiers & Qt.ControlModifier) && (e.modifiers & Qt.ShiftModifier)) {
                    root.redo(); e.accepted = true; return;
                }
                if ((e.key === Qt.Key_Y) && (e.modifiers & Qt.ControlModifier)) {
                    root.redo(); e.accepted = true; return;
                }
                if ((e.key === Qt.Key_Z) && (e.modifiers & Qt.ControlModifier)) {
                    root.undo(); e.accepted = true; return;
                }
                if ((e.key === Qt.Key_S) && (e.modifiers & Qt.ControlModifier)) {
                    root.finish("save"); e.accepted = true; return;
                }
                if ((e.key === Qt.Key_C) && (e.modifiers & Qt.ControlModifier)) {
                    root.finish("copy"); e.accepted = true; return;
                }
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    root.finish("copy"); e.accepted = true; return;
                }
                if (e.key === Qt.Key_C && !(e.modifiers & Qt.ControlModifier)) {
                    root.copyHex(); e.accepted = true; return;
                }

                if (root.locked && root.mode !== 3) {
                    const hitIdx = root.toolDefs.findIndex(td => td.key === e.key);
                    if (hitIdx >= 0) {
                        root.commitWord();
                        root.tool = (root.tool === hitIdx) ? -1 : hitIdx;
                        e.accepted = true; return;
                    }
                    if (e.key === Qt.Key_V) { root.commitWord(); root.tool = -1; e.accepted = true; return; }
                    if (e.key === Qt.Key_F || ((e.key === Qt.Key_P) && (e.modifiers & Qt.ControlModifier))) {
                        root.finish("pin"); e.accepted = true; return;
                    }
                    if (e.key === Qt.Key_H) { root.finish("shelf"); e.accepted = true; return; }
                    if (e.key === Qt.Key_G) { root.finish("ocr"); e.accepted = true; return; }
                    if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
                        root.marks = []; root.redoStack = []; e.accepted = true; return;
                    }
                    if (e.key >= Qt.Key_1 && e.key <= Qt.Key_6) {
                        root.ink = e.key - Qt.Key_1; e.accepted = true; return;
                    }
                    if (e.key === Qt.Key_BracketLeft) {
                        root.sizeIdx = Math.max(0, root.sizeIdx - 1); e.accepted = true; return;
                    }
                    if (e.key === Qt.Key_BracketRight) {
                        root.sizeIdx = Math.min(root.sizes.length - 1, root.sizeIdx + 1); e.accepted = true; return;
                    }
                    // 方向键像素级微调选区
                    if (root.tool === -1 && [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(e.key)) {
                        const step = (e.modifiers & Qt.ShiftModifier) ? 10 : 1;
                        let nx = root.drag.x, ny = root.drag.y;
                        if (e.key === Qt.Key_Left) nx -= step;
                        if (e.key === Qt.Key_Right) nx += step;
                        if (e.key === Qt.Key_Up) ny -= step;
                        if (e.key === Qt.Key_Down) ny += step;
                        nx = Math.max(0, Math.min(stage.width - root.drag.width, nx));
                        ny = Math.max(0, Math.min(stage.height - root.drag.height, ny));
                        root.drag = Qt.rect(nx, ny, root.drag.width, root.drag.height);
                        e.accepted = true; return;
                    }
                } else {
                    if (e.key === Qt.Key_Space) { root.mode = 1; e.accepted = true; return; }
                    if (e.key === Qt.Key_Tab) { root.mode = (root.mode + 1) % 4; e.accepted = true; return; }
                    if (e.key === Qt.Key_Backtab) { root.mode = (root.mode + 3) % 4; e.accepted = true; return; }
                    if (e.key === Qt.Key_T) { root.delay = (root.delay + 1) % 3; e.accepted = true; return; }
                }
            }

            // 底层冻结原图
            Image {
                id: frozenImg
                anchors.fill: parent
                source: root.frozen ? "file://" + root.frozen : ""
            }

            // 选区外暗化遮罩
            Item {
                anchors.fill: parent
                opacity: aim.t
                readonly property color c: Theme.fade(Theme.bg, root.sel.width ? 0.72 : 0.35)
                readonly property rect r: root.sel.width ? root.sel : Qt.rect(0, 0, 0, 0)
                Rectangle { width: parent.width; height: parent.r.y; color: parent.c }
                Rectangle { y: parent.r.y + parent.r.height; width: parent.width; height: parent.height - y; color: parent.c }
                Rectangle { y: parent.r.y; width: parent.r.x; height: parent.r.height; color: parent.c }
                Rectangle { x: parent.r.x + parent.r.width; y: parent.r.y; width: parent.width - x; height: parent.r.height; color: parent.c }
            }

            // 未锁定时全屏点阵十字准星
            Dots { visible: !root.locked; y: Math.round(root.my) - 4; width: parent.width; height: 8; opacity: 0.5 * aim.t }
            Dots { visible: !root.locked; x: Math.round(root.mx) - 4; width: 8; height: parent.height; opacity: 0.5 * aim.t }

            // 全屏初始框选拖拽层（未锁定时生效；右键关闭）
            MouseArea {
                id: selectArea
                anchors.fill: parent
                enabled: !root.locked
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.CrossCursor
                property point from
                property bool moved: false

                onPositionChanged: e => {
                    root.mx = e.x;
                    root.my = e.y;
                    if ((pressedButtons & Qt.LeftButton) && (root.mode === 0 || root.mode === 3)) {
                        if (Math.hypot(e.x - from.x, e.y - from.y) > 4) moved = true;
                        if (moved) {
                            root.drag = Qt.rect(
                                Math.min(from.x, e.x),
                                Math.min(from.y, e.y),
                                Math.abs(e.x - from.x),
                                Math.abs(e.y - from.y)
                            );
                        }
                    }
                }
                onPressed: e => {
                    if (e.button === Qt.RightButton) {
                        root.close();
                        return;
                    }
                    if (root.mode === 2) {
                        root.drag = Qt.rect(0, 0, stage.width, stage.height);
                        root.mode = 0;
                        root.locked = true;
                        return;
                    }
                    if (root.mode === 1) {
                        if (root.hover) {
                            root.drag = Qt.rect(root.hover.x, root.hover.y, root.hover.w, root.hover.h);
                            root.mode = 0;
                            root.locked = true;
                        }
                        return;
                    }
                    from = Qt.point(e.x, e.y);
                    moved = false;
                    root.drag = Qt.rect(e.x, e.y, 0, 0);
                }
                onReleased: e => {
                    if (e.button !== Qt.LeftButton) return;
                    // 单击未拖动且悬停在窗口上：智能吸附该窗口（微信/Flameshot 同款）
                    if (!moved && root.hover) {
                        root.drag = Qt.rect(root.hover.x, root.hover.y, root.hover.w, root.hover.h);
                        root.locked = true;
                        return;
                    }
                    if (root.drag.width >= 6 && root.drag.height >= 6) {
                        root.locked = true;
                    } else {
                        root.drag = Qt.rect(0, 0, 0, 0);
                    }
                }
            }

            // ============ 纯净导出画布（仅含原图与标注，不含选区白框与手柄） ============
            Item {
                id: exportCanvas
                visible: root.sel.width > 0 && root.sel.height > 0
                x: root.sel.x
                y: root.sel.y
                width: Math.max(1, root.sel.width)
                height: Math.max(1, root.sel.height)
                clip: true

                Image {
                    id: cropBase
                    x: -root.sel.x
                    y: -root.sel.y
                    width: stage.width
                    height: stage.height
                    source: frozenImg.source
                    smooth: true
                }

                Item {
                    x: -root.sel.x
                    y: -root.sel.y
                    width: stage.width
                    height: stage.height

                    Repeater {
                        model: root.marks
                        MarkItem { required property var modelData; m: modelData; src: cropBase }
                    }
                    Repeater {
                        model: root.live ? [root.live] : []
                        MarkItem { required property var modelData; m: modelData; src: cropBase }
                    }
                }
            }

            // ============ 选区边框 · 三分点阵线 · 原位绘制交互层 · 八向缩放手柄 ============
            Item {
                id: vf
                visible: root.sel.width > 0
                opacity: aim.t
                x: root.sel.x
                y: root.sel.y
                width: root.sel.width
                height: root.sel.height

                // 原位文字输入框
                TextInput {
                    id: typing
                    visible: false
                    z: 8
                    property real stageX: 0
                    property real stageY: 0
                    x: stageX - vf.x
                    y: stageY - vf.y
                    font { family: Theme.ui; pixelSize: Math.max(15, root.strokeW * 3.8); weight: Font.DemiBold }
                    color: root.inks[root.ink]
                    selectionColor: Theme.s3
                    cursorDelegate: Rectangle { width: 2; color: Theme.nothingRed }
                    onAccepted: root.commitWord()
                    Keys.onEscapePressed: { text = ""; visible = false; stage.forceActiveFocus(); }

                    Rectangle {
                        z: -1
                        anchors.fill: parent
                        anchors.margins: -6
                        radius: 6
                        color: Qt.rgba(0, 0, 0, 0.55)
                        border { width: 1; color: Theme.nothingRed }
                    }
                }

                // 锁定态选区内鼠标交互（tool === -1 移动选区 / 双击完成；tool >= 0 绘制标注；滚轮调粗细；右键回退）
                MouseArea {
                    id: drawArea
                    anchors.fill: parent
                    enabled: root.locked
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: {
                        if (root.tool === -1) return pressed ? Qt.ClosedHandCursor : Qt.SizeAllCursor;
                        if (root.tool === 7) return Qt.IBeamCursor;
                        return Qt.CrossCursor;
                    }

                    property point moveStart
                    property rect rectStart

                    onPositionChanged: e => {
                        const sx = vf.x + e.x;
                        const sy = vf.y + e.y;
                        root.mx = sx;
                        root.my = sy;

                        if (!(pressedButtons & Qt.LeftButton)) return;

                        if (root.tool === -1) {
                            let nx = rectStart.x + (sx - moveStart.x);
                            let ny = rectStart.y + (sy - moveStart.y);
                            nx = Math.max(0, Math.min(stage.width - rectStart.width, nx));
                            ny = Math.max(0, Math.min(stage.height - rectStart.height, ny));
                            root.drag = Qt.rect(nx, ny, rectStart.width, rectStart.height);
                            return;
                        }

                        const l = root.live;
                        if (!l) return;
                        let tx = sx, ty = sy;
                        // 按住 Shift 时直线/箭头/矩形/圆对齐水平/垂直/45°/正圆
                        if (e.modifiers & Qt.ShiftModifier) {
                            const dx = tx - l.x1, dy = ty - l.y1;
                            if (l.k === "line" || l.k === "arrow") {
                                const ang = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
                                const len = Math.hypot(dx, dy);
                                tx = l.x1 + Math.cos(ang) * len;
                                ty = l.y1 + Math.sin(ang) * len;
                            } else if (l.k === "rect" || l.k === "circle") {
                                const side = Math.max(Math.abs(dx), Math.abs(dy));
                                tx = l.x1 + (dx >= 0 ? side : -side);
                                ty = l.y1 + (dy >= 0 ? side : -side);
                            }
                        }
                        if (l.k === "pen" || l.k === "marker")
                            root.live = Object.assign({}, l, { pts: l.pts.concat([Qt.point(tx, ty)]) });
                        else
                            root.live = Object.assign({}, l, { x2: tx, y2: ty });
                    }

                    onPressed: e => {
                        const sx = vf.x + e.x;
                        const sy = vf.y + e.y;
                        root.mx = sx;
                        root.my = sy;

                        if (e.button === Qt.RightButton) {
                            root.commitWord();
                            if (root.tool >= 0) root.tool = -1;
                            else root.resetSelection();
                            return;
                        }

                        root.commitWord();
                        if (root.tool === -1) {
                            moveStart = Qt.point(sx, sy);
                            rectStart = root.drag;
                            return;
                        }

                        const kind = root.toolDefs[root.tool].id;
                        const c = root.inks[root.ink];
                        if (kind === "counter") {
                            root.marks = root.marks.concat([{
                                k: "counter",
                                c: c,
                                r: Math.max(13, root.strokeW * 2.2),
                                x: sx,
                                y: sy,
                                num: root.nextCounterNum()
                            }]);
                            root.redoStack = [];
                        } else if (kind === "text") {
                            typing.text = "";
                            typing.stageX = sx;
                            typing.stageY = sy - 12;
                            typing.visible = true;
                            typing.forceActiveFocus();
                        } else if (kind === "pen" || kind === "marker") {
                            root.live = {
                                k: kind,
                                c: c,
                                w: kind === "marker" ? Math.max(14, root.strokeW * 2.8) : root.strokeW,
                                pts: [Qt.point(sx, sy)]
                            };
                        } else {
                            root.live = { k: kind, c: c, w: root.strokeW, x1: sx, y1: sy, x2: sx, y2: sy };
                        }
                    }

                    onReleased: e => {
                        if (e.button !== Qt.LeftButton || !root.live) return;
                        const l = root.live;
                        root.live = null;
                        const valid = (l.k === "pen" || l.k === "marker")
                            ? l.pts.length > 1
                            : Math.hypot(l.x2 - l.x1, l.y2 - l.y1) > 3;
                        if (valid) {
                            root.marks = root.marks.concat([l]);
                            root.redoStack = [];
                        }
                    }

                    onDoubleClicked: e => {
                        if (e.button === Qt.LeftButton && root.tool === -1)
                            root.finish("copy");
                    }

                    onWheel: e => {
                        if (e.angleDelta.y > 0)
                            root.sizeIdx = Math.min(root.sizes.length - 1, root.sizeIdx + 1);
                        else if (e.angleDelta.y < 0)
                            root.sizeIdx = Math.max(0, root.sizeIdx - 1);
                    }
                }

                // 1px 选区白框与三分构图点阵线（标注进行中弱化三分线免干扰）
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border { width: 1.2; color: root.mode === 3 ? Theme.nothingRed : Theme.fg }
                }
                Repeater {
                    model: 2
                    Item {
                        required property int index
                        visible: root.tool === -1
                        anchors.fill: parent
                        Dots { x: parent.width * (index + 1) / 3 - 4; width: 8; height: parent.height; opacity: 0.25 }
                        Dots { y: parent.height * (index + 1) / 3 - 4; width: parent.width; height: 8; opacity: 0.25 }
                    }
                }

                // 八向缩放控制手柄（4 角圆点 + 4 边胶囊，仅在微调态 tool === -1 时激活交互）
                Repeater {
                    model: [
                        { hx: 0,   hy: 0,   cur: Qt.SizeFDiagCursor, dx1: 1, dy1: 1, dx2: 0, dy2: 0 },
                        { hx: 0.5, hy: 0,   cur: Qt.SizeVerCursor,   dx1: 0, dy1: 1, dx2: 0, dy2: 0 },
                        { hx: 1,   hy: 0,   cur: Qt.SizeBDiagCursor, dx1: 0, dy1: 1, dx2: 1, dy2: 0 },
                        { hx: 1,   hy: 0.5, cur: Qt.SizeHorCursor,   dx1: 0, dy1: 0, dx2: 1, dy2: 0 },
                        { hx: 1,   hy: 1,   cur: Qt.SizeFDiagCursor, dx1: 0, dy1: 0, dx2: 1, dy2: 1 },
                        { hx: 0.5, hy: 1,   cur: Qt.SizeVerCursor,   dx1: 0, dy1: 0, dx2: 0, dy2: 1 },
                        { hx: 0,   hy: 1,   cur: Qt.SizeBDiagCursor, dx1: 1, dy1: 0, dx2: 0, dy2: 1 },
                        { hx: 0,   hy: 0.5, cur: Qt.SizeHorCursor,   dx1: 1, dy1: 0, dx2: 0, dy2: 0 }
                    ]
                    Item {
                        id: hdl
                        required property var modelData
                        readonly property bool isCorner: modelData.hx !== 0.5 && modelData.hy !== 0.5
                        visible: root.locked ? (root.tool === -1 || isCorner) : isCorner
                        x: vf.width * modelData.hx - width / 2
                        y: vf.height * modelData.hy - height / 2
                        width: 18
                        height: 18
                        z: 10

                        Rectangle {
                            anchors.centerIn: parent
                            width: hdl.isCorner ? 11 : (hdl.modelData.hy === 0.5 ? 6 : 16)
                            height: hdl.isCorner ? 11 : (hdl.modelData.hx === 0.5 ? 6 : 16)
                            radius: Math.min(width, height) / 2
                            color: hdlArea.pressed ? Theme.nothingRed : Theme.fg
                            border { width: 1.5; color: "#000000" }
                        }

                        MouseArea {
                            id: hdlArea
                            anchors.fill: parent
                            enabled: root.locked && root.tool === -1
                            cursorShape: hdl.modelData.cur
                            property point startPt
                            property real sx1
                            property real sy1
                            property real sx2
                            property real sy2

                            onPressed: e => {
                                const gp = mapToItem(stage, e.x, e.y);
                                startPt = gp;
                                root.mx = gp.x;
                                root.my = gp.y;
                                sx1 = root.drag.x;
                                sy1 = root.drag.y;
                                sx2 = root.drag.x + root.drag.width;
                                sy2 = root.drag.y + root.drag.height;
                                root.resizingHandle = true;
                            }
                            onPositionChanged: e => {
                                if (!pressed) return;
                                const gp = mapToItem(stage, e.x, e.y);
                                root.mx = Math.max(0, Math.min(stage.width, gp.x));
                                root.my = Math.max(0, Math.min(stage.height, gp.y));
                                const dx = root.mx - startPt.x;
                                const dy = root.my - startPt.y;
                                const nx1 = Math.max(0, Math.min(stage.width, sx1 + dx * hdl.modelData.dx1));
                                const ny1 = Math.max(0, Math.min(stage.height, sy1 + dy * hdl.modelData.dy1));
                                const nx2 = Math.max(0, Math.min(stage.width, sx2 + dx * hdl.modelData.dx2));
                                const ny2 = Math.max(0, Math.min(stage.height, sy2 + dy * hdl.modelData.dy2));
                                root.drag = Qt.rect(
                                    Math.min(nx1, nx2),
                                    Math.min(ny1, ny2),
                                    Math.max(8, Math.abs(nx2 - nx1)),
                                    Math.max(8, Math.abs(ny2 - ny1))
                                );
                            }
                            onReleased: root.resizingHandle = false
                            onCanceled: root.resizingHandle = false
                        }
                    }
                }

                // 选区顶部点阵尺寸标尺（贴顶时自动移入框内左上角）
                Rectangle {
                    y: vf.y > 48 ? -height - 10 : 10
                    x: 0
                    width: infoRow.width + 20
                    height: 30
                    radius: 15
                    color: Qt.rgba(0.05, 0.05, 0.05, 0.88)
                    border { width: 1; color: Theme.s2 }

                    Row {
                        id: infoRow
                        anchors.centerIn: parent
                        spacing: 10
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7; height: 7; radius: 3.5
                            color: root.mode === 3 || root.tool >= 0 ? Theme.nothingRed : Theme.fg
                        }
                        Num {
                            anchors.verticalCenter: parent.verticalCenter
                            text: `${Math.round(root.sel.width * root.k)}×${Math.round(root.sel.height * root.k)}`
                            font.pixelSize: 22
                        }
                        Lb {
                            visible: root.marks.length > 0 || root.statusToast !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.statusToast !== "" ? root.statusToast : `${root.marks.length} 处标注`
                            px: 10
                            color: root.statusToast !== "" ? Theme.nothingRed : Theme.grey
                        }
                    }
                }
            }

            // 锁定态点击选区外部：若正在输入文字则落字，否则右键重置选区 / 左键微调外扩也不误关
            MouseArea {
                z: -1
                anchors.fill: parent
                enabled: root.locked
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: e => {
                    root.commitWord();
                    if (e.button === Qt.RightButton) {
                        if (root.tool >= 0) root.tool = -1;
                        else root.resetSelection();
                    }
                }
            }

            // ============ 12× 点阵像素放大镜（未锁定寻点时 + 拖拽八向手柄微调边缘时自动浮现！） ============
            Item {
                id: loupe
                visible: !root.locked || root.resizingHandle
                readonly property int px: Math.max(0, Math.min(frozenImg.sourceSize.width - 1, Math.floor(root.mx * root.k)))
                readonly property int py: Math.max(0, Math.min(frozenImg.sourceSize.height - 1, Math.floor(root.my * root.k)))
                readonly property int zoom: 12
                opacity: aim.t
                x: root.mx + 26 + width > stage.width ? root.mx - 26 - width : root.mx + 26
                y: root.my + 26 + height > stage.height ? root.my - 26 - height : root.my + 26
                width: 180
                height: 236
                z: 20

                Canvas {
                    id: picker
                    property string hex: "#000000"
                    x: 90; y: 90; width: 1; height: 1
                    onImageLoaded: requestPaint()
                    onPaint: {
                        const g = getContext("2d"), src = frozenImg.source.toString();
                        if (!src) return;
                        if (!isImageLoaded(src)) return loadImage(src);
                        g.drawImage(src, loupe.px, loupe.py, 1, 1, 0, 0, 1, 1);
                        const d = g.getImageData(0, 0, 1, 1).data;
                        hex = "#" + [d[0], d[1], d[2]].map(v => v.toString(16).padStart(2, "0")).join("").toUpperCase();
                    }
                    Connections { target: loupe; function onPxChanged() { picker.requestPaint(); } function onPyChanged() { picker.requestPaint(); } }
                }

                Rectangle { x: 6; y: 6; width: 168; height: 168; radius: 84; color: Theme.bg }
                Item {
                    x: 12; y: 12
                    width: 13 * loupe.zoom
                    height: 13 * loupe.zoom
                    layer.enabled: true
                    layer.effect: Dm { step: loupe.zoom; circle: true }
                    Image {
                        source: frozenImg.source
                        smooth: false
                        width: frozenImg.sourceSize.width * loupe.zoom
                        height: frozenImg.sourceSize.height * loupe.zoom
                        x: (6 - loupe.px) * loupe.zoom
                        y: (6 - loupe.py) * loupe.zoom
                    }
                }
                Rectangle { x: 80; y: 80; width: 20; height: 20; radius: 10; color: "transparent"; border { width: 1.5; color: Theme.nothingRed } }
                Ring { width: 180; height: 180; n: 48; dot: 3 }

                Pill {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    height: 42
                    pad: 16
                    spacing: 10
                    Num { anchors.verticalCenter: parent.verticalCenter; text: `${Math.round(root.mx * Theme.s)}·${Math.round(root.my * Theme.s)}`; font.pixelSize: 24 }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: picker.hex; border { width: 1; color: Theme.s3 } }
                    Lb { anchors.verticalCenter: parent.verticalCenter; text: picker.hex; px: 10 }
                }
            }

            // ============ 原位悬浮 Nothing 点阵标注与动作工具栏（固定锚点零跳动布局） ============
            Item {
                id: studioBar
                visible: root.locked
                z: 18
                width: root.mode === 3 ? recPill.width : mainPill.width
                height: 50
                opacity: (drawArea.pressed && root.live) ? 0.14 : 1.0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                // y 仅由选区矩形与固定常量计算，绝不随悬停提示或二级子栏显隐发生变化，杜绝上下跳动循环
                readonly property bool subBelow: y + 104 <= stage.height
                x: Math.max(14, Math.min(stage.width - width - 14, root.sel.x + root.sel.width - width))
                y: {
                    const below = root.sel.y + root.sel.height + 12;
                    if (below + 108 <= stage.height) return below;
                    const above = root.sel.y - 62;
                    if (above >= 42) return above;
                    if (below + 58 <= stage.height) return below;
                    return stage.height - 112;
                }

                // 悬停功能提示小胶囊（脱离文档流绝对定位，鼠标完全穿透，绝不挤占主栏坐标）
                Rectangle {
                    visible: root.hoverTip !== ""
                    enabled: false
                    anchors.right: parent.right
                    y: (!studioBar.subBelow && subPill.visible) ? -82 : (studioBar.y >= 42 ? -32 : (subPill.visible ? 104 : 56))
                    width: tipLb.width + 20
                    height: 24
                    radius: 12
                    color: Theme.s1
                    border { width: 1; color: Theme.s3 }
                    Lb { id: tipLb; anchors.centerIn: parent; text: root.hoverTip; px: 10; color: Theme.fg }
                }

                // 录屏确认胶囊（mode === 3）
                Pill {
                    id: recPill
                    visible: root.mode === 3
                    x: 0
                    y: 0
                    height: 48
                    pad: 12
                    spacing: 8

                    ToolBtn { icon: "\u{F0156}"; tip: "取消 · Esc"; danger: true; onClicked: root.close() }
                    Rectangle {
                        width: recRow.width + 26
                        height: 36
                        radius: 18
                        color: Theme.nothingRed
                        Row {
                            id: recRow
                            anchors.centerIn: parent
                            spacing: 8
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: "#FFFFFF" }
                            Lb { anchors.verticalCenter: parent.verticalCenter; text: "开始录屏 · Enter"; px: 10; color: "#FFFFFF" }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.startRecord()
                        }
                    }
                }

                // 截图全功能标注主工具栏（固定在 y: 0，零位移）
                Pill {
                    id: mainPill
                    visible: root.mode !== 3
                    x: 0
                    y: 0
                    height: 50
                    pad: 8
                    spacing: 3

                    // 移动/缩放选区
                    ToolBtn {
                        icon: "\u{F01BC}"
                        tip: "移动/缩放选区 · V"
                        active: root.tool === -1
                        onClicked: { root.commitWord(); root.tool = -1; }
                    }

                    DotSep {}

                    // 9 种原位标注工具：画笔 · 荧光笔 · 直线 · 箭头 · 矩形 · 椭圆 · 序号标 · 文字 · 马赛克
                    Repeater {
                        model: root.toolDefs
                        ToolBtn {
                            required property var modelData
                            required property int index
                            icon: modelData.icon ?? ""
                            badgeText: modelData.label ?? ""
                            iconRot: modelData.rot ?? 0
                            tip: modelData.tip
                            active: root.tool === index
                            onClicked: {
                                root.commitWord();
                                root.tool = (root.tool === index) ? -1 : index;
                            }
                        }
                    }

                    // 吸管取色
                    ToolBtn {
                        icon: "\u{F020A}"
                        tip: `复制色值 ${picker.hex} · C`
                        onClicked: root.copyHex()
                    }

                    DotSep {}

                    // 撤销 / 重做 / 清空
                    ToolBtn {
                        icon: "\u{F054C}"
                        tip: "撤销 · Ctrl+Z"
                        dimmed: root.marks.length === 0
                        onClicked: root.undo()
                    }
                    ToolBtn {
                        icon: "\u{F044E}"
                        tip: "重做 · Ctrl+Y"
                        dimmed: root.redoStack.length === 0
                        onClicked: root.redo()
                    }
                    ToolBtn {
                        icon: "\u{F0A7A}"
                        tip: "清空标注 · Del"
                        dimmed: root.marks.length === 0
                        onClicked: { root.commitWord(); root.marks = []; root.redoStack = []; }
                    }

                    DotSep {}

                    // 扩展动作：OCR识别 · 桌面贴图(Pin) · 暂存进灵动岛(Shelf) · 保存文件 · 取消 · 复制完成
                    ToolBtn {
                        badgeText: "OCR"
                        tip: "识别文字/二维码 · G"
                        onClicked: root.finish("ocr")
                    }
                    ToolBtn {
                        icon: "\u{F0403}"
                        tip: "钉在桌面贴图 · F"
                        onClicked: root.finish("pin")
                    }
                    ToolBtn {
                        icon: "\u{F0256}"
                        tip: "暂存进灵动岛 · H"
                        onClicked: root.finish("shelf")
                    }
                    ToolBtn {
                        icon: "\u{F0193}"
                        tip: "保存图片 · Ctrl+S"
                        onClicked: root.finish("save")
                    }
                    ToolBtn {
                        icon: "\u{F0156}"
                        tip: "退出取消 · Esc"
                        danger: true
                        onClicked: root.close()
                    }

                    // 主确认按钮：复制高清成图并关闭
                    Rectangle {
                        width: doneRow.width + 22
                        height: 36
                        radius: 18
                        color: doneArea.containsMouse ? Theme.nothingRed : Theme.fg
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            id: doneRow
                            anchors.centerIn: parent
                            spacing: 5
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{F012C}"
                                font.pixelSize: 15
                                color: doneArea.containsMouse ? "#FFFFFF" : Theme.ink
                            }
                            Lb {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "复制"
                                px: 11
                                color: doneArea.containsMouse ? "#FFFFFF" : Theme.ink
                            }
                        }
                        MouseArea {
                            id: doneArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.hoverTip = "复制到剪贴板 · Enter / 双击"
                            onExited: if (root.hoverTip === "复制到剪贴板 · Enter / 双击") root.hoverTip = ""
                            onClicked: root.finish("copy")
                        }
                    }
                }

                // 二级颜色与笔触粗细子栏（独立悬浮定位，不推动主栏 y 坐标）
                Pill {
                    id: subPill
                    visible: root.mode !== 3 && root.tool >= 0
                    anchors.right: mainPill.right
                    y: studioBar.subBelow ? 58 : -50
                    height: 42
                    pad: 12
                    spacing: 6

                    // 6 色圆点（1–6 快捷键）
                    Repeater {
                        model: root.inks
                        Item {
                            id: inkCell
                            required property color modelData
                            required property int index
                            width: 26
                            height: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: 22; height: 22; radius: 11
                                color: "transparent"
                                border { width: 1.5; color: inkCell.index === root.ink ? Theme.fg : "transparent" }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 14; height: 14; radius: 7
                                color: inkCell.modelData
                                border { width: 1; color: Theme.s3 }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.ink = inkCell.index
                            }
                        }
                    }

                    DotSep {}

                    // 4 档粗细圆点（[ ] 快捷键或鼠标滚轮）
                    Repeater {
                        model: root.sizes
                        Item {
                            id: szCell
                            required property real modelData
                            required property int index
                            width: 24
                            height: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: 5 + szCell.index * 3.2
                                height: width
                                radius: width / 2
                                color: szCell.index === root.sizeIdx ? Theme.nothingRed : Theme.mute
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.hoverTip = "笔触粗细 · 滚轮或 [ ]"
                                onExited: if (root.hoverTip === "笔触粗细 · 滚轮或 [ ]") root.hoverTip = ""
                                onClicked: root.sizeIdx = szCell.index
                            }
                        }
                    }
                }
            }

            // ============ 未锁定时的底部模式选择栏（区域 · 窗口 · 全屏 · 录屏 · 延时） ============
            Column {
                visible: !root.locked
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 42 - 24 * (1 - aim.t) }
                opacity: aim.t
                spacing: 10

                Pill {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                        model: root.modes
                        Chip {
                            required property string modelData
                            required property int index
                            text: modelData
                            on: index === root.mode
                            onClicked: root.mode = index
                        }
                    }
                    DotSep {}
                    Chip {
                        text: root.delay ? `${root.delays[root.delay]}s` : "timer"
                        on: root.delay > 0
                        onClicked: root.delay = (root.delay + 1) % 3
                    }
                }
                Pill {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 34
                    pad: 20
                    spacing: 22
                    Repeater {
                        model: ["单击捕窗 · 拖拽框选", "tab 切模式", "t 延时", "c 取色", "↵ 全屏快截", "右键/esc 退出"]
                        Lb { required property string modelData; text: modelData; px: 10 }
                    }
                }
            }
        }
    }

    // ============ 保存完成后的右下角闪光预览卡片 ============
    PanelWindow {
        id: fired
        screen: root.scr
        visible: false
        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: root.shotRec ? null : card }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "glyph-shot"

        Stage {
            id: fstage

            Rectangle {
                id: flash
                readonly property real o: root.shotRec ? 4 : 0
                x: root.shotRect.x - o
                y: root.shotRect.y - o
                width: root.shotRect.width + o * 2
                height: root.shotRect.height + o * 2
                color: root.shotRec ? "transparent" : Theme.fade(Theme.fg, 0.12)
                border { width: 2; color: root.shotRec ? Theme.accent : Theme.fg }
                layer.enabled: fired.visible && !root.shotRec
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Theme.glow
                    shadowBlur: 0.7
                    blurMax: 20
                }
            }

            Rectangle {
                id: card
                property real t: 0
                visible: !root.shotRec
                x: fstage.width - 28 - width + 48 * (1 - t)
                y: fstage.height - 28 - height
                opacity: t
                width: 360
                height: col.height + 32
                radius: Theme.corner(40)
                color: Theme.s1
                border { width: 1; color: Theme.s2 }

                Column {
                    id: col
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 16
                    Item {
                        width: parent.width
                        height: 184
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: thumbMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                        Rectangle { anchors.fill: parent; color: Theme.s2 }
                        Image {
                            anchors.fill: parent
                            source: root.shot ? "file://" + root.shot : ""
                            sourceSize: Qt.size(328, 184)
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                        }
                    }
                    Item {
                        width: parent.width
                        height: cdims.height
                        Num { id: cdims; x: 8; text: root.shotDims; font.pixelSize: 30 }
                        Lb { anchors { right: parent.right; rightMargin: 8; bottom: parent.bottom } text: root.shotWhat; px: 11 }
                    }
                    Lb { x: 8; text: "saved & copied · click to re-edit"; px: 10; color: Theme.mute }
                }
                Rectangle { id: thumbMask; width: 328; height: 184; radius: Theme.corner(24); visible: false; layer.enabled: true }

                TapHandler { onTapped: { fx.stop(); fired.visible = false; editor.open(root.shot, root.scr); } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }

        SequentialAnimation {
            id: fx
            PropertyAction { target: fired; property: "visible"; value: true }
            ParallelAnimation {
                NumberAnimation { target: flash; property: "opacity"; from: 1; to: 0; duration: 900; easing.type: Easing.OutQuad }
                NumberAnimation { target: card; property: "t"; from: 0; to: 1; duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide }
            }
            PauseAnimation { duration: 2200 }
            NumberAnimation { target: card; property: "t"; to: 0; duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide }
            PropertyAction { target: fired; property: "visible"; value: false }
        }
    }

    // ============ 内部复用的点阵组件 ============
    component DotSep: Item {
        width: 14
        height: 36
        Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: Theme.mute }
    }

    component ToolBtn: Rectangle {
        id: tb
        property string icon: ""
        property string badgeText: ""
        property real iconRot: 0
        property string tip: ""
        property bool active: false
        property bool dimmed: false
        property bool danger: false
        signal clicked

        width: badgeText.length > 1 ? 40 : 34
        height: 36
        radius: 18
        opacity: dimmed ? 0.35 : 1.0
        color: active ? Theme.fg : (tbArea.containsMouse ? (danger ? Theme.nothingRed : Theme.s2) : "transparent")
        Behavior on color { ColorAnimation { duration: 110 } }

        Icon {
            visible: tb.icon !== ""
            anchors.centerIn: parent
            text: tb.icon
            rotation: tb.iconRot
            font.pixelSize: 16
            color: tb.active ? Theme.ink : (tbArea.containsMouse && tb.danger ? "#FFFFFF" : Theme.fg)
        }

        Rectangle {
            visible: tb.badgeText.length === 1
            anchors.centerIn: parent
            width: 18; height: 18; radius: 9
            color: tb.active ? Theme.nothingRed : "transparent"
            border { width: 1.5; color: tb.active ? Theme.nothingRed : Theme.fg }
            Text {
                anchors.centerIn: parent
                text: tb.badgeText
                font { family: Theme.mono; pixelSize: 11; weight: Font.Bold }
                color: tb.active ? "#FFFFFF" : Theme.fg
            }
        }

        Lb {
            visible: tb.badgeText.length > 1
            anchors.centerIn: parent
            text: tb.badgeText
            px: 10
            color: tb.active ? Theme.ink : Theme.fg
        }

        MouseArea {
            id: tbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: tb.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor
            onEntered: root.hoverTip = tb.tip
            onExited: if (root.hoverTip === tb.tip) root.hoverTip = ""
            onClicked: if (!tb.dimmed) tb.clicked()
        }
    }

    // 矢量与像素标注渲染器
    component MarkItem: Item {
        id: mk
        property var m
        property Item src
        readonly property real x0: Math.min(m.x1 ?? 0, m.x2 ?? 0)
        readonly property real y0: Math.min(m.y1 ?? 0, m.y2 ?? 0)
        readonly property real w0: Math.abs((m.x2 ?? 0) - (m.x1 ?? 0))
        readonly property real h0: Math.abs((m.y2 ?? 0) - (m.y1 ?? 0))

        Loader {
            sourceComponent: ({
                pen: penComp,
                marker: markerComp,
                line: lineComp,
                arrow: arrowComp,
                rect: rectComp,
                circle: circleComp,
                counter: counterComp,
                blur: blurComp,
                text: textComp
            })[mk.m.k]
        }

        Component {
            id: penComp
            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: mk.m.c
                    strokeWidth: mk.m.w
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: mk.m.pts }
                }
            }
        }

        Component {
            id: markerComp
            Shape {
                opacity: 0.38
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: mk.m.c
                    strokeWidth: mk.m.w
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: mk.m.pts }
                }
            }
        }

        Component {
            id: lineComp
            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: mk.m.c
                    strokeWidth: mk.m.w
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathPolyline { path: [Qt.point(mk.m.x1, mk.m.y1), Qt.point(mk.m.x2, mk.m.y2)] }
                }
            }
        }

        Component {
            id: arrowComp
            Shape {
                id: ar
                readonly property real a: Math.atan2(mk.m.y2 - mk.m.y1, mk.m.x2 - mk.m.x1)
                readonly property real hl: Math.max(12, mk.m.w * 4.2)
                readonly property point base: Qt.point(mk.m.x2 - Math.cos(a) * hl * 0.78, mk.m.y2 - Math.sin(a) * hl * 0.78)
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: mk.m.c
                    strokeWidth: mk.m.w
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathPolyline { path: [Qt.point(mk.m.x1, mk.m.y1), ar.base] }
                }
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: mk.m.c
                    PathPolyline {
                        path: [
                            Qt.point(mk.m.x2, mk.m.y2),
                            Qt.point(mk.m.x2 - Math.cos(ar.a - 0.46) * ar.hl, mk.m.y2 - Math.sin(ar.a - 0.46) * ar.hl),
                            Qt.point(mk.m.x2 - Math.cos(ar.a + 0.46) * ar.hl, mk.m.y2 - Math.sin(ar.a + 0.46) * ar.hl),
                            Qt.point(mk.m.x2, mk.m.y2)
                        ]
                    }
                }
            }
        }

        Component {
            id: rectComp
            Rectangle {
                x: mk.x0 - mk.m.w / 2
                y: mk.y0 - mk.m.w / 2
                width: mk.w0 + mk.m.w
                height: mk.h0 + mk.m.w
                color: "transparent"
                border { width: mk.m.w; color: mk.m.c }
            }
        }

        Component {
            id: circleComp
            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: mk.m.c
                    strokeWidth: mk.m.w
                    fillColor: "transparent"
                    PathAngleArc {
                        centerX: mk.x0 + mk.w0 / 2
                        centerY: mk.y0 + mk.h0 / 2
                        radiusX: Math.max(1, mk.w0 / 2)
                        radiusY: Math.max(1, mk.h0 / 2)
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
            }
        }

        Component {
            id: counterComp
            Rectangle {
                x: mk.m.x - mk.m.r
                y: mk.m.y - mk.m.r
                width: mk.m.r * 2
                height: mk.m.r * 2
                radius: mk.m.r
                color: mk.m.c
                border { width: 2; color: Qt.colorEqual(mk.m.c, "#FFFFFF") ? "#000000" : "#FFFFFF" }
                Text {
                    anchors.centerIn: parent
                    text: mk.m.num
                    font { family: Theme.mono; pixelSize: Math.round(mk.m.r * 1.15); weight: Font.Bold }
                    color: Qt.colorEqual(mk.m.c, "#FFFFFF") || Qt.colorEqual(mk.m.c, "#F5C542") || Qt.colorEqual(mk.m.c, "#3DD68C") ? "#000000" : "#FFFFFF"
                }
            }
        }

        Component {
            id: blurComp
            ShaderEffectSource {
                readonly property real px: Math.max(6, mk.m.w * 2.4)
                x: mk.x0
                y: mk.y0
                width: Math.max(1, mk.w0)
                height: Math.max(1, mk.h0)
                sourceItem: mk.src
                sourceRect: Qt.rect(mk.x0, mk.y0, Math.max(1, mk.w0), Math.max(1, mk.h0))
                textureSize: Qt.size(Math.max(1, Math.ceil(mk.w0 / px)), Math.max(1, Math.ceil(mk.h0 / px)))
                smooth: false
            }
        }

        Component {
            id: textComp
            Text {
                x: mk.m.x
                y: mk.m.y
                text: mk.m.t
                font { family: Theme.ui; pixelSize: mk.m.s; weight: Font.DemiBold }
                color: mk.m.c
                style: Text.Outline
                styleColor: Qt.colorEqual(mk.m.c, "#0B0B0B") ? "#FFFFFF" : "#000000"
            }
        }
    }

    component Dots: Image {
        fillMode: Image.Tile
        horizontalAlignment: Image.AlignLeft
        verticalAlignment: Image.AlignTop
        source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><circle cx="4" cy="4" r="1.2" fill="#${Theme.hex(Theme.fg)}"/></svg>`)
    }
}
