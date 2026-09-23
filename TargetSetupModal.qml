import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    anchors.fill: parent
    color: "#000000"
    opacity: 0.95
    z: 999

    property double selectedHours: 8.0

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.88, 360)
        spacing: 20

        Text {
            text: "Set Daily Capacity Target"
            color: "#FFFFFF"
            font.pixelSize: 20
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: root.selectedHours.toFixed(1) + " Hours"
            color: "#6366F1"
            font.pixelSize: 32
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
        }

        Button {
            Layout.fillWidth: true
            text: "Confirm Target"
            onClicked: {
                taskManager.targetHours = root.selectedHours
                root.visible = false
            }
        }
    }
}