import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

// 日历 + 专注计时器 + Nothing OS 风格随手便签（点击顶栏时间弹出，或按 Super+R 直接聚焦便签输入）
PanelWindow {
    id: root

    property bool open: false
    property bool focusMemoOnOpen: false

    function toggle() {
        focusMemoOnOpen = false;
        open = !open;
    }
    function toggleMemo() {
        if (open && memoInput.activeFocus) {
            close();
        } else {
            focusMemoOnOpen = true;
            open = true;
            Qt.callLater(() => memoInput.forceActiveFocus());
        }
    }
    function close() {
        open = false;
        focusMemoOnOpen = false;
    }

    property int shift: 0
    onOpenChanged: {
        if (open) {
            shift = 0;
            if (focusMemoOnOpen) Qt.callLater(() => memoInput.forceActiveFocus());
            else panel.forceActiveFocus();
        }
    }

    // ---- 便签本地持久化 (~/.local/state/rice/memos.json) ----
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
            id: store
            property var items: []
        }
    }

    // 置顶在前、未完成在前、最新在前
    readonly property var sortedMemos: {
        const arr = (store.items ?? []).slice();
        arr.sort((a, b) => (Number(!!b.pinned) - Number(!!a.pinned))
                        || (Number(!!a.done) - Number(!!b.done))
                        || ((b.ts ?? 0) - (a.ts ?? 0)));
        return arr;
    }
    readonly property int doneCount: (store.items ?? []).filter(m => m.done).length

    function addMemo() {
        const txt = memoInput.text.trim();
        if (!txt) return;
        const now = new Date();
        const stamp = `${String(now.getMonth() + 1).padStart(2, "0")}/${String(now.getDate()).padStart(2, "0")} ${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
        store.items = [{
            id: String(Date.now()) + Math.random().toString(16).slice(2, 6),
            text: txt,
            done: false,
            pinned: false,
            time: stamp,
            ts: Date.now()
        }].concat(store.items ?? []);
        memoInput.text = "";
    }

    function toggleDone(id) {
        store.items = (store.items ?? []).map(m => m.id === id ? Object.assign({}, m, { done: !m.done }) : m);
    }

    function togglePin(id) {
        store.items = (store.items ?? []).map(m => m.id === id ? Object.assign({}, m, { pinned: !m.pinned }) : m);
    }

    function removeMemo(id) {
        store.items = (store.items ?? []).filter(m => m.id !== id);
    }

    function editMemo(m) {
        memoInput.text = m.text;
        removeMemo(m.id);
        memoInput.forceActiveFocus();
    }

    function clearDone() {
        store.items = (store.items ?? []).filter(m => !m.done);
    }

    property real t: open ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-cal"

    SystemClock { id: clock; precision: SystemClock.Hours }
    readonly property var en: Qt.locale("en_US")
    readonly property var month: new Date(clock.date.getFullYear(), clock.date.getMonth() + shift, 1)
    readonly property int lead: (month.getDay() + 6) % 7

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.35 * root.t
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Stage {
        id: stage

        Rectangle {
            id: panel
            readonly property bool onTop: Theme.state.barAt === "top"
            readonly property real off: (onTop ? 55 : 92) - 24 * (1 - root.t)
            x: onTop ? (parent.width - width) / 2 : off
            y: onTop ? off : Math.max(24, (parent.height - height) / 2)
            width: 460
            height: col.height + 48
            opacity: root.t
            radius: Theme.corner(36)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; return; }
                if (memoInput.activeFocus) return;
                if (e.key === Qt.Key_Left) root.shift--;
                else if (e.key === Qt.Key_Right) root.shift++;
                else if (e.key === Qt.Key_Space) Focus.toggle();
                else return;
                e.accepted = true;
            }
            MouseArea { anchors.fill: parent; onClicked: panel.forceActiveFocus() }

            Column {
                id: col
                x: 24
                y: 24
                width: parent.width - 48
                spacing: 14

                // ---- 月份标题 ----
                Item {
                    width: parent.width
                    height: 40
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Num { anchors.verticalCenter: parent.verticalCenter; text: root.en.standaloneMonthName(root.month.getMonth(), Locale.ShortFormat); font.pixelSize: 40 }
                        Lb { anchors.verticalCenter: parent.verticalCenter; text: root.month.getFullYear() }
                        TapHandler { onTapped: root.shift = 0 }
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Round { icon: "\u{F0141}"; onClicked: root.shift-- }
                        Round { icon: "\u{F0142}"; onClicked: root.shift++ }
                    }
                }

                // ---- 月历 7x6 ----
                Grid {
                    width: parent.width
                    columns: 7
                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]
                        Text {
                            required property string modelData
                            width: col.width / 7
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
                            id: day
                            required property int index
                            readonly property var d: new Date(root.month.getFullYear(), root.month.getMonth(), index - root.lead + 1)
                            readonly property bool own: d.getMonth() === root.month.getMonth()
                            readonly property bool today: d.toDateString() === clock.date.toDateString()
                            width: col.width / 7
                            height: 38
                            Rectangle { anchors.centerIn: parent; visible: day.today; width: 34; height: 34; radius: 17; color: Theme.fg }
                            Text {
                                anchors.centerIn: parent
                                text: day.d.getDate()
                                font { family: Theme.mono; pixelSize: 13 }
                                color: day.today ? Theme.ink : !day.own ? Theme.mute : day.index % 7 > 4 ? Theme.grey : Theme.fg
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.s2 }

                // ---- 专注倒计时 ----
                Row {
                    spacing: 20
                    Item {
                        width: 142
                        height: 142
                        Ring { anchors.fill: parent; n: 40; dot: 4.5; f: Focus.f }
                        Column {
                            anchors.centerIn: parent
                            Num { anchors.horizontalCenter: parent.horizontalCenter; text: Focus.mmss(Focus.left); font.pixelSize: 34 }
                            Lb {
                                anchors.horizontalCenter: parent.horizontalCenter
                                topPadding: 8
                                text: Focus.running ? "focus" : Focus.paused ? "paused" : "ready"
                                color: Focus.running ? Theme.fg : Theme.grey
                                px: 10
                            }
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Lb { text: "focus · min" }
                        Row {
                            spacing: 8
                            Repeater {
                                model: [15, 25, 45, 60]
                                Rectangle {
                                    id: chip
                                    required property int modelData
                                    readonly property bool on: Focus.minutes === modelData
                                    width: 42
                                    height: 42
                                    radius: 21
                                    color: on ? Theme.fg : chipHov.hovered ? Theme.s3 : Theme.s2
                                    Text { anchors.centerIn: parent; text: chip.modelData; font { family: Theme.mono; pixelSize: 13 } color: chip.on ? Theme.ink : Theme.fg }
                                    HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: Focus.set(chip.modelData) }
                                }
                            }
                        }
                        Row {
                            spacing: 10
                            Rectangle {
                                width: 142
                                height: 40
                                radius: Theme.corner(20)
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
                            Round { icon: "\u{F0450}"; opacity: Focus.running || Focus.paused ? 1 : 0.4; onClicked: Focus.reset() }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.s2 }

                // ---- Nothing OS 随手便签 / 待办 (MEMO) ----
                Item {
                    width: parent.width
                    height: 20
                    Row {
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.nothingRed
                        }
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

                // 输入胶囊（Nothing 红闪烁光标 + 回车保存）
                Rectangle {
                    id: inputBar
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
                                root.addMemo();
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
                        TapHandler { onTapped: root.addMemo() }
                    }
                }

                // 空状态提示
                Lb {
                    visible: root.sortedMemos.length === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 4
                    bottomPadding: 4
                    text: "no notes yet · super+r anytime"
                    color: Theme.mute
                    px: 10
                }

                // 便签卡片列表（超出自动滚动，保证弹窗绝不超出屏幕底边）
                ListView {
                    id: memoList
                    width: parent.width
                    readonly property real maxH: Math.max(120, stage.height - panel.y - 48 - y - 8)
                    height: Math.min(contentHeight, maxH)
                    visible: root.sortedMemos.length > 0
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.sortedMemos

                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        readonly property var m: modelData
                        width: memoList.width
                        height: Math.max(46, noteCol.height + 20)
                        radius: Theme.corner(18)
                        color: Theme.s2
                        border { width: m.pinned ? 1 : 0; color: m.pinned ? Theme.nothingRed : "transparent" }

                        HoverHandler { id: cardHov }

                        // 左侧勾选圆环（Nothing 极简点阵复选框）
                        Rectangle {
                            id: chk
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            radius: 10
                            color: card.m.done ? Theme.fg : "transparent"
                            border { width: 1.5; color: card.m.done ? Theme.fg : Theme.grey }
                            Icon {
                                visible: card.m.done
                                anchors.centerIn: parent
                                text: "\u{F012C}"
                                font.pixelSize: 12
                                color: Theme.ink
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.toggleDone(card.m.id) }
                        }

                        // 便签正文与时间（点击正文可重新放入输入框编辑）
                        Column {
                            id: noteCol
                            anchors {
                                left: chk.right
                                leftMargin: 12
                                right: actRow.left
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 2

                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                text: card.m.text
                                font {
                                    family: Theme.ui
                                    pixelSize: 14
                                    strikeout: !!card.m.done
                                }
                                color: card.m.done ? Theme.mute : Theme.fg
                            }
                            Lb {
                                visible: !!card.m.time
                                text: (card.m.pinned ? "pinned · " : "") + (card.m.time ?? "")
                                px: 9
                                color: card.m.pinned ? Theme.nothingRed : Theme.mute
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.editMemo(card.m) }
                        }

                        // 右侧置顶（红点/图钉）与删除按钮
                        Row {
                            id: actRow
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            opacity: cardHov.hovered || card.m.pinned ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }

                            Rectangle {
                                width: 26
                                height: 26
                                radius: 13
                                color: pinHov.hovered ? Theme.s3 : "transparent"
                                Icon {
                                    anchors.centerIn: parent
                                    text: "\u{F0403}"
                                    font.pixelSize: 13
                                    color: card.m.pinned ? Theme.nothingRed : Theme.grey
                                }
                                HoverHandler { id: pinHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.togglePin(card.m.id) }
                            }

                            Rectangle {
                                width: 26
                                height: 26
                                radius: 13
                                color: delHov.hovered ? Theme.s3 : "transparent"
                                Icon {
                                    anchors.centerIn: parent
                                    text: "\u{F0156}"
                                    font.pixelSize: 14
                                    color: delHov.hovered ? Theme.nothingRed : Theme.grey
                                }
                                HoverHandler { id: delHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.removeMemo(card.m.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    component Round: Rectangle {
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
