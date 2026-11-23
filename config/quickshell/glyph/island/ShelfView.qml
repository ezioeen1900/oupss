import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components

// Nothing OS 点阵风格双向拖拽文件暂存器 (SHELF)
Item {
    id: root

    property var items: []
    property bool draggingOut: false
    property bool dropHover: false

    Component.onCompleted: shelfFile.waitForJob()

    FileView {
        id: shelfFile
        path: Theme.riceState + "/shelf.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: Qt.callLater(shelfFile.writeAdapter)
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: adapter
            property var list: []
        }
    }

    readonly property var list: adapter.list ?? []
    readonly property int count: list.length

    function iconForPath(p) {
        const ext = p.split(".").pop().toLowerCase();
        if (["png", "jpg", "jpeg", "webp", "gif", "svg", "bmp"].includes(ext)) return "image-x-generic";
        if (["mp4", "mkv", "webm", "mov", "avi"].includes(ext)) return "video-x-generic";
        if (["mp3", "flac", "wav", "ogg", "m4a"].includes(ext)) return "audio-x-generic";
        if (["zip", "tar", "gz", "xz", "zst", "7z", "rar"].includes(ext)) return "package-x-generic";
        if (["pdf"].includes(ext)) return "application-pdf";
        if (["doc", "docx", "odt", "xls", "xlsx", "ppt", "pptx"].includes(ext)) return "x-office-document";
        return "text-x-generic";
    }

    function addUrls(urls, rawText) {
        const incoming = [];
        if (urls && urls.length) {
            for (let i = 0; i < urls.length; i++) incoming.push(String(urls[i]));
        } else if (rawText) {
            const lines = String(rawText).split(/\r?\n/);
            for (let i = 0; i < lines.length; i++) {
                const s = lines[i].trim();
                if (s.startsWith("file://") || s.startsWith("/")) incoming.push(s);
            }
        }
        if (!incoming.length) return;

        let next = (adapter.list ?? []).slice();
        for (const raw of incoming) {
            let uri = raw;
            let filePath = raw;
            if (raw.startsWith("file://")) {
                filePath = decodeURIComponent(raw.slice(7));
            } else if (raw.startsWith("/")) {
                uri = "file://" + encodeURI(raw);
            } else {
                continue;
            }
            filePath = filePath.replace(/\/+$/, "") || "/";
            if (next.some(x => x.filePath === filePath)) continue;
            const base = filePath.split("/").pop() || filePath;
            const hasExt = base.includes(".") && !base.startsWith(".");
            next.unshift({
                uri: uri,
                filePath: filePath,
                name: base,
                ext: hasExt ? base.split(".").pop().toUpperCase().slice(0, 5) : "FILE",
                icon: hasExt ? iconForPath(base) : "folder"
            });
        }
        adapter.list = next;
    }

    function removeAt(idx) {
        const next = (adapter.list ?? []).slice();
        next.splice(idx, 1);
        adapter.list = next;
    }

    function clearAll() {
        adapter.list = [];
    }

    function mimeFor(it) {
        const u = String(it.uri);
        return {
            "text/uri-list": u + "\r\n",
            "text/plain": String(it.filePath),
            "x-special/gnome-copied-files": "copy\n" + u + "\n"
        };
    }

    // 接收外部文件拖入
    DropArea {
        anchors.fill: parent
        onEntered: drag => {
            root.dropHover = true;
            drag.accept(Qt.CopyAction);
        }
        onExited: root.dropHover = false
        onDropped: drop => {
            root.dropHover = false;
            root.addUrls(drop.urls, drop.text);
            drop.accept(Qt.CopyAction);
        }
    }

    Column {
        anchors.fill: parent
        spacing: 12

        // 顶部状态行
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
                    color: root.dropHover ? Theme.nothingRed : Theme.fg
                }
                Lb { text: `shelf · ${root.count} item${root.count === 1 ? "" : "s"}` }
            }
            Lb {
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                visible: root.count > 0
                text: "clear all"
                color: Theme.fg
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.clearAll() }
            }
        }

        // 空暂存架点阵虚线投递框
        Rectangle {
            visible: root.count === 0
            width: parent.width
            height: 176
            radius: Theme.corner(24)
            color: root.dropHover ? Theme.s3 : Theme.s2
            border { width: 1; color: root.dropHover ? Theme.nothingRed : Theme.s3 }

            Column {
                anchors.centerIn: parent
                spacing: 10
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{F0256}"
                    font.pixelSize: 28
                    color: root.dropHover ? Theme.nothingRed : Theme.grey
                }
                Lb {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "drag files here to stash"
                    color: Theme.fg
                }
                Lb {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "drag cards out to wechat · browser · dolphin"
                    color: Theme.mute
                    px: 9
                }
            }
        }

        // 横向卡片滚动画廊
        ListView {
            id: shelfList
            visible: root.count > 0
            width: parent.width
            height: 176
            orientation: ListView.Horizontal
            spacing: 12
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.list

            delegate: Item {
                id: del
                required property var modelData
                required property int index
                width: 142
                height: 172

                Rectangle {
                    id: card
                    width: 142
                    height: 172
                    radius: Theme.corner(22)
                    color: cardHov.hovered ? Theme.s3 : Theme.s2
                    border { width: dragHandler.active ? 1 : 0; color: Theme.nothingRed }
                    scale: dragHandler.active ? 1.04 : 1.0
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    Drag.dragType: Drag.Automatic
                    Drag.active: dragHandler.active
                    Drag.supportedActions: Qt.CopyAction
                    Drag.proposedAction: Qt.CopyAction
                    Drag.hotSpot: Qt.point(width / 2, height / 2)
                    Drag.imageSource: fileIcon.source
                    Drag.mimeData: root.mimeFor(del.modelData)

                    HoverHandler { id: cardHov; cursorShape: Qt.OpenHandCursor }

                    DragHandler {
                        id: dragHandler
                        target: null
                        onActiveChanged: root.draggingOut = active
                    }

                    TapHandler {
                        onTapped: Quickshell.execDetached(["xdg-open", String(del.modelData.filePath)])
                    }

                    // 右上角移除按钮
                    Rectangle {
                        z: 4
                        anchors { right: parent.right; top: parent.top; rightMargin: 8; topMargin: 8 }
                        width: 24
                        height: 24
                        radius: 12
                        color: rmHov.hovered ? Theme.nothingRed : Theme.s1
                        opacity: cardHov.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{F0156}"
                            font.pixelSize: 13
                            color: Theme.fg
                        }
                        HoverHandler { id: rmHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.removeAt(del.index) }
                    }

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        spacing: 10

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 68
                            height: 68
                            radius: 34
                            color: Theme.s1
                            Image {
                                id: fileIcon
                                anchors.centerIn: parent
                                width: 38
                                height: 38
                                source: Quickshell.iconPath(del.modelData.icon || "text-x-generic", "text-x-generic")
                                sourceSize: Qt.size(64, 64)
                                smooth: true
                            }
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            maximumLineCount: 2
                            wrapMode: Text.WrapAnywhere
                            textFormat: Text.PlainText
                            text: del.modelData.name
                            font { family: Theme.ui; pixelSize: 12; weight: Font.Medium }
                            color: Theme.fg
                        }

                        Lb {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: del.modelData.ext || "FILE"
                            px: 9
                            color: Theme.mute
                        }
                    }
                }
            }
        }
    }
}
