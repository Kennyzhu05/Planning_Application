pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: root
    property string value: "Work"
    signal selected(string category)
    spacing: 6
    Repeater {
        model: [
            { name: "Work", tint: "#A5B4FC" },
            { name: "Health", tint: "#6EE7B7" },
            { name: "Personal", tint: "#FCD34D" }
        ]
        delegate: Button {
            id: option
            required property var modelData
            readonly property color accent: modelData.tint
            readonly property bool chosen: root.value === modelData.name
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 44
            padding: 8
            hoverEnabled: true
            Accessible.name: modelData.name + " category"
            Accessible.checkable: true
            Accessible.checked: chosen
            onClicked: root.selected(modelData.name)
            contentItem: RowLayout {
                spacing: 6
                Rectangle { implicitWidth: 6; implicitHeight: 6; radius: 3; color: option.accent }
                Text {
                    Layout.fillWidth: true
                    text: option.modelData.name
                    color: option.chosen ? option.accent : "#E4E4EE"
                    font.pixelSize: root.width < 290 ? 11 : 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.Wrap
                }
            }
            background: Rectangle {
                radius: 11
                color: option.down ? "#343044" : option.chosen
                       ? Qt.rgba(option.accent.r, option.accent.g, option.accent.b, 0.14)
                       : option.hovered ? "#2B2B3A" : "#22222F"
                border.width: option.chosen || option.activeFocus ? 2 : 1
                border.color: option.chosen ? option.accent : option.activeFocus ? "#C7D2FE" : "#454553"
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }
    }
}
