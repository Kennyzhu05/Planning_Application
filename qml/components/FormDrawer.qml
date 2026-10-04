import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    default property alias fields: fieldColumn.data
    property string heading: ""
    property string subtitle: ""
    property string saveText: "Save changes"
    property string errorMessage: ""
    property bool saveEnabled: true
    property real maximumCardWidth: 520
    property real maximumCardHeight: 760
    signal submitRequested()

    // Match the details cards: centered, with space on every side.
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: parent ? Math.max(1, Math.min(parent.width - 32, maximumCardWidth)) : 358
    height: parent ? Math.max(1, Math.min(parent.height - 32, maximumCardHeight)) : 700
    padding: 18
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: formScroll.contentItem.contentY = 0
    Overlay.modal: Rectangle { color: "#99000000" }
    background: Rectangle { color: "#18181B"; radius: 22; border.color: "#3F3F46" }

    contentItem: ColumnLayout {
        spacing: 14
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                implicitWidth: 38; implicitHeight: 38; radius: 12; color: "#302A49"
                NavigationIcon { anchors.centerIn: parent; iconName: "edit"; tint: "#B9AEFF"; width: 20; height: 20 }
            }
            Text {
                Layout.fillWidth: true
                text: root.heading
                color: "#FFFFFF"
                font.pixelSize: 21
                font.bold: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
            AppButton { text: "Close"; fillColor: "#30303D"; onClicked: root.close() }
        }
        Text {
            Layout.fillWidth: true
            visible: root.subtitle.length > 0
            text: root.subtitle
            color: "#A6A6BB"
            font.pixelSize: 12
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#363643" }
        ScrollView {
            id: formScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            Layout.preferredHeight: 0
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                id: fieldColumn
                width: formScroll.availableWidth
                spacing: 14
            }
        }
        Text {
            Layout.fillWidth: true
            visible: root.errorMessage.length > 0
            text: root.errorMessage
            color: "#FCA5A5"
            font.pixelSize: 12
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            AppButton { text: "Cancel"; fillColor: "#30303D"; implicitHeight: 46; onClicked: root.close() }
            AppButton {
                Layout.fillWidth: true
                text: root.saveText
                fillColor: "#059669"
                implicitHeight: 46
                enabled: root.saveEnabled
                onClicked: {
                    fieldColumn.forceActiveFocus()
                    root.submitRequested()
                }
            }
        }
    }
}
