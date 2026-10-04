import QtQuick
import QtQuick.Controls

TextField {
    id: root
    color: "#FFFFFF"
    placeholderTextColor: "#71717A"
    selectByMouse: true
    implicitHeight: 44
    padding: 12
    background: Rectangle {
        color: "#191922"; radius: 10
        border.color: root.activeFocus ? "#818CF8" : "#3F3F4C"
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }
}
