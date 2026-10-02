import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#09090B"

    signal backRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Button {
                id: backButton
                implicitWidth: 44
                implicitHeight: 44
                text: "Back"

                contentItem: Text {
                    text: backButton.text
                    color: "#FFFFFF"
                    font.pixelSize: 14
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    color: backButton.down ? "#27272A" : "#18181B"
                    radius: 12
                    border.color: "#3F3F46"
                }

                onClicked: root.backRequested()
            }

            Text {
                text: "Focus Mode"
                color: "#FFFFFF"
                font.pixelSize: 24
                font.bold: true
            }

            Item { Layout.fillWidth: true }
        }

        Text {
            Layout.fillWidth: true
            text: "Choose how long you'd like to focus."
            color: "#A1A1AA"
            font.pixelSize: 14
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 116
            color: "#18181B"
            radius: 16
            border.color: "#3F3F46"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Text {
                    text: "Custom Duration"
                    color: "#FFFFFF"
                    font.pixelSize: 18
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "Set a time for your focus session."
                    color: "#A1A1AA"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 116
            color: "#18181B"
            radius: 16
            border.color: "#3F3F46"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Text {
                    text: "Open-ended"
                    color: "#FFFFFF"
                    font.pixelSize: 18
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "Focus until you choose to stop."
                    color: "#A1A1AA"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
