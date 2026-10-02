import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Drawer {
    id: root
    width: parent ? parent.width : 390
    height: parent ? parent.height * 0.86 : 700
    edge: Qt.BottomEdge
    property int taskId: 0
    property string errorMessage: ""

    function openForTask(id) {
        var task = taskManager.getTask(id)
        if (!task.taskId) return
        taskId = id
        nameInput.text = task.name
        descriptionInput.text = task.description
        minutesInput.value = task.minutes
        categoryInput.currentIndex = categoryInput.model.indexOf(task.category)
        plannedDate.allowEmpty = task.goalId > 0
        plannedDate.value = task.plannedDate || ""
        errorMessage = ""
        open()
    }

    background: Rectangle { color: "#18181B"; radius: 24; border.color: "#3F3F46" }
    ScrollView {
        id: formScroll
        anchors.fill: parent
        anchors.margins: 20
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            width: formScroll.availableWidth
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Edit task"; color: "#FFFFFF"; font.pixelSize: 20; font.bold: true }
                AppButton { text: "Close"; fillColor: "#27272A"; onClicked: root.close() }
            }
            Text { text: "Task title"; color: "#A1A1AA"; font.pixelSize: 12 }
            PlannerField { id: nameInput; Layout.fillWidth: true }
            Text { text: "Description"; color: "#A1A1AA"; font.pixelSize: 12 }
            PlannerArea { id: descriptionInput; Layout.fillWidth: true }
            Text { text: "Original estimated minutes"; color: "#A1A1AA"; font.pixelSize: 12 }
            SpinBox { id: minutesInput; Layout.fillWidth: true; from: 1; to: 100000; editable: true; palette.text: "#FFFFFF"; palette.base: "#27272A" }
            Text { text: "Category"; color: "#A1A1AA"; font.pixelSize: 12 }
            ComboBox {
                id: categoryInput
                Layout.fillWidth: true
                model: ["Work", "Health", "Personal"]
                palette.text: "#FFFFFF"
                palette.buttonText: "#FFFFFF"
                palette.button: "#27272A"
                palette.base: "#27272A"
            }
            DateField { id: plannedDate; Layout.fillWidth: true }
            Text {
                Layout.fillWidth: true
                text: "Subtasks follow this date. When subtasks exist, their total is used in the Focus Budget."
                color: "#A1A1AA"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            Text { Layout.fillWidth: true; visible: root.errorMessage.length > 0; text: root.errorMessage; color: "#FCA5A5"; wrapMode: Text.Wrap }
            AppButton {
                Layout.fillWidth: true
                text: "Save changes"
                fillColor: "#059669"
                onClicked: {
                    root.errorMessage = ""
                    if (taskManager.updateTask(root.taskId, {
                        name: nameInput.text, description: descriptionInput.text, minutes: minutesInput.value,
                        category: categoryInput.currentText, plannedDate: plannedDate.value
                    })) root.close()
                }
            }
        }
    }
    Connections {
        target: taskManager
        function onErrorOccurred(message) { if (root.visible) root.errorMessage = message }
    }
}
