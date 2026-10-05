import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDrawer {
    id: root
    property int taskId: 0
    property string loadedPlannedDate: ""
    heading: "Edit task"
    subtitle: "Fine-tune the details and decide when to work on it."
    saveText: "Save changes"
    saveEnabled: nameInput.text.trim().length > 0

    function openForTask(id) {
        var task = taskManager.getTask(id)
        if (!task.taskId) return
        taskId = id
        nameInput.text = task.name
        descriptionInput.text = task.description
        minutesInput.value = task.minutes
        categoryInput.value = task.category
        plannedDate.allowEmpty = task.goalId > 0
        loadedPlannedDate = task.plannedDate || ""
        plannedDate.value = loadedPlannedDate
        errorMessage = ""
        open()
    }
    onSubmitRequested: {
        errorMessage = ""
        if (taskManager.updateTask(taskId, {
            name: nameInput.text, description: descriptionInput.text, minutes: minutesInput.value,
            category: categoryInput.value, plannedDate: plannedDate.value
        })) close()
    }

    Text { Layout.fillWidth: true; text: "TASK TITLE"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    PlannerField { id: nameInput; Layout.fillWidth: true; placeholderText: "Give this task a clear name" }
    Text { Layout.fillWidth: true; text: "DESCRIPTION"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    PlannerArea { id: descriptionInput; Layout.fillWidth: true; placeholderText: "Context, notes, or the result you want" }
    Text { Layout.fillWidth: true; text: "ORIGINAL ESTIMATE"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    RowLayout {
        Layout.fillWidth: true
        DurationSpinBox { id: minutesInput; Layout.fillWidth: true; from: 1; to: 100000; Accessible.name: "Original task estimate in minutes" }
        InfoBadge { text: "minutes"; tint: "#B3B3C6" }
    }
    Text { Layout.fillWidth: true; text: "CATEGORY"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    CategorySelector { id: categoryInput; Layout.fillWidth: true; onSelected: function(category) { categoryInput.value = category } }
    DateField { id: plannedDate; Layout.fillWidth: true; placeholderText: "Select a date" }
    Text {
        Layout.fillWidth: true
        text: "Subtasks follow this date. Their combined duration is used in the Focus Budget once you add them."
        color: "#9999AF"; font.pixelSize: 12; wrapMode: Text.Wrap
    }
    Connections {
        target: taskManager
        function onTaskChanged(id) {
            if (!root.visible || id !== root.taskId) return
            var task = taskManager.getTask(id)
            // Follow rollover only if the date field is untouched; keep the
            // other draft inputs and any date the user explicitly selected.
            if (plannedDate.value === root.loadedPlannedDate)
                plannedDate.value = task.plannedDate || ""
            root.loadedPlannedDate = task.plannedDate || ""
        }
        function onErrorOccurred(message) { if (root.visible) root.errorMessage = message }
    }
}
