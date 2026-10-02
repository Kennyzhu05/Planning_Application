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

    function formatFocusTime(totalSeconds) {
        const hours = Math.floor(totalSeconds / 3600)
        const minutes = Math.floor((totalSeconds % 3600) / 60)
        const seconds = totalSeconds % 60
        const shortTime = ("0" + minutes).slice(-2) + ":"
                + ("0" + seconds).slice(-2)
        return hours > 0 ? hours + ":" + shortTime : shortTime
    }

    function refreshDate() {
        currentDate = new Date()
        taskManager.refreshToday()
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
        enabled: !taskDetails.visible && !goalDetails.visible && !targetModal.visible
        // Blur the entire page, including navigation, behind task details.
        layer.enabled: (taskDetails.visible || goalDetails.visible) && GraphicsInfo.api !== GraphicsInfo.Software
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
            anchors.bottomMargin: window.currentPage === 0 || window.currentPage === 2 ? 88 : 20

            ColumnLayout {
                id: homePage
                objectName: "dashboardContent"
                anchors.fill: parent
                spacing: 20
                visible: window.currentPage === 0

                // =========================================================
                // 1. HEADER SECTION
                // =========================================================
                Item {
                    id: dashboardHeader
                    objectName: "dashboardHeader"
                    Layout.fillWidth: true
                    readonly property bool compact: width < headerLabels.implicitWidth + focusControl.width + 12
                    implicitHeight: headerLabels.implicitHeight + (compact ? focusControl.height + 8 : 0)

                    ColumnLayout {
                        id: headerLabels
                        anchors.left: parent.left
                        anchors.top: parent.top
                        spacing: 2
                        Text {
                            objectName: "dashboardTitle"
                            text: "Today's Schedule"
                            color: "#FFFFFF"
                            font.pixelSize: 24
                            font.bold: true
                        }
                        Text {
                            objectName: "dashboardDate"
                            text: Qt.formatDate(window.currentDate, "dddd, MMM d, yyyy")
                            color: "#A1A1AA"
                            font.pixelSize: 13
                        }
                    }

                    Button {
                        id: focusControl
                        objectName: "focusControl"
                        anchors.right: parent.right
                        y: dashboardHeader.compact ? headerLabels.height + 8 : 0
                        width: 106
                        height: 44
                        padding: 10
                        text: focusController.running
                              ? window.formatFocusTime(focusController.timed
                                    ? focusController.remainingSeconds
                                    : focusController.elapsedSeconds)
                              : "Start Focus"
                        Accessible.name: focusController.running
                                         ? "End focus session. " + (focusController.timed ? "Time remaining " : "Elapsed time ") + text
                                         : "Start focus session"
                        ToolTip.visible: hovered
                        ToolTip.text: focusController.running
                                      ? "End focus session"
                                      : "Choose a focus mode"
                        contentItem: RowLayout {
                            spacing: 6
                            Text {
                                objectName: "focusControlTime"
                                text: focusControl.text
                                color: "#FFFFFF"
                                font.pixelSize: 12
                                font.bold: true
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            Rectangle {
                                objectName: "focusStopSquare"
                                visible: focusController.running
                                implicitWidth: 10
                                implicitHeight: 10
                                color: "#FFFFFF"
                                radius: 1
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                        background: Rectangle {
                            objectName: "focusControlBackground"
                            radius: 12
                            color: focusController.running
                                   ? (focusControl.down ? "#9A3412" : "#C2410C")
                                   : (focusControl.down ? "#3730A3" : "#4338CA")
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                        onClicked: {
                            if (focusController.running)
                                focusController.stop()
                            else
                                focusSetupDialog.open()
                        }
                    }
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
                        model: taskManager.todayTasks

                        delegate: SwipeDelegate {
                            id: delegate
                            required property var model
                            objectName: "taskRow" + model.taskId
                            width: listView.width
                            leftPadding: 16
                            rightPadding: 16
                            implicitHeight: (model.subtaskCount > 0 ? 86 : 68) + (model.goalId > 0 ? 18 : 0)
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
                                        Layout.fillWidth: true
                                        visible: model.goalId > 0
                                        text: "Goal: " + (model.goalName || "")
                                        textFormat: Text.PlainText
                                        color: "#A5B4FC"
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
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

            CalendarPage {
                id: calendarPage
                anchors.fill: parent
                visible: window.currentPage === 1
                onTaskRequested: function(taskId) { taskDetails.openForTask(taskId) }
                onGoalRequested: function(goalId) { goalDetails.openForGoal(goalId) }
                onAddTaskRequested: function(date) { taskModal.openForDate(date) }
            }

            GoalsPage {
                anchors.fill: parent
                visible: window.currentPage === 2
                onGoalRequested: function(goalId) { goalDetails.openForGoal(goalId) }
            }

            ScrollView {
                id: menuScroll
                anchors.fill: parent
                visible: window.currentPage === 3
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: menuScroll.availableWidth
                    spacing: 20

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
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: accountContent.implicitHeight + 32
                        radius: 16
                        color: "#18181B"
                        border.color: "#27272A"
                        ColumnLayout {
                            id: accountContent
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10
                            Text { text: "AI account"; color: "#FFFFFF"; font.pixelSize: 15; font.bold: true }
                            Text {
                                Layout.fillWidth: true
                                text: authService.signedIn ? authService.email : "Sign in to use AI breakdown."
                                textFormat: Text.PlainText
                                color: "#A1A1AA"
                                wrapMode: Text.WrapAnywhere
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Your tasks and goals stay on this device."
                                color: "#71717A"
                                wrapMode: Text.WordWrap
                                font.pixelSize: 12
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: authService.signedIn
                                text: authService.storageMessage
                                textFormat: Text.PlainText
                                color: "#71717A"
                                wrapMode: Text.WordWrap
                                font.pixelSize: 12
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: authService.errorMessage.length > 0
                                text: authService.errorMessage
                                textFormat: Text.PlainText
                                color: "#FCA5A5"
                                wrapMode: Text.WordWrap
                                font.pixelSize: 12
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: authService.message.length > 0
                                text: authService.message
                                textFormat: Text.PlainText
                                color: "#A7F3D0"
                                wrapMode: Text.WordWrap
                                font.pixelSize: 12
                            }
                            AppButton {
                                Layout.fillWidth: true
                                text: authService.signedIn ? "Sign out" : authService.busy ? "Connecting…" : "Sign in / Create account"
                                enabled: !authService.busy
                                onClicked: {
                                    if (authService.signedIn) authService.signOut()
                                    else authModal.openForSignIn()
                                }
                            }
                        }
                    }
                }
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
            visible: window.currentPage === 0 || window.currentPage === 2
            Accessible.name: window.currentPage === 2 ? "Add long-term goal" : "Add new task"
            ToolTip.visible: hovered
            ToolTip.text: window.currentPage === 2 ? "Add long-term goal" : "Add new task"
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
            onClicked: {
                if (window.currentPage === 2) goalForm.openForGoal(0)
                else taskModal.openForDate(taskManager.todayDate)
            }
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

    FocusSetupDialog {
        id: focusSetupDialog
    }

    TaskDetailsModal {
        id: taskDetails
        editPopupVisible: taskEdit.visible
        onEditRequested: function(taskId) { taskEdit.openForTask(taskId) }
    }

    TaskEditModal { id: taskEdit }

    AuthModal { id: authModal }
    Connections {
        target: aiService
        function onAuthenticationRequired() { authModal.openForSignIn() }
    }

    GoalDetailsModal {
        id: goalDetails
        editPopupVisible: goalForm.visible
        onEditRequested: function(goalId) { goalForm.openForGoal(goalId) }
        onTaskRequested: function(taskId) { taskDetails.openForTask(taskId) }
    }

    GoalForm {
        id: goalForm
        onGoalSaved: function(goalId) { if (!goalDetails.visible) goalDetails.openForGoal(goalId) }
    }
}
