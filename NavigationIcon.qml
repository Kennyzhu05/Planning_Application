import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property string iconName: "dashboard"
    property color tint: "#A1A1AA"
    implicitWidth: 24
    implicitHeight: 24

    readonly property string iconPath: {
        switch (iconName) {
        case "calendar": return "M4 5H20V21H4Z M4 10H20 M8 3V7 M16 3V7 M8 14H9 M15 14H16 M8 17H9 M15 17H16"
        case "goal": return "M21 12A9 9 0 1 1 3 12A9 9 0 1 1 21 12 M17 12A5 5 0 1 1 7 12A5 5 0 1 1 17 12 M13 12A1 1 0 1 1 11 12A1 1 0 1 1 13 12"
        case "menu": return "M4 6H20 M4 12H20 M4 18H20"
        case "edit": return "M4 16L15 5L19 9L8 20H4Z M13 7L17 11 M15 5L17 3L21 7L19 9"
        default: return "M3 3H10V10H3Z M14 3H21V10H14Z M3 14H10V21H3Z M14 14H21V21H14Z"
        }
    }

    Item {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: Math.min(root.width, root.height) / 24
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: root.tint
                strokeWidth: 1.8
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: root.iconPath }
            }
        }
    }
}
