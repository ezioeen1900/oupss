import QtQuick
import QtQuick.Shapes

// 纯 GPU 矢量渲染的一体化灵动岛轮廓（零纹理重分配、零首帧黑闪、120fps 丝滑变形）
Shape {
    id: root

    property real earSize: 0
    property real topRadius: 16
    property real bottomRadius: 26
    property color fillColor: "#000000"
    property color borderColor: "#262626"

    preferredRendererType: Shape.CurveRenderer

    readonly property real e: Math.max(0, Math.min(earSize, height * 0.45, width * 0.25))
    readonly property bool docked: e > 0.5
    readonly property real xl: e + 0.5
    readonly property real xr: Math.max(xl + 2, width - e - 0.5)
    readonly property real yb: Math.max(2, height - 0.5)
    readonly property real bodyW: xr - xl
    readonly property real rb: Math.max(0, Math.min(bottomRadius - 0.5, bodyW / 2, yb / 2))
    readonly property real rt: docked ? 0 : Math.max(0, Math.min(topRadius - 0.5, bodyW / 2, yb / 2))

    // 1. 悬浮圆角胶囊态 (earSize == 0)
    ShapePath {
        fillColor: root.docked ? "transparent" : root.fillColor
        strokeColor: root.docked ? "transparent" : root.borderColor
        strokeWidth: root.docked ? -1 : 1
        startX: root.xl + root.rt
        startY: 0.5
        PathLine { x: root.xr - root.rt; y: 0.5 }
        PathArc { x: root.xr; y: 0.5 + root.rt; radiusX: root.rt; radiusY: root.rt }
        PathLine { x: root.xr; y: root.yb - root.rb }
        PathArc { x: root.xr - root.rb; y: root.yb; radiusX: root.rb; radiusY: root.rb }
        PathLine { x: root.xl + root.rb; y: root.yb }
        PathArc { x: root.xl; y: root.yb - root.rb; radiusX: root.rb; radiusY: root.rb }
        PathLine { x: root.xl; y: 0.5 + root.rt }
        PathArc { x: root.xl + root.rt; y: 0.5; radiusX: root.rt; radiusY: root.rt }
    }

    // 2A. 贴顶液态内凹耳朵态：无接缝纯黑填充
    ShapePath {
        fillColor: root.docked ? root.fillColor : "transparent"
        strokeColor: "transparent"
        strokeWidth: -1
        startX: 0
        startY: 0
        PathLine { x: root.width; y: 0 }
        PathArc { x: root.xr; y: root.e; radiusX: root.e; radiusY: root.e; direction: PathArc.Counterclockwise }
        PathLine { x: root.xr; y: root.yb - root.rb }
        PathArc { x: root.xr - root.rb; y: root.yb; radiusX: root.rb; radiusY: root.rb }
        PathLine { x: root.xl + root.rb; y: root.yb }
        PathArc { x: root.xl; y: root.yb - root.rb; radiusX: root.rb; radiusY: root.rb }
        PathLine { x: root.xl; y: root.e }
        PathArc { x: 0; y: 0; radiusX: root.e; radiusY: root.e; direction: PathArc.Counterclockwise }
    }

    // 2B. 贴顶液态内凹耳朵态：连续 1px 外轮廓描边（不含 y=0 屏幕顶边）
    ShapePath {
        fillColor: "transparent"
        strokeColor: root.docked ? root.borderColor : "transparent"
        strokeWidth: root.docked ? 1 : -1
        startX: 0
        startY: 0
        PathArc { x: root.xl; y: root.e; radiusX: root.e; radiusY: root.e; direction: PathArc.Clockwise }
        PathLine { x: root.xl; y: root.yb - root.rb }
        PathArc { x: root.xl + root.rb; y: root.yb; radiusX: root.rb; radiusY: root.rb; direction: PathArc.Counterclockwise }
        PathLine { x: root.xr - root.rb; y: root.yb }
        PathArc { x: root.xr; y: root.yb - root.rb; radiusX: root.rb; radiusY: root.rb; direction: PathArc.Counterclockwise }
        PathLine { x: root.xr; y: root.e }
        PathArc { x: root.width; y: 0; radiusX: root.e; radiusY: root.e; direction: PathArc.Clockwise }
    }
}
