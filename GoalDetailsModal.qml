pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "DateUtils.js" as Dates

FocusScope {
    id: root
    anchors.fill: parent
    visible: false
    z: 100
    focus: visible
    property int selectedGoalId: -1
    property bool hasPreview: false
    property int previewRevision: 0
    property string errorMessage: ""
    property string confirmation: ""
    readonly property var goal: { var revision = taskManager.revision; return taskManager.getGoal(selectedGoalId) }
    readonly property var tasks: { var revision = taskManager.revision; return taskManager.getGoalTasks(selectedGoalId) }
    readonly property bool generating: aiService.busy && aiService.activeGoalId === selectedGoalId
    readonly property int suggestedMinutes: {
        var revision = previewRevision
        var total = 0
        for (var i = 0; i < taskPreview.count; ++i) total += taskPreview.get(i).minutes
        return total
    }
    readonly property bool previewValid: {
        var revision = previewRevision
        if (taskPreview.count < 1 || taskPreview.count > 12 || milestonePreview.count < 1) return false
        for (var m = 0; m < milestonePreview.count; ++m)
            if (!milestonePreview.get(m).name.trim()) return false
        for (var i = 0; i < taskPreview.count; ++i) {
            var task = taskPreview.get(i)
            if (!task.name.trim() || task.minutes < 1 || task.minutes > 120) return false
        }
        return true
    }
    signal editRequested(int goalId)
    signal taskRequested(int taskId)
    ListModel { id: taskPreview }
    ListModel { id: milestonePreview }

    function openForGoal(goalId) {
        if (visible || !taskManager.getGoal(goalId).goalId) return
        selectedGoalId = goalId
        hasPreview = false
        taskPreview.clear()
        milestonePreview.clear()
        confirmation = ""
        errorMessage = ""
        visible = true
        forceActiveFocus()
        content.contentY = 0
    }
    function closeCard() {
        if (generating) aiService.cancel()
        visible = false
        hasPreview = false
        confirmation = ""
        taskPreview.clear()
        milestonePreview.clear()
        selectedGoalId = -1
    }
    function requestClose() {
        if (hasPreview) confirmation = "discard"
        else closeCard()
    }
    function generate() {
        if (aiService.busy || hasPreview) return
        errorMessage = ""
        aiService.breakdownGoal(selectedGoalId, goal)
    }
    function savePreview() {
        forceActiveFocus()
        if (!previewValid) return
        if (tasks.length > 0) confirmation = "replace"
        else commitPreview()
    }
    function commitPreview() {
        var steps = [], milestones = []
        for (var m = 0; m < milestonePreview.count; ++m) milestones.push(milestonePreview.get(m).name)
        for (var i = 0; i < taskPreview.count; ++i) {
            var task = taskPreview.get(i)
            steps.push({ name: task.name, description: task.description, minutes: task.minutes, plannedDate: task.plannedDate })
        }
        errorMessage = ""
        confirmation = ""
        if (taskManager.saveGoalBreakdown(selectedGoalId, milestones, steps)) {
            hasPreview = false
            taskPreview.clear()
            milestonePreview.clear()
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible && !Overlay.overlay.visible
        context: Qt.WindowShortcut
        onActivated: {
            if (root.confirmation.length) root.confirmation = ""
            else root.requestClose()
        }
    }
    Connections {
        target: aiService
        function onGoalBreakdownComplete(goalId, milestones, tasks) {
            if (!root.visible || goalId !== root.selectedGoalId) return
            taskPreview.clear()
            milestonePreview.clear()
            for (var m = 0; m < milestones.length; ++m) milestonePreview.append({ name: milestones[m] })
            for (var i = 0; i < tasks.length; ++i)
                taskPreview.append({ name: tasks[i].name, description: tasks[i].description, minutes: tasks[i].minutes, plannedDate: "" })
            root.hasPreview = true
            root.previewRevision++
            root.errorMessage = ""
        }
        function onGoalErrorOccurred(goalId, message) {
            if (root.visible && goalId === root.selectedGoalId) root.errorMessage = message
        }
    }
    Connections {
        target: taskManager
        function onErrorOccurred(message) { if (root.visible) root.errorMessage = message }
    }

    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.55 }
    MouseArea { anchors.fill: parent; onClicked: root.requestClose(); onWheel: function(wheel) { wheel.accepted = true } }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 540)
        height: Math.min(parent.height - 32, 780)
        color: "#18181B"
        radius: 22
        border.color: "#3F3F46"
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            enabled: root.confirmation.length === 0
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Goal details"; color: "#FFFFFF"; font.pixelSize: 20; font.bold: true }
                AppButton {
                    text: "Edit"
                    fillColor: "#27272A"
                    enabled: !root.hasPreview && !aiService.busy
                    onClicked: root.editRequested(root.selectedGoalId)
                }
                AppButton { text: "Close"; fillColor: "#27272A"; onClicked: root.requestClose() }
            }
            Flickable {
                id: content
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: contentColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: contentColumn
                    width: content.width
                    spacing: 14
                    Text {
                        Layout.fillWidth: true
                        text: root.goal.name || ""
                        textFormat: Text.PlainText
                        color: "#FFFFFF"
                        font.pixelSize: 22
                        font.bold: true
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Dates.label(root.goal.targetDate || "", "No deadline") + " • " + (root.goal.category || "Personal")
                        color: "#A1A1AA"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.goal.description || "No description added."
                        textFormat: Text.PlainText
                        color: "#D4D4D8"
                        font.pixelSize: 14
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Success: " + (root.goal.successCriteria || "Not specified yet.")
                        textFormat: Text.PlainText
                        color: "#C7D2FE"
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!root.goal.startingPoint
                        text: "Starting point: " + (root.goal.startingPoint || "")
                        textFormat: Text.PlainText
                        color: "#A1A1AA"
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                    }
                    Text {
                        visible: root.goal.weeklyHours > 0
                        text: "Available: " + (root.goal.weeklyHours || 0) + " hours per week"
                        color: "#A1A1AA"
                        font.pixelSize: 12
                    }
                    CheckBox {
                        text: root.goal.isCompleted ? "Goal achieved" : "Mark goal achieved"
                        checked: !!root.goal.isCompleted
                        enabled: !root.hasPreview && !root.generating
                        palette.text: "#D4D4D8"
                        palette.windowText: "#D4D4D8"
                        onClicked: taskManager.toggleGoal(root.selectedGoalId)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Completing planned tasks tracks your progress. Mark the goal achieved when its success criteria are met."
                        color: "#71717A"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#3F3F46" }
                    Text {
                        text: root.hasPreview ? "Suggested milestones" : "Milestone roadmap"
                        color: "#FFFFFF"
                        font.pixelSize: 17
                        font.bold: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.hasPreview
                        Repeater {
                            model: milestonePreview
                            delegate: RowLayout {
                                id: milestoneEditor
                                required property int index
                                required property string name
                                Layout.fillWidth: true
                                Text { text: (milestoneEditor.index + 1) + "."; color: "#A5B4FC" }
                                PlannerField {
                                    Layout.fillWidth: true
                                    text: milestoneEditor.name
                                    onTextEdited: { milestonePreview.setProperty(milestoneEditor.index, "name", text); root.previewRevision++ }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !root.hasPreview
                        Repeater {
                            model: root.goal.milestones || []
                            delegate: Text {
                                required property int index
                                required property string modelData
                                Layout.fillWidth: true
                                text: (index + 1) + ". " + modelData
                                textFormat: Text.PlainText
                                color: "#C7D2FE"
                                font.pixelSize: 14
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.hasPreview ? "First milestone tasks • " + root.suggestedMinutes + " min estimated"
                            : root.tasks.length > 0 ? root.goal.completedTaskCount + " of " + root.tasks.length + " planned tasks completed"
                            : "Use AI to create milestones and manageable tasks for the first milestone."
                        color: "#A5B4FC"
                        font.pixelSize: 14
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.hasPreview || root.tasks.length > 0
                        text: "These tasks cover the first milestone. Assign dates to place them on Calendar, or keep them unscheduled in this goal's backlog."
                        color: "#A1A1AA"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.hasPreview
                        spacing: 12
                        Repeater {
                            model: taskPreview
                            delegate: Rectangle {
                                id: suggestion
                                required property int index
                                required property string name
                                required property string description
                                required property int minutes
                                required property string plannedDate
                                Layout.fillWidth: true
                                implicitHeight: fields.implicitHeight + 24
                                color: "#27272A"
                                radius: 12
                                ColumnLayout {
                                    id: fields
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8
                                    Text { text: "Task " + (suggestion.index + 1); color: "#A5B4FC"; font.pixelSize: 12 }
                                    PlannerField {
                                        Layout.fillWidth: true
                                        text: suggestion.name
                                        onTextEdited: { taskPreview.setProperty(suggestion.index, "name", text); root.previewRevision++ }
                                    }
                                    PlannerArea {
                                        Layout.fillWidth: true
                                        text: suggestion.description
                                        onTextChanged: {
                                            if (activeFocus) { taskPreview.setProperty(suggestion.index, "description", text); root.previewRevision++ }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        SpinBox {
                                            from: 1
                                            to: 120
                                            value: suggestion.minutes
                                            editable: true
                                            palette.text: "#FFFFFF"
                                            palette.base: "#18181B"
                                            onValueModified: { taskPreview.setProperty(suggestion.index, "minutes", value); root.previewRevision++ }
                                        }
                                        Text { text: "min"; color: "#A1A1AA" }
                                        Item { Layout.fillWidth: true }
                                        AppButton {
                                            text: "Remove"
                                            fillColor: "#3F3F46"
                                            onClicked: { taskPreview.remove(suggestion.index); root.previewRevision++ }
                                        }
                                    }
                                    DateField {
                                        Layout.fillWidth: true
                                        value: suggestion.plannedDate
                                        allowEmpty: true
                                        onEdited: function(date) { taskPreview.setProperty(suggestion.index, "plannedDate", date); root.previewRevision++ }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: !!suggestion.plannedDate && !!root.goal.targetDate && suggestion.plannedDate > root.goal.targetDate
                                        text: "This task is scheduled after the goal's target date."
                                        color: "#FCD34D"
                                        font.pixelSize: 12
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !root.hasPreview
                        spacing: 10
                        Repeater {
                            model: root.tasks
                            delegate: TaskListCard {
                                required property var modelData
                                Layout.fillWidth: true
                                task: modelData
                                showDate: true
                                enabled: !root.generating
                                onOpenRequested: function(taskId) { root.closeCard(); root.taskRequested(taskId) }
                            }
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: root.errorMessage.length > 0
                text: root.errorMessage
                textFormat: Text.PlainText
                color: "#FCA5A5"
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }
            RowLayout {
                visible: root.generating
                Layout.fillWidth: true
                BusyIndicator { running: root.generating; implicitWidth: 28; implicitHeight: 28 }
                Text { Layout.fillWidth: true; text: "Planning milestones and first steps…"; color: "#A1A1AA"; wrapMode: Text.Wrap }
            }
            Text {
                Layout.fillWidth: true
                visible: root.hasPreview && !root.previewValid
                text: "Keep at least one task and give every milestone and task a title."
                color: "#FCD34D"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            AppButton {
                Layout.fillWidth: true
                text: root.generating ? "Breaking down…" : root.hasPreview ? "Save goal tasks"
                    : root.tasks.length > 0 ? "Regenerate goal breakdown" : "Break down this goal"
                enabled: !aiService.busy && (!root.hasPreview || root.previewValid)
                fillColor: root.hasPreview ? "#059669" : "#6366F1"
                onClicked: root.hasPreview ? root.savePreview() : root.generate()
            }
        }
        Rectangle {
            anchors.fill: parent
            color: "#D9000000"
            radius: 22
            visible: root.confirmation.length > 0
            MouseArea { anchors.fill: parent }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 32
                height: confirmColumn.implicitHeight + 32
                color: "#27272A"
                radius: 14
                ColumnLayout {
                    id: confirmColumn
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14
                    Text {
                        Layout.fillWidth: true
                        text: root.confirmation === "discard" ? "Discard suggested goal tasks?" : "Replace this goal's tasks?"
                        color: "#FFFFFF"
                        font.pixelSize: 17
                        font.bold: true
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.confirmation === "discard" ? "Saved tasks will stay unchanged. Unsaved suggestions will be discarded."
                            : "This replaces all tasks linked to this goal, including their existing dates, subtasks, and completion progress. Other daily tasks are unchanged."
                        color: "#D4D4D8"
                        wrapMode: Text.Wrap
                    }
                    AppButton {
                        Layout.fillWidth: true
                        text: root.confirmation === "discard" ? "Discard and close" : "Replace goal tasks"
                        fillColor: "#DC2626"
                        onClicked: root.confirmation === "discard" ? root.closeCard() : root.commitPreview()
                    }
                    AppButton { Layout.fillWidth: true; text: "Keep editing"; fillColor: "#3F3F46"; onClicked: root.confirmation = "" }
                }
            }
        }
    }
}
