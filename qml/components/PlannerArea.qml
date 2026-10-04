import QtQuick
import QtQuick.Controls

TextArea {
    id: root
    color: "#FFFFFF"
    placeholderTextColor: "#71717A"
    selectByMouse: true
    wrapMode: TextEdit.Wrap
    implicitHeight: Math.max(88, contentHeight + 24)
    padding: 12
    background: Rectangle {
        color: "#191922"; radius: 10
        border.color: root.activeFocus ? "#818CF8" : "#3F3F4C"
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }
}
