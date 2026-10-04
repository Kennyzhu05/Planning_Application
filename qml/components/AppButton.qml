import QtQuick
import QtQuick.Controls

Button {
    id: root
    property color fillColor: "#6366F1"
    hoverEnabled: true
    implicitHeight: 44
    padding: 10
    contentItem: Text {
        text: root.text
        color: root.enabled ? "#FFFFFF" : "#71717A"
        font.pixelSize: 13
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }
    background: Rectangle {
        radius: 10
        color: root.enabled ? (root.down ? Qt.darker(root.fillColor, 1.15) : root.hovered ? Qt.lighter(root.fillColor, 1.12) : root.fillColor) : "#27272A"
        border.width: root.activeFocus ? 1 : 0
        border.color: "#C7D2FE"
        Behavior on color { ColorAnimation { duration: 140 } }
    }
}
