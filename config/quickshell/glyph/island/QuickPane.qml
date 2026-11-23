import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Notifications
import qs
import qs.components
import qs.settings
import qs.services
import "../quick"

// 内嵌在灵动岛同一个变形容器内的原生点阵控制中心内容层（单窗口零切换黑条、120fps 原地丝滑伸缩）
Item {
    id: root

    signal closeRequested
    signal switchTabsRequested
    signal powerRequested
    signal settingsRequested
    signal portalRequested
    signal vpnRequested

    property bool active: false
    property real maxStageHeight: 1080
    property string pick: ""

    onActiveChanged: if (active) Sys.earRun([]); else pick = ""

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var net: wifi?.networks.values.find(n => n.connected) ?? null
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var btDev: Bluetooth.devices.values.find(d => d.connected) ?? null
    SystemClock { id: clock; precision: SystemClock.Minutes }

    implicitWidth: 470
    implicitHeight: col.height + 44

    Column {
        id: col
        x: 22
        y: 20
        width: 470 - 44
        spacing: 15

        // 顶部点阵时钟 + 设置 / 电源圆钮（右键可直接切到日历/便签/暂存器页）
        Item {
            width: parent.width
            height: 50
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: root.switchTabsRequested()
            }
            Row {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Num { anchors.verticalCenter: parent.verticalCenter; text: `${Theme.hh(clock.date)}:${Qt.formatTime(clock.date, "mm")}`; font.pixelSize: 42 }
                Lb { anchors.verticalCenter: parent.verticalCenter; text: Qt.locale("en_US").toString(clock.date, "ddd d MMM") }
            }
            Row {
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 12
                Round { icon: "\u{F0493}"; onClicked: { root.closeRequested(); root.settingsRequested(); } }
                Round { icon: "\u{F0425}"; onClicked: { root.closeRequested(); root.powerRequested(); } }
            }
        }

        // Wi-Fi & 蓝牙胶囊 + 展开列表
        Column {
            id: nets
            width: parent.width
            Row {
                id: pills
                width: parent.width
                spacing: 12
                Pill {
                    on: Networking.wifiEnabled
                    icon: on ? "\u{F05A9}" : "\u{F05AA}"
                    name: "Wi-Fi"
                    sub: !on ? "off" : (Networking.connectivity === NetworkConnectivity.Portal ? "sign in · " : "") + (root.net?.name ?? "no network")
                    picked: root.pick === "wifi"
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                    onMenu: root.pick = picked ? "" : "wifi"
                }
                Pill {
                    on: root.bt?.enabled ?? false
                    icon: on ? "\u{F00AF}" : "\u{F00B2}"
                    name: "Bluetooth"
                    sub: !on ? "off" : root.btDev?.name ?? "on"
                    picked: root.pick === "bt"
                    onClicked: if (root.bt) root.bt.enabled = !root.bt.enabled
                    onMenu: root.pick = picked ? "" : "bt"
                }
            }
            Item {
                width: parent.width
                height: picker.open ? picker.height + 16 : 0
                Behavior on height { enabled: Rules.moving; NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
                visible: height > 0
                clip: true
                Picker {
                    id: picker
                    y: 16
                    width: parent.width
                    kind: root.pick
                    onPortalRequested: root.portalRequested()
                    max: Math.max(160, root.maxStageHeight - 360)
                }
            }
        }

        // Nothing / CMF 耳机降噪栏（连接时显示）
        Column {
            visible: !!Sys.ear
            width: parent.width
            spacing: 10
            Item {
                width: parent.width
                height: 20
                Lb { x: 6; text: Sys.buds?.name ?? "" }
                Lb {
                    anchors.right: parent.right
                    rightPadding: 6
                    text: Sys.earBat.map(k => `${k} ${Sys.ear[k]}`).join(" · ")
                    color: Theme.fg
                }
            }
            Rectangle {
                id: anc
                visible: Sys.ear?.mode !== undefined && Sys.ancModes.length > 0
                width: parent.width
                height: 52
                radius: Theme.corner(26)
                color: Theme.s2
                readonly property real cell: (width - 12) / Math.max(1, Sys.ancModes.length)
                readonly property int at: Sys.ancModes.findIndex(m => m[0] === Sys.ear?.mode)
                Rectangle {
                    visible: anc.at >= 0
                    x: 6 + anc.cell * anc.at
                    y: 6
                    width: anc.cell
                    height: parent.height - 12
                    radius: height / 2
                    color: Theme.fg
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                }
                Repeater {
                    model: Sys.ancModes
                    Item {
                        id: am
                        required property var modelData
                        required property int index
                        x: 6 + anc.cell * index
                        width: anc.cell
                        height: anc.height
                        Lb { anchors.centerIn: parent; text: am.modelData[1]; color: anc.at === am.index ? Theme.ink : Theme.grey }
                        TapHandler { onTapped: Sys.setAnc(am.modelData[0]) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }

        // 8 个快捷开关圆砖（VPN 左键开关系统代理，右键呼出 Clash 节点面板）
        Grid {
            width: parent.width
            columns: 4
            rowSpacing: 14
            Tile { icon: "\u{F009B}"; name: "dnd"; on: Theme.state.dnd; onClicked: Theme.state.dnd = !Theme.state.dnd }
            Tile { icon: "\u{F0594}"; name: "night"; on: Sys.night; onClicked: Sys.toggleNight() }
            Tile { icon: "\u{F001D}"; name: "airplane"; on: Sys.air; onClicked: Sys.toggleAir() }
            Tile { icon: "\u{F0176}"; name: "caffeine"; on: Sys.caffeine; onClicked: Sys.caffeine = !Sys.caffeine }
            Tile { icon: on ? "\u{F036C}" : "\u{F036D}"; name: "mic"; on: Sys.micOn; onClicked: Sys.toggleMic() }
            Tile { icon: "\u{F044A}"; name: "record"; on: Sys.rec; picked: root.pick === "rec"; onClicked: { root.closeRequested(); Sys.toggleRec(); } onMenu: root.pick = picked ? "" : "rec" }
            Tile { icon: "\u{F0483}"; name: "vpn"; on: Sys.vpn; onClicked: Sys.toggleVpn(); onMenu: { root.closeRequested(); root.vpnRequested(); } }
            Tile { icon: "\u{F050E}"; name: "dark"; on: !Theme.light; onClicked: Theme.setLight(!Theme.light) }
        }

        Rec { width: parent.width; visible: root.pick === "rec"; onStart: { root.closeRequested(); Sys.toggleRec(); } }

        // 亮度与音量点阵滑条
        Slider { icon: "\u{F00E0}"; visible: Sys.hasBri; value: Sys.bri; onMoved: v => Sys.setBri(v) }
        Slider { icon: Sys.muted ? "\u{F075F}" : "\u{F057E}"; value: Sys.muted ? 0 : Sys.vol; onMoved: v => Sys.setVol(v) }

        // 性能档位 + 游戏模式
        Row {
            width: parent.width
            spacing: 12
            Rectangle {
                id: modes
                width: parent.width - game.width - 12
                height: 52
                radius: Theme.corner(26)
                color: Theme.s2
                readonly property real cell: (width - 12) / Rules.modeCount
                Rectangle {
                    x: 6 + modes.cell * Rules.mode
                    y: 6
                    width: modes.cell
                    height: parent.height - 12
                    radius: height / 2
                    color: Theme.fg
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                }
                Repeater {
                    model: Rules.modeCount
                    Item {
                        id: mc
                        required property int index
                        readonly property bool on: Rules.mode === index
                        x: 6 + modes.cell * index
                        width: modes.cell
                        height: modes.height
                        Row {
                            anchors.centerIn: parent
                            spacing: 10
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                Repeater {
                                    model: 4
                                    Rectangle {
                                        required property int index
                                        anchors.bottom: parent.bottom
                                        width: 4
                                        height: 6 + index * 4
                                        radius: 2
                                        color: index <= mc.index ? (mc.on ? Theme.ink : Theme.fg) : (mc.on ? Theme.mute : Theme.s3)
                                    }
                                }
                            }
                            Lb { anchors.verticalCenter: parent.verticalCenter; text: Rules.modes[mc.index].short; color: mc.on ? Theme.ink : Theme.grey }
                        }
                        TapHandler { onTapped: Rules.setMode(mc.index) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
            Rectangle {
                id: game
                width: 52
                height: 52
                radius: 26
                color: Rules.store.game ? Theme.fg : Theme.s2
                Icon { anchors.centerIn: parent; text: "\u{F0297}"; font.pixelSize: 22; color: Rules.store.game ? Theme.ink : Theme.fg }
                TapHandler { onTapped: Rules.store.game = !Rules.store.game }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }

        // 迷你媒体播放器
        Rectangle {
            visible: !!Media.player
            width: parent.width
            height: 82
            radius: Theme.corner(28)
            color: Theme.s2
            Art { id: mart; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 58; height: 58; step: 4; url: Media.player?.trackArtUrl ?? "" }
            Column {
                anchors { left: mart.right; leftMargin: 14; right: mctl.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: Media.player?.trackTitle || "Nothing on"; font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: Theme.fg }
                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: Media.player?.trackArtist ?? ""; font { family: Theme.ui; pixelSize: 12 } color: Theme.grey }
            }
            Controls { id: mctl; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } size: 19; play: 42 }
        }

        // 通知列表头
        Item {
            width: parent.width
            height: 18
            Lb { x: 6; text: `notifications · ${Notes.list.length}` }
            Lb {
                anchors.right: parent.right
                rightPadding: 6
                visible: Notes.list.length > 0
                text: "clear all"
                color: Theme.fg
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Notes.clear() }
            }
        }

        // 通知卡片列表
        ListView {
            id: notes
            width: parent.width
            height: Math.max(0, Math.min(contentHeight, Math.max(120, root.maxStageHeight - y - 64)))
            visible: contentHeight > 0
            clip: true
            spacing: 10
            model: Notes.list.slice().reverse()
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                required property var modelData
                readonly property var n: modelData
                width: notes.width
                height: body.height + 28
                radius: Theme.corner(24)
                color: Theme.s2
                border { width: n.urgency === NotificationUrgency.Critical ? 1 : 0; color: Theme.red }

                Rectangle {
                    x: 16; y: 14; width: 40; height: 40; radius: 20; color: Theme.s3
                    Icon { anchors.centerIn: parent; text: "\u{F009A}"; visible: !nicon.visible }
                    Image {
                        id: nicon
                        anchors.centerIn: parent
                        width: 22; height: 22
                        visible: status === Image.Ready
                        source: n.appIcon ? Quickshell.iconPath(n.appIcon, true) : ""
                        sourceSize: Qt.size(22, 22)
                        layer.enabled: true
                        layer.effect: Dm { step: 2 }
                    }
                }
                Column {
                    id: body
                    x: 68; y: 14
                    width: parent.width - x - 16
                    Lb { width: parent.width; elide: Text.ElideRight; text: `${n.appName || "app"} · ${Notes.ago(n, clock.date.getTime())}`; px: 10 }
                    Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: n.summary; font { family: Theme.ui; pixelSize: 14; weight: Font.DemiBold } color: Theme.fg }
                    Text {
                        width: parent.width
                        visible: !!n.body
                        topPadding: 2
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: n.body
                        font { family: Theme.ui; pixelSize: 13 }
                        color: Theme.grey
                    }
                }
                TapHandler {
                    onTapped: {
                        const it = n;
                        it.actions.find(a => a.identifier === "default")?.invoke();
                        if (it.tracked) it.dismiss();
                    }
                }
            }
        }
    }

    component Round: Rectangle {
        property string icon
        signal clicked
        width: 42; height: 42; radius: 21; color: Theme.s2
        Icon { anchors.centerIn: parent; text: parent.icon }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.clicked() }
    }

    component Pill: Rectangle {
        id: pill
        property bool on
        property bool picked
        signal menu
        property string icon
        property string name
        property string sub
        signal clicked
        width: (col.width - 12) / 2
        height: 72
        radius: Theme.corner(36)
        color: on ? Theme.fg : Theme.s2
        Behavior on color { ColorAnimation { duration: 160 } }
        Rectangle {
            id: pi
            x: 12; anchors.verticalCenter: parent.verticalCenter
            width: 48; height: 48; radius: 24
            color: pill.on ? Theme.ink : Theme.s3
            Icon { anchors.centerIn: parent; text: pill.icon; font.pixelSize: 21 }
        }
        Column {
            anchors { left: pi.right; leftMargin: 12; right: chev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            Text { text: pill.name; font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: pill.on ? Theme.ink : Theme.fg }
            Text {
                width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: pill.sub
                font { family: Theme.mono; pixelSize: 10; letterSpacing: 0.9; capitalization: Font.AllUppercase }
                color: pill.on ? Theme.ink : Theme.fg; opacity: 0.6
            }
        }
        Icon {
            id: chev
            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            text: "\u{F0140}"; font.pixelSize: 18
            color: pill.on ? Theme.ink : Theme.fg
            opacity: pill.picked ? 1 : 0.4
            rotation: pill.picked ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pill.clicked() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: pill.menu() }
    }

    component Tile: Column {
        id: tile
        property bool on
        property bool picked
        signal menu
        property string icon
        property string name
        signal clicked
        width: col.width / 4
        spacing: 7
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 64; height: 64; radius: 32
            color: tile.on ? Theme.fg : Theme.s2
            Behavior on color { ColorAnimation { duration: 160 } }
            Icon { anchors.centerIn: parent; text: tile.icon; font.pixelSize: 23; color: tile.on ? Theme.ink : Theme.fg }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: tile.clicked() }
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: tile.menu() }
        }
        Lb { anchors.horizontalCenter: parent.horizontalCenter; text: tile.name; px: 10; color: tile.picked ? Theme.fg : Theme.grey }
    }

    component Slider: Rectangle {
        id: sl
        property real value
        property string icon
        signal moved(real v)
        readonly property real shown: area.pressed ? area.v : value
        width: col.width
        height: 50
        radius: Theme.corner(25)
        color: Theme.s2
        Row {
            x: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 11 - 2.8
            Repeater {
                model: Math.max(0, Math.floor((sl.width - 20) / 11) + 1)
                Rectangle { width: 2.8; height: 2.8; radius: 1.4; color: Theme.mute }
            }
        }
        Rectangle {
            width: Math.max(height, sl.width * sl.shown)
            height: parent.height
            radius: Theme.corner(25)
            color: Theme.fg
            Icon { x: 17; anchors.verticalCenter: parent.verticalCenter; text: sl.icon; font.pixelSize: 20; color: Theme.ink }
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: val.width + 16; height: val.height + 8
            radius: Theme.corner(10); color: Theme.s2
            Lb { id: val; anchors.centerIn: parent; text: Math.round(sl.shown * 100) }
        }
        MouseArea {
            id: area
            property real v
            property real wacc: 0
            anchors.fill: parent
            preventStealing: true
            function set(x) { v = Math.max(0, Math.min(1, x / width)); sl.moved(v); }
            onPressed: e => set(e.x)
            onPositionChanged: e => set(e.x)
            onWheel: e => {
                wacc += (e.inverted ? -1 : 1) * (e.angleDelta.y || -e.angleDelta.x) / 120 * 0.05 * (e.phase === Qt.NoScrollPhase ? 1 : 0.25);
                if (Math.abs(wacc) < 0.02) return;
                sl.moved(Math.max(0, Math.min(1, sl.shown + wacc)));
                wacc = 0;
            }
        }
    }
}
