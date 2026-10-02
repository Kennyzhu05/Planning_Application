import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    objectName: "focusSetupDialog"
    parent: Overlay.overlay
    width: Math.min(parent.width - 32, 360)
    height: Math.min(implicitHeight, parent.height - 32)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    padding: 20
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property bool editingDuration: false
    property string startError: ""

    onOpened: {
        editingDuration = false
        startError = ""
        hoursInput.currentIndex = 0
        minutesInput.currentIndex = 25
    }

    background: Rectangle {
        color: "#18181B"
        radius: 20
        border.color: "#3F3F46"
    }

    Overlay.modal: Rectangle { color: "#99000000" }

    component ModeButton: Button {
        id: control
        Layout.fillWidth: true
        implicitHeight: 48
        contentItem: Text {
            text: control.text
            color: control.enabled ? "#FFFFFF" : "#71717A"
            font.pixelSize: 14
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: control.down ? "#3F3F46" : "#27272A"
            radius: 12
            border.color: control.activeFocus ? "#818CF8" : "#3F3F46"
        }
    }

    component DurationWheel: Tumbler {
        id: wheel
        Layout.fillWidth: true
        implicitWidth: 120
        implicitHeight: 180
        visibleItemCount: 5
        wrap: false
        flickDeceleration: 2500
        onCurrentIndexChanged: root.startError = ""
        background: Rectangle {
            color: "#27272A"
            radius: 12
            border.color: wheel.activeFocus ? "#818CF8" : "#3F3F46"
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 12
                height: wheel.availableHeight / wheel.visibleItemCount
                color: "#4338CA"
                opacity: 0.25
                radius: 8
            }
        }
        delegate: Text {
            required property int index
            required property var modelData
            readonly property real distance: Math.abs(Tumbler.displacement)
            text: ("0" + modelData).slice(-2)
            color: distance < 0.5 ? "#FFFFFF" : "#A1A1AA"
            opacity: Math.max(0.2, 1 - distance / 3)
            font.pixelSize: 24
            font.bold: distance < 0.5
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    contentItem: ScrollView {
        id: scroll
        implicitHeight: form.implicitHeight
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            id: form
            width: scroll.availableWidth
            spacing: 16

            Text {
                text: root.editingDuration ? "Custom Duration" : "Focus Mode"
                color: "#FFFFFF"
                font.pixelSize: 22
                font.bold: true
                Layout.fillWidth: true
            }
            Text {
                text: root.editingDuration
                      ? "Choose a duration from 1 minute to 24 hours."
                      : "Choose how you'd like to focus."
                color: "#A1A1AA"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            ModeButton {
                objectName: "focusOpenEndedOption"
                visible: !root.editingDuration
                text: "Open-ended"
                Accessible.name: "Start open-ended focus"
                onClicked: {
                    if (focusController.startOpenEnded())
                        root.close()
                    else
                        root.startError = "Focus could not start. Monitoring is not available on this device yet."
                }
            }
            ModeButton {
                objectName: "focusTimedOption"
                visible: !root.editingDuration
                text: "Custom Duration"
                onClicked: {
                    root.editingDuration = true
                    root.startError = ""
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.editingDuration
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    Text { text: "Hours"; color: "#A1A1AA" }
                    DurationWheel {
                        id: hoursInput
                        objectName: "focusHoursInput"
                        model: 25
                        currentIndex: 0
                        Accessible.name: "Focus duration hours"
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Text { text: "Minutes"; color: "#A1A1AA" }
                    DurationWheel {
                        id: minutesInput
                        objectName: "focusMinutesInput"
                        model: hoursInput.currentIndex === 24 ? 1 : 60
                        currentIndex: 25
                        enabled: hoursInput.currentIndex !== 24
                        Accessible.name: "Focus duration minutes"
                    }
                }
            }

            Text {
                objectName: "focusStartError"
                Layout.fillWidth: true
                visible: root.startError.length > 0
                text: root.startError
                color: "#FCA5A5"
                wrapMode: Text.WordWrap
                font.pixelSize: 13
            }

            ModeButton {
                id: startButton
                objectName: "focusTimedStart"
                visible: root.editingDuration
                text: "Start"
                enabled: !hoursInput.moving && !minutesInput.moving
                         && hoursInput.currentIndex >= 0 && minutesInput.currentIndex >= 0
                background: Rectangle {
                    color: startButton.down ? "#3730A3" : "#4338CA"
                    radius: 12
                }
                onClicked: {
                    root.startError = ""
                    if (hoursInput.currentIndex * 60 + minutesInput.currentIndex < 1) {
                        root.startError = "Choose at least 1 minute."
                        return
                    }
                    if (focusController.startTimed(hoursInput.currentIndex, minutesInput.currentIndex))
                        root.close()
                    else
                        root.startError = "Focus could not start. Check the duration and device support."
                }
            }

            ModeButton {
                objectName: "focusChooseMode"
                visible: root.editingDuration
                text: "Back"
                onClicked: {
                    root.editingDuration = false
                    root.startError = ""
                }
            }
        }
    }
}
