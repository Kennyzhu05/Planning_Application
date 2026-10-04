import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#09090B"

    signal backRequested()

    property bool timedSelected: true
    property string startError: ""

    function formatTime(totalSeconds) {
        const hours = Math.floor(totalSeconds / 3600)
        const minutes = Math.floor((totalSeconds % 3600) / 60)
        const seconds = totalSeconds % 60

        return hours + ":" + ("0" + minutes).slice(-2)
                + ":" + ("0" + seconds).slice(-2)
    }

    ScrollView {
        id: pageScroll
        anchors.fill: parent
        anchors.margins: 20
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: pageScroll.availableWidth
            spacing: 20

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Button {
                    id: backButton
                    implicitWidth: 64
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

                Item {
                    Layout.fillWidth: true
                }
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
                border.color: root.timedSelected ? "#818CF8" : "#3F3F46"

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

                MouseArea {
                    anchors.fill: parent
                    enabled: !focusController.running

                    onClicked: {
                        root.timedSelected = true
                        root.startError = ""
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 116
                color: "#18181B"
                radius: 16
                border.color: !root.timedSelected ? "#818CF8" : "#3F3F46"

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

                MouseArea {
                    anchors.fill: parent
                    enabled: !focusController.running

                    onClicked: {
                        root.timedSelected = false
                        root.startError = ""
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.timedSelected
                    enabled: !focusController.running
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Hours"
                            color: "#A1A1AA"
                        }

                        SpinBox {
                            id: hoursInput
                            Layout.fillWidth: true
                            from: 0
                            to: 24
                            value: 0
                            editable: true
                            palette.base: "#18181B"
                            palette.text: "#FFFFFF"
                            palette.button: "#27272A"
                            palette.buttonText: "#FFFFFF"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Minutes"
                            color: "#A1A1AA"
                        }

                        SpinBox {
                            id: minutesInput
                            Layout.fillWidth: true
                            from: 0
                            to: hoursInput.value === 24 ? 0 : 59
                            value: 25
                            editable: true
                            palette.base: "#18181B"
                            palette.text: "#FFFFFF"
                            palette.button: "#27272A"
                            palette.buttonText: "#FFFFFF"
                        }
                    }
                }

                Button {
                    id: sessionButton
                    Layout.fillWidth: true
                    implicitHeight: 52
                    text: focusController.running
                          ? "Stop Focus" : "Start Focus"

                    contentItem: Text {
                        text: sessionButton.text
                        color: "#FFFFFF"
                        font.pixelSize: 16
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: 12
                        color: focusController.running
                               ? "#991B1B" : "#4338CA"
                    }

                    onClicked: {
                        sessionButton.forceActiveFocus()
                        root.startError = ""

                        if (focusController.running) {
                            focusController.stop()
                            return
                        }

                        const started = root.timedSelected
                                ? focusController.startTimed(
                                      hoursInput.value, minutesInput.value)
                                : focusController.startOpenEnded()

                        if (!started) {
                            root.startError =
                                    "Unable to start. Choose a duration between 1 minute and 24 hours."
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.startError.length > 0
                    text: root.startError
                    color: "#F87171"
                    wrapMode: Text.WordWrap
                }

                Text {
                    text: "Status: " + focusController.status
                    color: "#A1A1AA"
                }

                Text {
                    visible: focusController.status !== "Idle"
                    text: focusController.running && focusController.timed
                          ? "Time remaining" : "Elapsed focus time"
                    color: "#A1A1AA"
                }

                Text {
                    visible: focusController.status !== "Idle"
                    text: root.formatTime(
                              focusController.running && focusController.timed
                              ? focusController.remainingSeconds
                              : focusController.elapsedSeconds)
                    color: "#FFFFFF"
                    font.pixelSize: 28
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    visible: focusController.status !== "Idle"
                    text: "Counted phone use: "
                          + root.formatTime(focusController.phoneUseSeconds)
                    color: "#A1A1AA"
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}