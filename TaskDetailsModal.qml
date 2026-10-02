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
    property string errorMessage: ""
    property string confirmation: ""
    property int previewRevision: 0
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
        if (visible) forceActiveFocus()
    }
    function openForTask(taskId) {
        // Switching programmatically must also respect an unsaved preview.
        if (visible) return
        selectedTaskId = taskId
        refresh()
        if (!task.taskId) return
        hasPreview = false
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
    function savePreview() {
        forceActiveFocus()
        if (!previewValid) return
        if (savedModel.count > 0) confirmation = "replace"
        else commitPreview()
    }
    function commitPreview() {
        var steps = []
        for (var i = 0; i < previewModel.count; ++i) {
            var step = previewModel.get(i)
            steps.push({ name: step.name, description: step.description, minutes: step.minutes })
        }
        confirmation = ""
        errorMessage = ""
        if (taskManager.saveSubtasks(selectedTaskId, steps)) {
            hasPreview = false
            previewModel.clear()
            refresh()
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible && !Overlay.overlay.visible
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
            for (var i = 0; i < steps.length; ++i) previewModel.append(steps[i])
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

    component CardButton: Button {
        id: control
        property color fillColor: "#6366F1"
        implicitHeight: 44
        padding: 10
        contentItem: Text {
            text: control.text
            color: control.enabled ? "#FFFFFF" : "#71717A"
            font.pixelSize: 14
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
        background: Rectangle {
            radius: 10
            color: control.enabled ? (control.down ? Qt.darker(control.fillColor, 1.15) : control.fillColor) : "#27272A"
        }
    }

    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.55 }
    MouseArea { anchors.fill: parent; onClicked: root.requestClose() }

    Rectangle {
        id: card
        objectName: "detailsCard"
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 520)
        height: Math.min(parent.height - 32, 760)
        radius: 22
        color: "#18181B"
        border.color: "#3F3F46"
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
                    Text {
                        Layout.fillWidth: true
                        text: (root.task.category || "") + "  •  Original estimate: " + (root.task.minutes || 0) + " min"
                        color: "#A1A1AA"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.task.description || "No description added."
                        textFormat: Text.PlainText
                        color: "#D4D4D8"
                        font.pixelSize: 14
                        wrapMode: Text.Wrap
                    }
                    CheckBox {
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
                        text: root.hasPreview ? "Suggested steps" : "Subtasks"
                        color: "#FFFFFF"
                        font.pixelSize: 17
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.hasPreview
                        text: "Review these steps before saving. Suggested total: " + root.suggestedMinutes
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
                        text: "The suggested total exceeds your original estimate. Review the durations before saving."
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
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.hasPreview
                        spacing: 10
                        Repeater {
                            model: previewModel
                            delegate: Rectangle {
                                id: suggestion
                                required property int index
                                required property string name
                                required property string description
                                required property int minutes
                                Layout.fillWidth: true
                                implicitHeight: suggestionColumn.implicitHeight + 24
                                color: "#27272A"
                                radius: 12
                                ColumnLayout {
                                    id: suggestionColumn
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: (suggestion.index + 1) + "."; color: "#A5B4FC"; font.bold: true }
                                        TextField {
                                            objectName: "suggestedTitle" + suggestion.index
                                            Layout.fillWidth: true
                                            text: suggestion.name
                                            color: "#FFFFFF"
                                            selectByMouse: true
                                            placeholderText: "Step title"
                                            background: Rectangle { color: "#18181B"; radius: 6 }
                                            onTextEdited: {
                                                previewModel.setProperty(suggestion.index, "name", text)
                                                root.previewRevision++
                                            }
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: suggestion.description
                                        textFormat: Text.PlainText
                                        color: "#D4D4D8"
                                        font.pixelSize: 13
                                        wrapMode: Text.Wrap
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        SpinBox {
                                            objectName: "suggestedMinutes" + suggestion.index
                                            from: 1
                                            to: 120
                                            Layout.preferredWidth: 120
                                            value: suggestion.minutes
                                            editable: true
                                            palette.text: "#FFFFFF"
                                            palette.base: "#18181B"
                                            onValueModified: {
                                                previewModel.setProperty(suggestion.index, "minutes", value)
                                                root.previewRevision++
                                            }
                                        }
                                        Text { text: "min"; color: "#A1A1AA" }
                                        Item { Layout.fillWidth: true }
                                        CardButton {
                                            objectName: "removeSuggestion" + suggestion.index
                                            text: "Remove"
                                            fillColor: "#3F3F46"
                                            onClicked: {
                                                root.previewRevision++
                                                previewModel.remove(suggestion.index)
                                            }
                                        }
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
                                color: "#27272A"
                                radius: 12
                                ColumnLayout {
                                    id: savedColumn
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6
                                    RowLayout {
                                        Layout.fillWidth: true
                                        CheckBox {
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
                text: "Keep at least one step and give every step a title before saving."
                color: "#FCD34D"
                wrapMode: Text.Wrap
                font.pixelSize: 12
            }
            CardButton {
                objectName: "breakdownAction"
                Layout.fillWidth: true
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
                        text: root.confirmation === "discard" ? "Discard suggested steps?" : "Replace saved subtasks?"
                        color: "#FFFFFF"
                        font.bold: true
                        font.pixelSize: 17
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.confirmation === "discard"
                              ? "Your unsaved suggestions will be discarded. Saved subtasks will stay unchanged."
                              : "Saving this breakdown replaces the existing subtasks and resets their completion progress."
                        color: "#D4D4D8"
                        wrapMode: Text.Wrap
                    }
                    CardButton {
                        objectName: "confirmBreakdownAction"
                        Layout.fillWidth: true
                        text: root.confirmation === "discard" ? "Discard and close" : "Replace subtasks"
                        fillColor: "#DC2626"
                        onClicked: root.confirmation === "discard" ? root.closeCard() : root.commitPreview()
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
