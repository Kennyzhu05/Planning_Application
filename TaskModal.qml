import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Drawer {
    id: drawer
    width: parent ? parent.width : 390
    height: parent ? parent.height * 0.75 : 600
    edge: Qt.BottomEdge

    // Direct, strongly typed state
    property int selectedMinutes: 30
    property string selectedCategory: "Work"

    background: Rectangle {
        color: "#18181B"
        radius: 24
        border.color: "#27272A"
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        // Grab Handle
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 40
            implicitHeight: 4
            color: "#3F3F46"
            radius: 2
        }

        Text {
            text: "Create New Task"
            color: "#FFFFFF"
            font.pixelSize: 20
            font.bold: true
        }

        // 1. Task Name Input
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "TASK TITLE"
                color: "#A1A1AA"
                font.pixelSize: 11
                font.bold: true
            }

            TextField {
                id: taskNameInput
                Layout.fillWidth: true
                implicitHeight: 48
                placeholderText: "e.g., Prepare quarterly presentation"
                placeholderTextColor: "#71717A"
                color: "#FFFFFF"
                font.pixelSize: 15
                leftPadding: 14
                rightPadding: 14

                background: Rectangle {
                    color: "#27272A"
                    radius: 12
                    border.color: taskNameInput.activeFocus ? "#6366F1" : "#3F3F46"
                    border.width: 1
                }
            }
        }

        // 2. Duration Quick-Select Chips
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "ESTIMATED DURATION"
                color: "#A1A1AA"
                font.pixelSize: 11
                font.bold: true
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 8
                columnSpacing: 8

                Repeater {
                    model: [
                        { label: "15m", mins: 15 },
                        { label: "30m", mins: 30 },
                        { label: "45m", mins: 45 },
                        { label: "1h", mins: 60 },
                        { label: "1.5h", mins: 90 },
                        { label: "2h", mins: 120 }
                    ]

                    delegate: Button {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        text: modelData.label

                        contentItem: Text {
                            text: parent.text
                            color: drawer.selectedMinutes === modelData.mins ? "#FFFFFF" : "#A1A1AA"
                            font.bold: drawer.selectedMinutes === modelData.mins
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            color: drawer.selectedMinutes === modelData.mins ? "#6366F1" : "#27272A"
                            radius: 10
                            border.color: drawer.selectedMinutes === modelData.mins ? "#818CF8" : "#3F3F46"
                            border.width: 1
                        }

                        onClicked: {
                            drawer.selectedMinutes = modelData.mins
                        }
                    }
                }
            }
        }

        // 3. Category Chips
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "CATEGORY"
                color: "#A1A1AA"
                font.pixelSize: 11
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { name: "Work", color: "#6366F1" },
                        { name: "Health", color: "#10B981" },
                        { name: "Personal", color: "#F59E0B" }
                    ]

                    delegate: Button {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        text: modelData.name

                        contentItem: Text {
                            text: parent.text
                            color: drawer.selectedCategory === modelData.name ? "#FFFFFF" : "#A1A1AA"
                            font.bold: drawer.selectedCategory === modelData.name
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            color: drawer.selectedCategory === modelData.name ? modelData.color : "#27272A"
                            radius: 10
                            border.color: drawer.selectedCategory === modelData.name ? modelData.color : "#3F3F46"
                            border.width: 1
                        }

                        onClicked: {
                            drawer.selectedCategory = modelData.name
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // 4. Save Task Button
        Button {
            id: saveButton
            Layout.fillWidth: true
            implicitHeight: 52
            text: "Save Task"

            contentItem: Text {
                text: parent.text
                color: "#FFFFFF"
                font.pixelSize: 16
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                color: saveButton.down ? "#059669" : "#10B981"
                radius: 14
            }

            onClicked: {
                var cleanTitle = taskNameInput.text.trim()
                if (cleanTitle.length > 0) {
                    // SAFE INVOCATION: Strictly cast types to match C++ signature
                    taskManager.addTask(
                        String(cleanTitle),
                        Number(drawer.selectedMinutes),
                        String(drawer.selectedCategory)
                    )

                    // Reset input state
                    taskNameInput.text = ""
                    drawer.selectedMinutes = 30
                    drawer.selectedCategory = "Work"
                    drawer.close()
                }
            }
        }
    }
}