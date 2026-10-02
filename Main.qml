import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Window {
    id: window
    width: 390
    height: 844
    visible: true
    title: Qt.application.name
    color: "#09090B"

    property int currentPage: 0
    property var currentDate: new Date()

    function refreshDate() {
        currentDate = new Date()
        var midnight = new Date(currentDate.getFullYear(), currentDate.getMonth(), currentDate.getDate() + 1)
        dateTimer.interval = Math.max(1000, midnight.getTime() - currentDate.getTime() + 50)
        dateTimer.restart()
    }

    Component.onCompleted: refreshDate()
    onActiveChanged: if (active) refreshDate()

    Timer {
        id: dateTimer
        repeat: false
        onTriggered: window.refreshDate()
    }

    // Calculate capacity ratio for dynamic progress gauge
    readonly property double capacityRatio: taskManager.targetHours > 0
        ? taskManager.totalPlannedHours / taskManager.targetHours
        : 0.0

    Item {
        id: appShell
        anchors.fill: parent
        visible: !focusPage.visible
        enabled: !taskDetails.visible && !targetModal.visible
        // Blur the entire page, including navigation, behind task details.
        layer.enabled: taskDetails.visible && GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: 0.6
            autoPaddingEnabled: false
        }

        Item {
            id: pageContent
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: bottomNavigation.top
            anchors.margins: 20
            // Leave a separate row for the floating button so it cannot cover tasks.
            anchors.bottomMargin: window.currentPage === 0 ? 88 : 20

            ColumnLayout {
                id: homePage
                objectName: "dashboardContent"
                anchors.fill: parent
                spacing: 20
                visible: window.currentPage === 0

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
                            text: Qt.formatDate(window.currentDate, "dddd, MMM d, yyyy")
                            color: "#A1A1AA"
                            font.pixelSize: 13
                        }
                    }

                    Item { Layout.fillWidth: true }

                }

                // =========================================================
                // 2. CAPACITY PROGRESS CARD
                // =========================================================
                Button {
                    id: focusBudgetButton
                    objectName: "focusBudgetButton"
                    Layout.fillWidth: true
                    implicitHeight: 84
                    padding: 16
                    Accessible.name: "Focus Budget. Edit daily focus target"
                    onClicked: targetModal.openForTarget(taskManager.targetHours)

                    background: Rectangle {
                        color: focusBudgetButton.down ? "#27272A" : "#18181B"
                        radius: 16
                        border.color: focusBudgetButton.activeFocus ? "#818CF8" : "#27272A"
                        border.width: 1
                    }

                    contentItem: ColumnLayout {
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "Focus Budget"
                                color: "#A1A1AA"
                                font.pixelSize: 12
                                font.bold: true
                            }

                            NavigationIcon {
                                iconName: "edit"
                                tint: "#818CF8"
                                Layout.preferredWidth: 14
                                Layout.preferredHeight: 14
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

                Button {
                    id: startFocusButton
                    Layout.fillWidth: true
                    implicitHeight: 52
                    text: "Start Focus"

                    contentItem: Text {
                        text: startFocusButton.text
                        color: "#FFFFFF"
                        font.pixelSize: 16
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        color: startFocusButton.down ? "#3730A3" : "#4338CA"
                        radius: 14
                    }

                    onClicked: focusPage.visible = true
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
                            text: "Tap the + button to build your schedule."
                            color: "#71717A"
                            font.pixelSize: 12
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    ListView {
                        id: listView
                        objectName: "taskList"
                        anchors.fill: parent
                        clip: true
                        spacing: 10
                        model: taskManager

                        delegate: SwipeDelegate {
                            id: delegate
                            required property var model
                            objectName: "taskRow" + model.taskId
                            width: listView.width
                            leftPadding: 16
                            rightPadding: 16
                            implicitHeight: model.subtaskCount > 0 ? 86 : 68
                            onClicked: {
                                if (swipe.position === 0) taskDetails.openForTask(model.taskId)
                            }

                            background: Rectangle {
                                color: "#18181B"
                                radius: 14
                                border.color: "#27272A"
                                border.width: 1
                            }

                            contentItem: RowLayout {
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
                                        objectName: "taskCheckbox" + model.taskId
                                        anchors.fill: parent
                                        onClicked: taskManager.toggleTaskById(model.taskId)
                                    }
                                }

                                // Task Details
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: model.name
                                        textFormat: Text.PlainText
                                        color: model.isCompleted ? "#71717A" : "#FFFFFF"
                                        font.pixelSize: 15
                                        font.bold: true
                                        font.strikeout: model.isCompleted
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: model.effectiveMinutes + " mins • " + model.category
                                        color: "#A1A1AA"
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        visible: model.subtaskCount > 0
                                        text: model.completedSubtaskCount + " of " + model.subtaskCount + " steps completed"
                                        color: "#A5B4FC"
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
                                objectName: "deleteTask" + delegate.model.taskId
                                width: parent.width
                                height: parent.height
                                color: "#EF4444"
                                radius: 14
                                SwipeDelegate.onClicked: taskManager.deleteTaskById(delegate.model.taskId)

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

                                }
                            }
                        }
                    }
                }

            }

            Item {
                anchors.fill: parent
                visible: window.currentPage === 1 || window.currentPage === 2

                Text {
                    text: window.currentPage === 1 ? "Calendar" : "Long-term goal"
                    color: "#FFFFFF"
                    font.pixelSize: 24
                    font.bold: true
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 16

                    NavigationIcon {
                        iconName: window.currentPage === 1 ? "calendar" : "goal"
                        tint: "#818CF8"
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: window.currentPage === 1 ? "Your planning calendar" : "Make room for bigger goals"
                        color: "#FFFFFF"
                        font.pixelSize: 18
                        font.bold: true
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        text: window.currentPage === 1
                            ? "Calendar scheduling is coming soon. Plan your tasks on the Dashboard for now."
                            : "Long-term goal planning is coming soon. You can already break down tasks on the Dashboard."
                        color: "#A1A1AA"
                        font.pixelSize: 13
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 20
                visible: window.currentPage === 3

                Text {
                    text: "Menu"
                    color: "#FFFFFF"
                    font.pixelSize: 24
                    font.bold: true
                }

                Button {
                    id: menuTargetButton
                    Layout.fillWidth: true
                    implicitHeight: 80
                    padding: 16
                    Accessible.name: "Edit daily focus target"
                    onClicked: targetModal.openForTarget(taskManager.targetHours)
                    background: Rectangle {
                        color: menuTargetButton.down ? "#27272A" : "#18181B"
                        radius: 16
                        border.color: menuTargetButton.activeFocus ? "#818CF8" : "#27272A"
                    }
                    contentItem: RowLayout {
                        spacing: 12
                        NavigationIcon { iconName: "goal"; tint: "#818CF8" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "Daily focus target"; color: "#FFFFFF"; font.pixelSize: 15; font.bold: true }
                            Text { text: taskManager.targetHours.toFixed(1) + " hours per day"; color: "#A1A1AA"; font.pixelSize: 12 }
                        }
                        NavigationIcon { iconName: "edit"; tint: "#818CF8" }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        Button {
            id: addTaskButton
            objectName: "addTaskButton"
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.bottom: bottomNavigation.top
            anchors.bottomMargin: 16
            width: 56
            height: 56
            padding: 0
            visible: window.currentPage === 0
            Accessible.name: "Add new task"
            ToolTip.visible: hovered
            ToolTip.text: "Add new task"
            contentItem: Text {
                text: "+"
                color: "#FFFFFF"
                font.pixelSize: 32
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: addTaskButton.down ? "#4F46E5" : "#6366F1"
                radius: width / 2
                border.width: addTaskButton.activeFocus ? 2 : 0
                border.color: "#C7D2FE"
            }
            onClicked: taskModal.open()
        }

        BottomNavigation {
            id: bottomNavigation
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            currentIndex: window.currentPage
            onPageSelected: function(index) { window.currentPage = index }
        }
    }

    // Modal dialog for creating new tasks
    TaskModal {
        id: taskModal
    }

    // Onboarding Overlay for setting daily target hours
    TargetSetupModal {
        id: targetModal
        objectName: "targetModal"
        // Keep it hidden initially; let Component.onCompleted decide
        visible: false

        Component.onCompleted: if (taskManager.targetHours <= 0) openForTarget(0)

        onTargetSelected: function(hours) {
            taskManager.setTargetHours(hours)
            targetModal.visible = false
        }
    }

    FocusPage {
        id: focusPage
        anchors.fill: parent
        visible: false
        onBackRequested: focusPage.visible = false
    }

    TaskDetailsModal {
        id: taskDetails
    }
}
