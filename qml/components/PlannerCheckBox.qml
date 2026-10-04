import QtQuick
import QtQuick.Controls

CheckBox {
    id: root
    spacing: 10
    hoverEnabled: true
    padding: 4
    implicitHeight: 40
    indicator: Rectangle {
        implicitWidth: 24
        implicitHeight: 24
        x: root.leftPadding
        y: (root.height - height) / 2
        radius: 7
        color: root.checked ? "#10B981" : root.hovered ? "#272A38" : "#18181B"
        border.width: root.checked ? 0 : 2
        border.color: root.activeFocus ? "#A5B4FC" : "#52525B"
        opacity: root.enabled ? 1 : 0.5
        Behavior on color { ColorAnimation { duration: 140 } }
        Text {
            anchors.centerIn: parent
            text: "✓"
            color: "#FFFFFF"
            font.pixelSize: 16
            font.bold: true
            visible: root.checked
        }
    }
    contentItem: Text {
        text: root.text
        textFormat: Text.PlainText
        color: root.enabled ? "#D4D4D8" : "#71717A"
        font.pixelSize: 13
        leftPadding: root.indicator.width + root.spacing
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
    }
}
