import QtQuick

Rectangle {
    id: root
    property string text: ""
    property color tint: "#A5B4FC"
    implicitWidth: label.implicitWidth + 18
    implicitHeight: 24
    radius: 8
    color: Qt.rgba(tint.r, tint.g, tint.b, 0.12)
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        textFormat: Text.PlainText
        color: root.tint
        font.pixelSize: 11
        font.bold: true
    }
}
