import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// меню питания: Super+Esc / Alt+Shift+P. 点击 SHUT DOWN 或 REBOOT 时先播放 ~1.25s Nothing OS 环形归零与红点熄屏过渡动画，再无缝切入关机跑码
PanelWindow {
    id: root

    property int sel: 2
    property string halting: "" // "" | "SHUT DOWN" | "REBOOT"
    property real shutP: 0      // 0 → 1 关机熄火动画进度

    readonly property var items: [
        ["LOCK", () => Quickshell.execDetached([Quickshell.env("HOME") + "/.config/quickshell/rice/rice", "lock"])],
        ["SLEEP", () => Quickshell.execDetached(["systemctl", "suspend"])],
        ["SHUT DOWN", () => Quickshell.execDetached(["systemctl", "poweroff"])],
        ["REBOOT", () => Quickshell.execDetached(["systemctl", "reboot"])],
        ["LOG OUT", () => Hyprland.dispatch("hl.dsp.exit()")]
    ]

    function open() {
        halting = "";
        shutP = 0;
        sel = 2;
        SysStats.sample();
        visible = true;
    }
    function close() {
        if (halting) return;
        visible = false;
    }
    function accept() {
        if (halting) return;
        if (sel === 2 || sel === 3) {
            halting = items[sel][0];
            shutAnim.start();
            return;
        }
        visible = false;
        items[sel][1]();
    }

    NumberAnimation {
        id: shutAnim
        target: root
        property: "shutP"
        from: 0
        to: 1
        duration: 1280
        easing.type: Easing.Linear
        onFinished: {
            const cmd = root.halting === "REBOOT" ? "reboot" : "poweroff";
            Quickshell.execDetached(["systemctl", cmd]);
        }
    }

    visible: false
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-power"

    Rectangle {
        anchors.fill: parent
        color: root.halting ? "#000000" : Theme.fade(Theme.bg, 0.96)
        Behavior on color { ColorAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Stage {
        id: stage
        focus: true
        Keys.onPressed: e => {
            if (root.halting) { e.accepted = true; return; }
            if (e.key === Qt.Key_Up || e.key === Qt.Key_K) root.sel = (root.sel + 4) % 5;
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_J || e.key === Qt.Key_Tab) root.sel = (root.sel + 1) % 5;
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.accept();
            else if (e.key === Qt.Key_Escape) root.close();
            else return;
            e.accepted = true;
        }

        // 正常电源菜单层
        Item {
            anchors.fill: parent
            opacity: root.halting ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180 } }
            visible: opacity > 0

            Column {
                x: 240
                anchors.verticalCenter: parent.verticalCenter
                spacing: 26
                Repeater {
                    model: root.items
                    Row {
                        id: it
                        required property var modelData
                        required property int index
                        readonly property bool on: root.sel === index
                        spacing: 30
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: it.on
                            width: 30
                            height: 30
                            radius: 15
                            color: Theme.accent
                        }
                        Num {
                            text: it.modelData[0]
                            font.pixelSize: it.on ? 168 : 66
                            color: it.on ? Theme.fg : Theme.mute
                            Behavior on font.pixelSize { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                            Behavior on color { ColorAnimation { duration: Theme.t } }
                        }
                        HoverHandler { onHoveredChanged: if (hovered && !root.halting) root.sel = it.index }
                        TapHandler { onTapped: { if (!root.halting) { root.sel = it.index; root.accept(); } } }
                    }
                }
            }

            Item {
                x: stage.width - 200 - 460
                anchors.verticalCenter: parent.verticalCenter
                width: 460
                height: 460
                Ring { anchors.fill: parent; n: 60; dot: 10; f: SysStats.uptime / (6 * 3600) }
                Column {
                    anchors.centerIn: parent
                    Lb { anchors.horizontalCenter: parent.horizontalCenter; text: "uptime" }
                    Num {
                        anchors.horizontalCenter: parent.horizontalCenter
                        topPadding: lead + 10
                        bottomPadding: lead + 10
                        text: `${Math.floor(SysStats.uptime / 3600)}:${String(Math.floor(SysStats.uptime / 60) % 60).padStart(2, "0")}`
                        font.pixelSize: 110
                    }
                    Lb {
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property int n: Hyprland.toplevels.values.length
                        text: `${n} window${n === 1 ? "" : "s"} open`
                    }
                }
            }

            Row {
                x: 240
                anchors { bottom: parent.bottom; bottomMargin: 70 }
                spacing: 34
                Lb { text: "↑↓ select" }
                Lb { text: "↵ confirm" }
                Lb { text: "esc cancel" }
            }
        }

        // Nothing OS 关机 / 重启熄火过渡层（Phase 1: 0..0.68 环形倒退收缩；Phase 2: 0.68..1.0 横线收束与红点熄灭）
        Item {
            id: outro
            anchors.fill: parent
            visible: !!root.halting
            readonly property real cx: width / 2
            readonly property real cy: height / 2 - 20
            readonly property bool phase1: root.shutP < 0.68
            readonly property real k1: phase1 ? 1 - root.shutP / 0.68 : 0
            readonly property real ease1: k1 * k1
            readonly property real u2: phase1 ? 0 : Math.min(1, (root.shutP - 0.68) / 0.30)

            // 36 点圆环逆向熄灭并向心收缩
            Repeater {
                model: 36
                Rectangle {
                    required property int index
                    readonly property real ang: -Math.PI / 2 + (index / 36) * Math.PI * 2
                    readonly property real rad: 44 + 96 * outro.ease1
                    readonly property int keep: Math.ceil(outro.ease1 * 36)
                    readonly property bool lit: index < keep
                    visible: outro.phase1
                    width: lit ? 7 : 4
                    height: width
                    radius: width / 2
                    x: outro.cx + Math.cos(ang) * rad - width / 2
                    y: outro.cy + Math.sin(ang) * rad - height / 2
                    color: lit ? (index === keep - 1 ? Theme.nothingRed : "#F2F2F2") : "#222222"
                }
            }

            // 阶段 2 横向白线收束
            Rectangle {
                visible: !outro.phase1 && width > 2
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -20
                width: Math.max(0, 460 * (1 - outro.u2 * outro.u2))
                height: 3
                radius: 1.5
                color: "#F2F2F2"
                opacity: 1 - outro.u2
            }

            // 中央 Nothing Red 核心红点收束熄灭
            Rectangle {
                readonly property real sz: outro.phase1 ? 16 : 18 * (1 - 0.7 * outro.u2)
                width: sz
                height: sz
                radius: sz / 2
                x: outro.cx - width / 2
                y: outro.cy - height / 2
                color: Theme.nothingRed
                opacity: outro.phase1 ? 1 : Math.max(0, 1 - outro.u2)
            }

            // 点阵字标渐隐（SHUT DOWN / REBOOT）
            Num {
                visible: outro.phase1
                anchors.horizontalCenter: parent.horizontalCenter
                y: outro.cy + 165
                text: root.halting
                font.pixelSize: 38
                color: "#8C8C8C"
                opacity: outro.ease1 * 0.9
            }
        }
    }
}
