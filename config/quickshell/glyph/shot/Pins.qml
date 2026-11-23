import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs
import qs.components

// Nothing OS 点阵风格桌面悬浮贴图（Snipaste / Flameshot Pin 同款体验）：
// 截完一键原位钉在桌面上，支持自由拖拽、滚轮无级缩放（35%–300%）、悬停复制/半透明对比/关闭、双击或右键秒关
Scope {
    id: root

    property var list: [] // [{ id, path, scr, x, y, w, h, zoom, ghost }]

    function add(path, screen, x, y, w, h) {
        const id = String(Date.now()) + Math.random().toString(16).slice(2, 6);
        list = list.concat([{
            id: id,
            path: path,
            scr: screen,
            x: Math.round(x),
            y: Math.round(y),
            w: Math.max(48, Math.round(w)),
            h: Math.max(48, Math.round(h)),
            zoom: 1.0,
            ghost: false
        }]);
    }

    function remove(id) {
        const it = list.find(p => p.id === id);
        list = list.filter(p => p.id !== id);
        if (it && it.path.includes("/glyph-pin-"))
            Quickshell.execDetached(["rm", "-f", it.path]);
    }

    function copyPin(path) {
        Quickshell.execDetached(["sh", "-c", 'wl-copy -t image/png < "$1"', "sh", path]);
    }

    Variants {
        model: root.list

        PanelWindow {
            id: pwin
            required property var modelData

            property real px: modelData.x
            property real py: modelData.y
            property real zoom: modelData.zoom
            property bool ghost: modelData.ghost

            screen: modelData.scr
            visible: true
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "glyph-pin"

            mask: Region { item: cardHit }

            Item {
                id: cardHit
                x: card.x - 4
                y: card.y - (bar.opacity > 0.05 ? 40 : 4)
                width: card.width + 8
                height: card.height + (bar.opacity > 0.05 ? 44 : 8)
            }

            // 顶部迷你 Nothing 工具胶囊（悬停浮现）
            Rectangle {
                id: bar
                z: 5
                x: Math.max(8, Math.min(pwin.width - width - 8, card.x + card.width - width))
                y: card.y > 46 ? card.y - 38 : card.y + 8
                width: barRow.width + 18
                height: 30
                radius: 15
                color: Theme.s1
                border { width: 1; color: Theme.s3 }
                opacity: cardHov.hovered || barHov.hovered ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 140 } }
                HoverHandler { id: barHov }

                Row {
                    id: barRow
                    anchors.centerIn: parent
                    spacing: 8

                    Lb {
                        anchors.verticalCenter: parent.verticalCenter
                        text: `${Math.round(pwin.zoom * 100)}%`
                        px: 9
                        color: Theme.grey
                    }

                    // 半透明穿透对比切换
                    Rectangle {
                        width: 22; height: 22; radius: 11
                        color: pwin.ghost ? Theme.fg : (gHov.hovered ? Theme.s3 : "transparent")
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{F0208}"
                            font.pixelSize: 12
                            color: pwin.ghost ? Theme.ink : Theme.fg
                        }
                        HoverHandler { id: gHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: pwin.ghost = !pwin.ghost }
                    }

                    // 复制到剪贴板
                    Rectangle {
                        width: 22; height: 22; radius: 11
                        color: cpHov.hovered ? Theme.s3 : "transparent"
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{F018F}"
                            font.pixelSize: 12
                            color: Theme.fg
                        }
                        HoverHandler { id: cpHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.copyPin(pwin.modelData.path) }
                    }

                    // 关闭贴图
                    Rectangle {
                        width: 22; height: 22; radius: 11
                        color: clHov.hovered ? Theme.nothingRed : "transparent"
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{F0156}"
                            font.pixelSize: 13
                            color: Theme.fg
                        }
                        HoverHandler { id: clHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.remove(pwin.modelData.id) }
                    }
                }
            }

            Rectangle {
                id: card
                x: pwin.px
                y: pwin.py
                width: Math.round(pwin.modelData.w * pwin.zoom)
                height: Math.round(pwin.modelData.h * pwin.zoom)
                color: "#000000"
                opacity: pwin.ghost ? 0.48 : 1.0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                border { width: 1.5; color: cardHov.hovered ? Theme.nothingRed : Theme.fg }

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.65)
                    shadowBlur: 0.8
                    blurMax: 24
                    shadowVerticalOffset: 6
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: 1.5
                    source: "file://" + pwin.modelData.path
                    smooth: true
                    mipmap: true
                }

                // 四角 Nothing 点阵圆点装饰（悬停显现）
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        visible: cardHov.hovered
                        x: (index % 2 ? card.width : 0) - 4
                        y: (index > 1 ? card.height : 0) - 4
                        width: 8; height: 8; radius: 4
                        color: Theme.nothingRed
                    }
                }

                HoverHandler { id: cardHov; cursorShape: dragArea.pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    property point startMouse
                    property point startPos
                    onPressed: e => {
                        if (e.button === Qt.RightButton) {
                            root.remove(pwin.modelData.id);
                            return;
                        }
                        startMouse = mapToItem(null, e.x, e.y);
                        startPos = Qt.point(pwin.px, pwin.py);
                    }
                    onPositionChanged: e => {
                        if (!(pressedButtons & Qt.LeftButton)) return;
                        const cur = mapToItem(null, e.x, e.y);
                        pwin.px = Math.max(-card.width + 48, Math.min(pwin.width - 48, startPos.x + (cur.x - startMouse.x)));
                        pwin.py = Math.max(0, Math.min(pwin.height - 48, startPos.y + (cur.y - startMouse.y)));
                    }
                    onDoubleClicked: e => {
                        if (e.button === Qt.LeftButton) root.remove(pwin.modelData.id);
                    }
                    onWheel: e => {
                        const step = e.angleDelta.y > 0 ? 1.1 : (1 / 1.1);
                        const nextZ = Math.max(0.35, Math.min(3.0, pwin.zoom * step));
                        const cx = pwin.px + card.width / 2;
                        const cy = pwin.py + card.height / 2;
                        pwin.zoom = nextZ;
                        pwin.px = Math.round(cx - (pwin.modelData.w * nextZ) / 2);
                        pwin.py = Math.round(cy - (pwin.modelData.h * nextZ) / 2);
                    }
                }
            }
        }
    }
}
