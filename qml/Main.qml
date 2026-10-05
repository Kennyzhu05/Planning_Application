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

    PageInsets {
        id: pageInsets
        anchors.fill: parent
    }

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
    onActiveChanged: if (active) {
        refreshDate()
        focusController.refresh()
    }

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
        // Shared by Dashboard, Calendar, Long-term goal, Menu, and focus banners.
        anchors.topMargin: pageInsets.topInset
                           + (Qt.platform.os === "android" || Qt.platform.os === "ios" ? 8 : 0)
        enabled: !taskDetails.visible && !goalDetails.visible && !targetModal.visible
        // Blur the entire page, including navigation, behind task details.
        layer.enabled: (taskDetails.visible || goalDetails.visible) && GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: 0.6
            autoPaddingEnabled: false
        }

        Rectangle {
            id: focusReminderBanner
            objectName: "focusReminderBanner"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            visible: focusController.warningLevel > 0 || focusController.errorMessage.length > 0
            height: focusReminderContent.implicitHeight + 24
            radius: 14
            color: focusController.warningLevel === 2 || focusController.errorMessage.length > 0
                   ? "#3B1B24" : "#24213D"
            border.color: focusController.warningLevel === 2 ? "#EF4444" : "#818CF8"
            RowLayout {
                id: focusReminderContent
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    text: focusController.errorMessage.length > 0 ? focusController.errorMessage
                          : focusController.warningLevel === 2
                            ? "Return to your focus. Your screen has been awake for " + Math.floor(focusController.currentUnlockSeconds / 60) + " minutes."
                            : "A gentle reminder: turn off your screen and return to your task."
                    color: focusController.warningLevel === 2 ? "#FCA5A5" : "#E0E7FF"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    Accessible.role: Accessible.AlertMessage
                    Accessible.name: text
                }
                AppButton {
                    text: focusController.running ? "End focus" : "Settings"
                    onClicked: {
                        if (focusController.running) focusController.stop()
                        else focusSetupDialog.open()
                    }
                }
            }
        }

        Item {
            id: pageContent
            anchors.top: focusReminderBanner.visible ? focusReminderBanner.bottom : parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: bottomNavigation.top
            anchors.margins: 20
            // The add button floats over content; only the scrolling lists need
            // trailing space to let their last item move clear of the button.
            anchors.bottomMargin: 20

            ColumnLayout {
                id: homePage
                objectName: "dashboardContent"
                anchors.fill: parent
                spacing: 16
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
                Rectangle {
                    id: rolloverNotice
                    objectName: "rolloverNotice"
                    Layout.fillWidth: true
                    visible: taskManager.rolloverMessage.length > 0
                    implicitHeight: rolloverNoticeContent.implicitHeight + 24
                    color: taskManager.rolloverFailed ? "#3B1B24" : "#1D2932"
                    border.color: taskManager.rolloverFailed ? "#F87171" : "#3B5962"
                    radius: 14
                    RowLayout {
                        id: rolloverNoticeContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: taskManager.rolloverMessage
                            color: taskManager.rolloverFailed ? "#FCA5A5" : "#BAE6D5"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            textFormat: Text.PlainText
                            Accessible.role: Accessible.AlertMessage
                            Accessible.name: text
                        }
                        AppButton {
                            visible: taskManager.rolloverFailed
                            text: "Retry"
                            implicitHeight: 36
                            onClicked: taskManager.refreshToday()
                        }
                        Button {
                            id: dismissRollover
                            implicitWidth: 32
                            implicitHeight: 36
                            padding: 0
                            Accessible.name: "Dismiss task rollover message"
                            onClicked: taskManager.dismissRolloverMessage()
                            contentItem: Text {
                                text: "×"
                                font.pixelSize: 22
                                color: "#CBD5E1"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: dismissRollover.down ? "#334155" : "transparent"
                                radius: 8
                                border.color: dismissRollover.activeFocus ? "#A5B4FC" : "transparent"
                            }
                        }
                    }
                }

                Button {
                    id: focusBudgetButton
                    objectName: "focusBudgetButton"
                    Layout.fillWidth: true
                    implicitHeight: 84
                    padding: 16
                    Accessible.name: "Focus Budget. Edit daily focus target"
                    onClicked: targetModal.openForTarget(taskManager.targetHours)

                    background: Rectangle {
                        color: focusBudgetButton.down ? "#272735" : focusBudgetButton.hovered ? "#20202D" : "#1B1B26"
                        radius: 16
                        border.color: focusBudgetButton.activeFocus ? "#818CF8" : "#27272A"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
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
                Button {
                    id: autoConfigureButton
                    objectName: "autoConfigureButton"
                    Layout.fillWidth: true
                    implicitHeight: 58
                    padding: 12
                    hoverEnabled: true
                    Accessible.name: "Auto task configure. Coming soon"
                    onClicked: autoConfigureInfo.open()
                    background: Rectangle {
                        radius: 14
                        color: autoConfigureButton.down ? "#332C52" : autoConfigureButton.hovered ? "#2A2541" : "#211D32"
                        border.color: autoConfigureButton.activeFocus ? "#A5B4FC" : "#44385F"
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: RowLayout {
                        spacing: 10
                        NavigationIcon { iconName: "plan"; tint: "#A5B4FC"; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                        Text {
                            Layout.fillWidth: true
                            text: "Auto task configure"
                            color: "#E0DBFF"
                            font.pixelSize: 13
                            font.bold: true
                            wrapMode: Text.Wrap
                        }
                        InfoBadge { text: "Coming soon"; tint: "#B5A6EB" }
                    }
                }
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
                        bottomMargin: addTaskButton.height + 24

                        delegate: SwipeDelegate {
                            id: delegate
                            required property var model
                            objectName: "taskRow" + model.taskId
                            width: listView.width
                            leftPadding: 16
                            rightPadding: 16
                            implicitHeight: (model.subtaskCount > 0 ? 100 : 76) + (model.goalId > 0 ? 18 : 0)
                            onClicked: {
                                if (swipe.position === 0) taskDetails.openForTask(model.taskId)
                            }

                            background: Rectangle {
                                color: delegate.down ? "#242433" : delegate.hovered ? "#20202B" : "#18181F"
                                radius: 16
                                border.color: delegate.activeFocus ? "#818CF8" : "#30303C"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            contentItem: RowLayout {
                                spacing: 14

                                // Checkbox Toggle
                                PlannerCheckBox {
                                    objectName: "taskCheckbox" + model.taskId
                                    implicitWidth: 32
                                    checked: model.isCompleted
                                    Accessible.name: "Complete " + model.name
                                    onClicked: taskManager.toggleTaskById(model.taskId)
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

                                    RowLayout {
                                        spacing: 6
                                        InfoBadge { text: model.effectiveMinutes + " min"; tint: "#B3B3C6" }
                                        InfoBadge {
                                            text: model.category
                                            tint: model.category === "Work" ? "#A5B4FC" : model.category === "Health" ? "#6EE7B7" : "#FCD34D"
                                        }
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
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        visible: model.subtaskCount > 0
                                        implicitHeight: 4
                                        radius: 2
                                        color: "#30303B"
                                        Rectangle {
                                            width: parent.width * (model.subtaskCount > 0 ? model.completedSubtaskCount / model.subtaskCount : 0)
                                            height: parent.height
                                            radius: 2
                                            color: model.isCompleted ? "#34D399" : "#818CF8"
                                            Behavior on width { NumberAnimation { duration: 180 } }
                                        }
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
            hoverEnabled: true
            scale: down ? 0.96 : hovered ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: 130 } }
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
    Popup {
        id: autoConfigureInfo
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 400)
        height: Math.min(parent.height - 32, 280)
        padding: 20
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "#1D1D27"; radius: 20; border.color: "#49425F" }
        Overlay.modal: Rectangle { color: "#99000000" }
        contentItem: ScrollView {
            id: autoInfoScroll
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: autoInfoScroll.availableWidth
                spacing: 16
                InfoBadge { text: "Coming soon"; tint: "#B5A6EB" }
                Text { Layout.fillWidth: true; text: "Auto task configure"; color: "#FFFFFF"; font.pixelSize: 21; font.bold: true; wrapMode: Text.Wrap }
                Text {
                    Layout.fillWidth: true
                    text: "Automatic daily planning is coming later. For now, arrange your tasks manually."
                    color: "#B9B9CB"
                    font.pixelSize: 14
                    wrapMode: Text.Wrap
                }
                AppButton { Layout.fillWidth: true; text: "Got it"; onClicked: autoConfigureInfo.close() }
            }
        }
    }

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
