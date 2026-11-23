pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// 统一实时歌词源：兼容 Mineradio (/tmp/mineradio-live-lyric.json) + MPRIS 实时歌词流 (lyricsmpris --pipe)
Singleton {
    id: root

    property bool active: false
    property string pipeLyric: ""
    property string mineradioLyric: ""
    property string mineradioTitle: ""
    property string mineradioCover: ""
    property bool mineradioPlaying: false

    readonly property bool playing: (mineradioPlaying && mineradioTitle !== "") || Media.playing
    readonly property string artUrl: (mineradioPlaying && mineradioCover !== "") ? mineradioCover : (Media.player?.trackArtUrl ?? "")

    readonly property string displayText: {
        if (mineradioPlaying && mineradioLyric !== "") return mineradioLyric;
        if (mineradioPlaying && mineradioTitle !== "") return mineradioTitle;
        if (pipeLyric !== "") return pipeLyric;
        const t = Media.player?.trackTitle ?? "";
        const a = Media.player?.trackArtist ?? "";
        if (t && a) return `${t} · ${a}`;
        if (t) return t;
        return "NO TRACK PLAYING";
    }

    FileView {
        id: mrFile
        path: "/tmp/mineradio-live-lyric.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const obj = JSON.parse(text());
                root.mineradioTitle = String(obj.title || "").trim();
                root.mineradioLyric = String(obj.lyric || "").trim();
                root.mineradioCover = String(obj.localCover || obj.coverUrl || "").trim();
                root.mineradioPlaying = !!obj.playing;
            } catch (e) {}
        }
    }

    Process {
        running: root.active
        command: [Quickshell.env("HOME") + "/.local/share/glyph/ezioeen/bin/lyricsmpris", "--pipe"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const obj = JSON.parse(line);
                    if (obj.type === "line") {
                        root.pipeLyric = String(obj.text || "").trim();
                    } else if (obj.type === "status" && obj.status === "idle") {
                        root.pipeLyric = "";
                    }
                } catch (e) {}
            }
        }
        onRunningChanged: if (!running) root.pipeLyric = ""
    }
}
