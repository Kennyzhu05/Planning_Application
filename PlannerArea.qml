import QtQuick
import QtQuick.Controls

TextArea {
    color: "#FFFFFF"
    placeholderTextColor: "#71717A"
    selectByMouse: true
    wrapMode: TextEdit.Wrap
    implicitHeight: Math.max(88, contentHeight + 24)
    padding: 12
    background: Rectangle { color: "#27272A"; radius: 10; border.color: "#3F3F46" }
}
