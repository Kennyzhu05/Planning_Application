import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property int currentIndex: 0
    signal pageSelected(int index)
    height: 76
    color: "#18181B"

    Rectangle { width: parent.width; height: 1; color: "#27272A" }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        Repeater {
            model: [
                { label: "Dashboard", icon: "dashboard" },
                { label: "Calendar", icon: "calendar" },
                { label: "Long-term goal", icon: "goal" },
                { label: "Menu", icon: "menu" }
            ]

            delegate: Button {
                id: tabButton
                required property var modelData
                required property int index
                readonly property bool selected: root.currentIndex === index
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                padding: 4
                Accessible.name: modelData.label
                Accessible.role: Accessible.PageTab
                Accessible.checkable: true
                Accessible.checked: selected
                onClicked: root.pageSelected(index)

                background: Rectangle {
                    radius: 12
                    color: tabButton.down ? "#312E81" : (tabButton.selected ? "#25223B" : "transparent")
                    border.width: tabButton.activeFocus ? 1 : 0
                    border.color: "#818CF8"
                }
                contentItem: ColumnLayout {
                    spacing: 3
                    NavigationIcon {
                        iconName: tabButton.modelData.icon
                        tint: tabButton.selected ? "#A5B4FC" : "#A1A1AA"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: tabButton.modelData.label
                        color: tabButton.selected ? "#A5B4FC" : "#A1A1AA"
                        font.pixelSize: 11
                        font.bold: tabButton.selected
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
