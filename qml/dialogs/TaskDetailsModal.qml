pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "DateUtils.js" as Dates

FocusScope {
    id: root
    objectName: "taskDetailsModal"
    anchors.fill: parent
    visible: false
    z: 100
    focus: visible

    property int selectedTaskId: -1
    property var task: ({})
    property bool hasPreview: false
    property bool editingSaved: false
    property string errorMessage: ""
    property string confirmation: ""
    property int previewRevision: 0
    property bool editPopupVisible: false
    signal editRequested(int taskId)
    readonly property bool generating: aiService.busy && aiService.activeTaskId === selectedTaskId
    readonly property int suggestedMinutes: {
        var revision = previewRevision
        var total = 0
        for (var i = 0; i < previewModel.count; ++i)
            total += previewModel.get(i).minutes
        return total
    }
    readonly property bool previewValid: {
        var revision = previewRevision
        if (previewModel.count < 1 || previewModel.count > 12) return false
        for (var i = 0; i < previewModel.count; ++i) {
            var step = previewModel.get(i)
            if (!step.name.trim().length || step.minutes < 1 || step.minutes > 120) return false
        }
        return true
    }

    ListModel { id: previewModel }
    ListModel { id: savedModel }

    function refresh() {
        task = taskManager.getTask(selectedTaskId)
        savedModel.clear()
        var steps = taskManager.getSubtasks(selectedTaskId)
        for (var i = 0; i < steps.length; ++i) savedModel.append(steps[i])
        // Background rollover can refresh details while a draft/editor has focus.
        if (visible && !hasPreview && !editPopupVisible) forceActiveFocus()
    }
    function openForTask(taskId) {
        // Switching programmatically must also respect an unsaved preview.
        if (visible) return
        selectedTaskId = taskId
        refresh()
        if (!task.taskId) return
        hasPreview = false
        editingSaved = false
        previewModel.clear()
        errorMessage = ""
        confirmation = ""
        visible = true
        forceActiveFocus()
        content.contentY = 0
    }
    function closeCard() {
        if (generating) aiService.cancel()
        hasPreview = false
        editingSaved = false
        previewModel.clear()
        confirmation = ""
        visible = false
        selectedTaskId = -1
    }
    function requestClose() {
        forceActiveFocus()
        if (hasPreview) confirmation = "discard"
        else closeCard()
    }
    function generate() {
        if (aiService.busy || hasPreview) return
        errorMessage = ""
        aiService.breakdownTask(selectedTaskId, task)
    }
    function editSubtasks() {
        if (aiService.busy || hasPreview) return
        previewModel.clear()
        for (var i = 0; i < savedModel.count; ++i) {
            var step = savedModel.get(i)
            previewModel.append({ subtaskId: step.subtaskId, name: step.name,
                                  description: step.description, minutes: step.minutes })
        }
        if (!previewModel.count)
            previewModel.append({ subtaskId: 0, name: "", description: "", minutes: 15 })
        editingSaved = true
        hasPreview = true
        previewRevision++
        errorMessage = ""
    }
    function discardDraft() {
        hasPreview = false
        editingSaved = false
        previewModel.clear()
        previewRevision++
        confirmation = ""
        errorMessage = ""
        refresh()
    }
    function savePreview() {
        forceActiveFocus()
        if (!previewValid) return
        if (savedModel.count > 0 && !editingSaved) confirmation = "replace"
        else commitPreview()
    }
    function commitPreview() {
        forceActiveFocus()
        var steps = []
        for (var i = 0; i < previewModel.count; ++i) {
            var step = previewModel.get(i)
            steps.push({ subtaskId: editingSaved ? step.subtaskId : 0,
                         name: step.name, description: step.description, minutes: step.minutes })
        }
        confirmation = ""
        errorMessage = ""
        var saved = editingSaved ? taskManager.updateSubtasks(selectedTaskId, steps)
                                 : taskManager.saveSubtasks(selectedTaskId, steps)
        if (saved) {
            hasPreview = false
            editingSaved = false
            previewModel.clear()
            refresh()
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible && !root.editPopupVisible
        context: Qt.WindowShortcut
        onActivated: {
            if (root.confirmation.length) {
                root.confirmation = ""
                root.forceActiveFocus()
            } else root.requestClose()
        }
    }
    Connections {
        target: aiService
        function onBreakdownComplete(taskId, steps) {
            if (!root.visible || taskId !== root.selectedTaskId) return
            previewModel.clear()
            for (var i = 0; i < steps.length; ++i)
                previewModel.append({ subtaskId: 0, name: steps[i].name,
                                      description: steps[i].description, minutes: steps[i].minutes })
            root.editingSaved = false
            root.hasPreview = true
            root.previewRevision++
            root.errorMessage = ""
        }
        function onErrorOccurred(taskId, message) {
            if (root.visible && taskId === root.selectedTaskId) root.errorMessage = message
        }
    }
    Connections {
        target: taskManager
        function onTaskChanged(taskId) {
            if (root.visible && taskId === root.selectedTaskId) root.refresh()
        }
        function onTaskRemoved(taskId) {
            if (root.visible && taskId === root.selectedTaskId) root.closeCard()
        }
        function onErrorOccurred(message) {
            if (root.visible) root.errorMessage = message
        }
    }

    component CardButton: AppButton {}
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.55 }
    MouseArea { anchors.fill: parent; onClicked: root.requestClose(); onWheel: function(wheel) { wheel.accepted = true } }

    Rectangle {
        id: card
        objectName: "detailsCard"
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 520)
        height: Math.min(parent.height - 32, 760)
        radius: 22
        color: "#18181B"
        border.color: "#3F3F46"
        scale: root.visible ? 1 : 0.97
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        // Prevent empty areas inside the card from closing it.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14
            enabled: root.confirmation.length === 0
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Task details"
                    color: "#FFFFFF"
                    font.pixelSize: 20
                    font.bold: true
                    wrapMode: Text.Wrap
                }
                CardButton {
                    text: "Edit"
                    fillColor: "#27272A"
                    enabled: !root.hasPreview && !aiService.busy
                    onClicked: root.editRequested(root.selectedTaskId)
                }
                CardButton {
                    objectName: "closeDetailsButton"
                    text: "Close"
                    fillColor: "#27272A"
                    onClicked: root.requestClose()
                }
            }
            Flickable {
                id: content
                objectName: "detailsScroll"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: contentColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; active: true }
                ColumnLayout {
                    id: contentColumn
                    width: content.width
                    spacing: 14
                    Text {
                        Layout.fillWidth: true
                        text: root.task.name || ""
                        color: "#FFFFFF"
                        font.pixelSize: 22
                        font.bold: true
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        InfoBadge {
                            text: root.task.category || "Personal"
                            tint: root.task.category === "Work" ? "#A5B4FC" : root.task.category === "Health" ? "#6EE7B7" : "#FCD34D"
                        }
                        InfoBadge { text: "Original estimate: " + (root.task.minutes || 0) + " min"; tint: "#B3B3C6" }
                        InfoBadge { text: root.task.isCompleted ? "Completed" : "In progress"; tint: root.task.isCompleted ? "#6EE7B7" : "#A5B4FC" }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.task.description || "No description added."
                        textFormat: Text.PlainText
                        color: "#D4D4D8"
                        font.pixelSize: 14
                        wrapMode: Text.Wrap
                    }
                    PlannerCheckBox {
                        objectName: "parentCompletion"
                        text: root.task.isCompleted ? "Task completed" : "Mark task complete"
                        checked: !!root.task.isCompleted
                        enabled: !root.hasPreview && !root.generating
                        palette.windowText: "#D4D4D8"
                        palette.text: "#D4D4D8"
                        onClicked: taskManager.toggleTaskById(root.selectedTaskId)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Planned: " + Dates.label(root.task.plannedDate || "", "Unscheduled")
                        color: "#A1A1AA"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!root.task.goalName
                        text: "Goal: " + (root.task.goalName || "")
                        textFormat: Text.PlainText
                        color: "#A5B4FC"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#3F3F46" }
                    Text {
                        Layout.fillWidth: true
                        text: root.hasPreview ? (root.editingSaved ? "Edit subtasks" : "Suggested steps") : "Subtasks"
                        color: "#FFFFFF"
                        font.pixelSize: 17
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.hasPreview
                        text: (root.editingSaved ? "Changes keep existing completion progress. Total: "
                                               : "Edit, add, or reorder these steps before saving. Total: ") + root.suggestedMinutes
                              + " min • Original estimate: " + (root.task.minutes || 0) + " min"
                        color: "#C7D2FE"
                        wrapMode: Text.Wrap
                        font.pixelSize: 13
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !root.hasPreview && savedModel.count > 0
                        text: (root.task.completedSubtaskCount || 0) + " of " + savedModel.count
                              + " completed • " + (root.task.effectiveMinutes || 0) + " min planned"
                        color: "#A5B4FC"
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.hasPreview && root.suggestedMinutes > (root.task.minutes || 0)
                        text: "The total exceeds your original estimate. Review the durations before saving."
                        color: "#FCD34D"
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !root.hasPreview && savedModel.count === 0
                        text: "Turn this task into manageable steps. Start with one small action and work toward the goal."
                        color: "#A1A1AA"
                        font.pixelSize: 14
                        wrapMode: Text.Wrap
                    }
                    StepsEditor {
                        Layout.fillWidth: true
                        visible: root.hasPreview
                        stepsModel: previewModel
                        onEdited: root.previewRevision++
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 5
                        radius: 3
                        visible: !root.hasPreview && savedModel.count > 0
                        color: "#30303B"
                        Rectangle {
                            height: parent.height
                            width: parent.width * (savedModel.count > 0 ? (root.task.completedSubtaskCount || 0) / savedModel.count : 0)
                            radius: 3
                            color: "#34D399"
                            Behavior on width { NumberAnimation { duration: 180 } }
                        }
                    }
                    CardButton {
                        Layout.fillWidth: true
                        visible: !root.hasPreview
                        text: savedModel.count > 0 ? "Edit subtasks" : "Create subtasks manually"
                        fillColor: "#302B4D"
                        enabled: !aiService.busy
                        onClicked: root.editSubtasks()
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !root.hasPreview
                        spacing: 10
                        Repeater {
                            model: savedModel
                            delegate: Rectangle {
                                id: saved
                                required property int index
                                required property int subtaskId
                                required property string name
                                required property string description
                                required property int minutes
                                required property bool isCompleted
                                Layout.fillWidth: true
                                implicitHeight: savedColumn.implicitHeight + 24
                                color: "#22222C"
                                radius: 12
                                ColumnLayout {
                                    id: savedColumn
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6
                                    RowLayout {
                                        Layout.fillWidth: true
                                        PlannerCheckBox {
                                            objectName: "subtaskCheck" + saved.index
                                            checked: saved.isCompleted
                                            enabled: !root.generating
                                            onClicked: taskManager.toggleSubtask(root.selectedTaskId, saved.subtaskId)
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (saved.index + 1) + ". " + saved.name
                                            textFormat: Text.PlainText
                                            color: saved.isCompleted ? "#A1A1AA" : "#FFFFFF"
                                            font.pixelSize: 14
                                            font.bold: true
                                            font.strikeout: saved.isCompleted
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: saved.description
                                        textFormat: Text.PlainText
                                        color: "#D4D4D8"
                                        font.pixelSize: 13
                                        wrapMode: Text.Wrap
                                    }
                                    Text { text: saved.minutes + " min • " + (root.task.category || ""); color: "#A5B4FC"; font.pixelSize: 12 }
                                }
                            }
                        }
                    }
                }
            }
            Text {
                objectName: "breakdownError"
                Layout.fillWidth: true
                visible: root.errorMessage.length > 0
                text: root.errorMessage
                textFormat: Text.PlainText
                color: "#FCA5A5"
                wrapMode: Text.Wrap
                font.pixelSize: 13
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.generating
                BusyIndicator { running: root.generating; implicitWidth: 28; implicitHeight: 28 }
                Text { Layout.fillWidth: true; text: "Finding useful steps for your task…"; color: "#A1A1AA"; wrapMode: Text.Wrap }
            }
            Text {
                Layout.fillWidth: true
                visible: root.hasPreview && !root.previewValid
                text: "Keep 1–12 steps, each with a title and a duration of 1–120 minutes."
                color: "#FCD34D"
                wrapMode: Text.Wrap
                font.pixelSize: 12
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.hasPreview
                CardButton {
                    Layout.fillWidth: true
                    text: "Cancel"
                    fillColor: "#30303B"
                    onClicked: { root.forceActiveFocus(); root.confirmation = "cancel" }
                }
                CardButton {
                    Layout.fillWidth: true
                    text: root.editingSaved ? "Save changes" : "Save subtasks"
                    fillColor: "#059669"
                    enabled: root.previewValid
                    onClicked: root.savePreview()
                }
            }
            CardButton {
                objectName: "breakdownAction"
                Layout.fillWidth: true
                visible: !root.hasPreview
                text: root.generating ? "Breaking down…" : root.hasPreview ? "Save subtasks"
                      : savedModel.count > 0 ? "Regenerate breakdown" : "Break down the task"
                enabled: !aiService.busy && (!root.hasPreview || root.previewValid)
                fillColor: root.hasPreview ? "#059669" : "#6366F1"
                onClicked: root.hasPreview ? root.savePreview() : root.generate()
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 22
            color: "#D9000000"
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
                        text: root.confirmation === "replace" ? "Replace saved subtasks?" : "Discard unsaved changes?"
                        color: "#FFFFFF"
                        font.bold: true
                        font.pixelSize: 17
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.confirmation === "replace"
                              ? "Saving this breakdown replaces the existing subtasks and resets their completion progress."
                              : "Your unsaved changes will be discarded. Saved subtasks and progress will stay unchanged."
                        color: "#D4D4D8"
                        wrapMode: Text.Wrap
                    }
                    CardButton {
                        objectName: "confirmBreakdownAction"
                        Layout.fillWidth: true
                        text: root.confirmation === "replace" ? "Replace subtasks"
                              : root.confirmation === "cancel" ? "Discard changes" : "Discard and close"
                        fillColor: "#DC2626"
                        onClicked: {
                            if (root.confirmation === "replace") root.commitPreview()
                            else if (root.confirmation === "cancel") root.discardDraft()
                            else root.closeCard()
                        }
                    }
                    CardButton {
                        Layout.fillWidth: true
                        text: "Keep editing"
                        fillColor: "#3F3F46"
                        onClicked: {
                            root.confirmation = ""
                            root.forceActiveFocus()
                        }
                    }
                }
            }
        }
    }
}
