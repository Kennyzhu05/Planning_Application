pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDrawer {
    id: drawer
    property string plannedDate: taskManager.todayDate
    property int selectedMinutes: 30
    property string selectedCategory: "Work"
    heading: "Create new task"
    subtitle: "Make room for one clear next step in your day."
    saveText: "Create task"
    saveEnabled: taskNameInput.text.trim().length > 0

    function openForDate(date) {
        plannedDate = date || taskManager.todayDate
        taskDate.value = plannedDate
        errorMessage = ""
        open()
    }
    onSubmitRequested: {
        errorMessage = ""
        if (!taskManager.addTask(taskNameInput.text.trim(), selectedMinutes,
            selectedCategory, descriptionInput.text, plannedDate)) return
        taskNameInput.text = ""
        descriptionInput.text = ""
        selectedMinutes = 30
        selectedCategory = "Work"
        close()
    }

    Text { Layout.fillWidth: true; text: "TASK TITLE"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    PlannerField { id: taskNameInput; Layout.fillWidth: true; placeholderText: "e.g., Prepare a presentation" }
    Text { Layout.fillWidth: true; text: "DESCRIPTION (OPTIONAL)"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    PlannerArea { id: descriptionInput; Layout.fillWidth: true; placeholderText: "Add context to help plan useful steps." }
    Text { Layout.fillWidth: true; text: "ESTIMATED DURATION"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    GridLayout {
        Layout.fillWidth: true
        columns: 3
        rowSpacing: 8
        columnSpacing: 8
        Repeater {
            model: [
                { label: "15m", mins: 15 }, { label: "30m", mins: 30 }, { label: "45m", mins: 45 },
                { label: "1h", mins: 60 }, { label: "1.5h", mins: 90 }, { label: "2h", mins: 120 }
            ]
            delegate: AppButton {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                text: modelData.label
                fillColor: drawer.selectedMinutes === modelData.mins ? "#6366F1" : "#30303D"
                Accessible.checkable: true
                Accessible.checked: drawer.selectedMinutes === modelData.mins
                onClicked: drawer.selectedMinutes = modelData.mins
            }
        }
    }
    Text { Layout.fillWidth: true; text: "CATEGORY"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    CategorySelector {
        Layout.fillWidth: true
        value: drawer.selectedCategory
        onSelected: function(category) { drawer.selectedCategory = category }
    }
    DateField { id: taskDate; Layout.fillWidth: true; onEdited: function(date) { drawer.plannedDate = date } }
    Connections {
        target: taskManager
        function onErrorOccurred(message) { if (drawer.visible) drawer.errorMessage = message }
    }
}
