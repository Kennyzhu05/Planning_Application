import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    id: window
    width: 390
    height: 844
    visible: true
    title: Qt.application.name
    color: "#09090B"

    // Calculate capacity ratio for dynamic progress gauge
    readonly property double capacityRatio: taskManager.targetHours > 0
        ? taskManager.totalPlannedHours / taskManager.targetHours
        : 0.0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // =========================================================
        // 1. HEADER SECTION
        // =========================================================
        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 2
                Text {
                    text: "Today's Schedule"
                    color: "#FFFFFF"
                    font.pixelSize: 24
                    font.bold: true
                }
                Text {
                    text: Qt.formatDate(new Date(), "EEEE, MMM d")
                    color: "#A1A1AA"
                    font.pixelSize: 13
                }
            }

            Item { Layout.fillWidth: true }

            // Target Hours Chip (Clickable to edit daily goal)
            Rectangle {
                implicitWidth: 92
                implicitHeight: 36
                color: targetArea.containsPress ? "#27272A" : "#18181B"
                radius: 18
                border.color: "#27272A"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: taskManager.targetHours.toFixed(1) + "h Goal"
                    color: "#818CF8"
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    id: targetArea
                    anchors.fill: parent
                    onClicked: targetModal.visible = true
                }
            }
        }

        // =========================================================
        // 2. CAPACITY PROGRESS CARD
        // =========================================================
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 84
            color: "#18181B"
            radius: 16
            border.color: "#27272A"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Focus Budget"
                        color: "#A1A1AA"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: taskManager.totalPlannedHours.toFixed(1) + " / " + taskManager.targetHours.toFixed(1) + " hrs"
                        color: window.capacityRatio > 1.0 ? "#F59E0B" : "#FFFFFF"
                        font.pixelSize: 13
                        font.bold: true
                    }
                }

                // Dynamic Progress Bar
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    color: "#27272A"
                    radius: 4

                    Rectangle {
                        width: parent.width * Math.min(window.capacityRatio, 1.0)
                        height: parent.height
                        color: window.capacityRatio > 1.0 ? "#F59E0B" : "#6366F1"
                        radius: 4

                        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
            }
        }

        // =========================================================
        // 3. TASK LIST VIEW & EMPTY STATE
        // =========================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Empty State Graphic when zero tasks exist
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                visible: listView.count === 0

                Text {
                    text: "☕"
                    font.pixelSize: 42
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "No tasks planned yet"
                    color: "#FFFFFF"
                    font.pixelSize: 16
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Tap '+ Add New Task' below to build your schedule."
                    color: "#71717A"
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            ListView {
                id: listView
                anchors.fill: parent
                clip: true
                spacing: 10
                model: taskManager

                delegate: SwipeDelegate {
                    id: delegate
                    width: listView.width
                    implicitHeight: 68

                    background: Rectangle {
                        color: "#18181B"
                        radius: 14
                        border.color: "#27272A"
                        border.width: 1
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 14

                        // Checkbox Toggle
                        Rectangle {
                            implicitWidth: 24
                            implicitHeight: 24
                            radius: 7
                            color: model.isCompleted ? "#10B981" : "transparent"
                            border.color: model.isCompleted ? "#10B981" : "#52525B"
                            border.width: 2

                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                color: "#FFFFFF"
                                font.pixelSize: 14
                                font.bold: true
                                visible: model.isCompleted
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: taskManager.toggleTask(model.index)
                            }
                        }

                        // Task Details
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: model.name
                                color: model.isCompleted ? "#71717A" : "#FFFFFF"
                                font.pixelSize: 15
                                font.bold: true
                                font.strikeout: model.isCompleted
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: model.minutes + " mins • " + model.category
                                color: "#A1A1AA"
                                font.pixelSize: 12
                            }
                        }

                        // Category Tag Indicator
                        Rectangle {
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: 5
                            color: model.category === "Work" ? "#6366F1" :
                                   (model.category === "Health" ? "#10B981" : "#F59E0B")
                        }
                    }

                    // Swipe-to-Delete Action Layer
                    swipe.right: Rectangle {
                        width: parent.width
                        height: parent.height
                        color: "#EF4444"
                        radius: 14

                        Item {
                            anchors.right: parent.right
                            anchors.rightMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            width: 60
                            height: parent.height

                            Text {
                                anchors.centerIn: parent
                                text: "Delete"
                                color: "#FFFFFF"
                                font.bold: true
                                font.pixelSize: 13
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: taskManager.deleteTask(model.index)
                            }
                        }
                    }
                }
            }
        }

        // =========================================================
        // 4. FLOATING ACTION TRIGGER
        // =========================================================
        Button {
            Layout.fillWidth: true
            implicitHeight: 52
            text: "+ Add New Task"

            contentItem: Text {
                text: parent.text
                color: "#FFFFFF"
                font.pixelSize: 16
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                color: parent.down ? "#4F46E5" : "#6366F1"
                radius: 14
            }

            onClicked: taskModal.open()
        }
    }

    // Modal dialog for creating new tasks
    TaskModal {
        id: taskModal
    }

    // Onboarding Overlay for setting daily target hours
    TargetSetupModal {
        id: targetModal
        // Keep it hidden initially; let Component.onCompleted decide
        visible: false

        Component.onCompleted: {
            // If the database has a default/unset target, or on first run, show the setup overlay
            // If you want it to pop up EVERY time the application starts up:
            targetModal.visible = true;
        }

        onTargetSelected: function(hours) {
            taskManager.setTargetHours(hours)
            targetModal.visible = false
        }
    }
}