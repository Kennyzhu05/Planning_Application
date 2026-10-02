import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: root
    anchors.fill: parent
    z: 200
    focus: visible
    property double selectedHours: 8.0
    readonly property bool editing: taskManager.targetHours > 0

    signal targetSelected(double hours)

    function openForTarget(hours) {
        selectedHours = hours > 0 ? Math.max(1, Math.min(12, hours)) : 8.0
        visible = true
        forceActiveFocus()
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible && root.editing
        context: Qt.WindowShortcut
        onActivated: root.visible = false
    }

    // Dark semi-transparent background overlay
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.85
    }

    MouseArea {
        anchors.fill: parent
        onWheel: function(wheel) { wheel.accepted = true }
    }

    // Modal Card Container
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.88, 400)
        implicitHeight: layout.implicitHeight + 48
        color: "#18181B"
        radius: 24
        border.color: "#27272A"
        border.width: 1

        Button {
            id: closeButton
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            width: 32
            height: 32
            visible: root.editing
            z: 1
            Accessible.name: "Close focus target settings"
            onClicked: root.visible = false
            background: Rectangle { color: closeButton.down ? "#3F3F46" : "#27272A"; radius: 16 }
            contentItem: Text {
                text: "×"
                color: "#FFFFFF"
                font.pixelSize: 20
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: 28
            spacing: 20

            // Header Icon & Title
            ColumnLayout {
                spacing: 6
                Layout.alignment: Qt.AlignHCenter

                Text {
                    text: "🎯"
                    font.pixelSize: 36
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Set Daily Focus Target"
                    color: "#FFFFFF"
                    font.pixelSize: 20
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "How many hours of focused work are you aiming for today?"
                    color: "#A1A1AA"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
            }

            // Target Hours Big Display
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                Text {
                    text: root.selectedHours.toFixed(1)
                    color: "#6366F1"
                    font.pixelSize: 48
                    font.bold: true
                }

                Text {
                    text: "hrs / day"
                    color: "#71717A"
                    font.pixelSize: 16
                    font.bold: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 10
                }
            }

            // Quick Preset Chips
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { label: "4h Light", val: 4.0 },
                        { label: "6h Moderate", val: 6.0 },
                        { label: "8h Standard", val: 8.0 }
                    ]

                    delegate: Button {
                        Layout.fillWidth: true
                        implicitHeight: 40

                        contentItem: Text {
                            text: modelData.label
                            color: root.selectedHours === modelData.val ? "#FFFFFF" : "#A1A1AA"
                            font.pixelSize: 12
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            color: root.selectedHours === modelData.val ? "#6366F1" : "#09090B"
                            radius: 10
                            border.color: root.selectedHours === modelData.val ? "#6366F1" : "#27272A"
                        }

                        onClicked: root.selectedHours = modelData.val
                    }
                }
            }

            // Custom Slider Adjustment
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Slider {
                    id: hourSlider
                    Layout.fillWidth: true
                    from: 1.0
                    to: 12.0
                    stepSize: 0.5
                    value: root.selectedHours

                    onMoved: root.selectedHours = value
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "1 hr"; color: "#52525B"; font.pixelSize: 11; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Text { text: "12 hrs"; color: "#52525B"; font.pixelSize: 11; font.bold: true }
                }
            }

            // Confirm Button
            Button {
                Layout.fillWidth: true
                implicitHeight: 52

                contentItem: Text {
                    text: root.editing ? "Save Focus Target" : "Start Planning Day →"
                    color: "#FFFFFF"
                    font.pixelSize: 15
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    color: "#6366F1"
                    radius: 14
                }

                onClicked: root.targetSelected(root.selectedHours)
            }
        }
    }
}
