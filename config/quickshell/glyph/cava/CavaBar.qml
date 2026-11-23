import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

// 底部 Nothing OS 点阵风格 Cava 音频律动条（仅在空桌面背景层显示，占底边 8/10 宽度）
Scope {
    id: root

    readonly property int halfBars: 50
    readonly property int cols: halfBars * 2
    property var bars: Array(halfBars).fill(0)
    property bool playing: false

    function isEmpty(s) {
        return (Hyprland.monitorFor(s)?.activeWorkspace?.toplevels.values.length ?? 0) === 0;
    }
    readonly property bool anyEmpty: Quickshell.screens.some(s => root.isEmpty(s))

    Timer {
        id: quietT
        interval: 1800
        onTriggered: root.playing = false
    }

    Process {
        running: root.anyEmpty
        command: ["cava", "-p", Qt.resolvedUrl("cava.conf").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: line => {
                const vals = line.split(";").filter(s => s !== "").map(v => Number(v) / 100);
                if (!vals.length) return;
                root.bars = vals;
                if (vals.some(v => v > 0.015)) {
                    root.playing = true;
                    quietT.restart();
                }
            }
        }
        onRunningChanged: if (!running) { root.playing = false; root.bars = Array(root.halfBars).fill(0); }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            readonly property bool empty: root.isEmpty(modelData)
            readonly property bool shown: root.playing && win.empty && !Sys.deckOpen
            property real t: shown ? 1 : 0
            Behavior on t { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

            visible: t > 0
            anchors { left: true; right: true; bottom: true }
            implicitHeight: Math.ceil(62 * Theme.s)
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "glyph-cava"

            Stage {
                Item {
                    id: area
                    anchors.fill: parent
                    opacity: win.t
                    transform: Translate { y: 12 * (1 - win.t) }

                    readonly property real dotSize: 6
                    readonly property real spanWidth: parent.width * 0.8

                    Row {
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            bottom: parent.bottom
                            bottomMargin: 6
                        }
                        spacing: (area.spanWidth - root.cols * area.dotSize) / (root.cols - 1)

                        Repeater {
                            model: root.cols

                            Column {
                                id: col
                                required property int index
                                readonly property int bi: Math.min(root.halfBars - 1, Math.floor(Math.abs(index - (root.cols - 1) / 2)))
                                readonly property real v: root.bars[bi] ?? 0
                                readonly property int lit: Math.round(v * 7)
                                spacing: 2.5

                                Repeater {
                                    model: 7

                                    Rectangle {
                                        required property int index
                                        readonly property int lv: 6 - index
                                        readonly property bool on: lv < col.lit
                                        width: area.dotSize
                                        height: area.dotSize
                                        radius: width / 2
                                        color: !on ? Theme.fg : (lv === 6 ? Theme.nothingRed : Theme.fg)
                                        opacity: on ? 0.95 : (lv === 0 ? 0.22 : 0)
                                        Behavior on opacity { NumberAnimation { duration: 55 } }
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
