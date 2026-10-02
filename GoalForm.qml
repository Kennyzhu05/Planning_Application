import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Drawer {
    id: root
    width: parent ? parent.width : 390
    height: parent ? parent.height * 0.9 : 740
    edge: Qt.BottomEdge
    property int editingGoalId: 0
    property string errorMessage: ""
    signal goalSaved(int goalId)

    function openForGoal(goalId) {
        editingGoalId = goalId
        var goal = goalId > 0 ? taskManager.getGoal(goalId) : ({})
        nameInput.text = goal.name || ""
        descriptionInput.text = goal.description || ""
        successInput.text = goal.successCriteria || ""
        targetDate.value = goal.targetDate || ""
        categoryInput.currentIndex = Math.max(0, categoryInput.model.indexOf(goal.category || "Personal"))
        startingPoint.text = goal.startingPoint || ""
        weeklyHours.value = Math.round((goal.weeklyHours || 0) * 2)
        moreDetails.checked = !!goal.startingPoint || goal.weeklyHours > 0
        errorMessage = ""
        formScroll.contentItem.contentY = 0
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
                Text {
                    Layout.fillWidth: true
                    text: root.editingGoalId > 0 ? "Edit goal" : "Create long-term goal"
                    color: "#FFFFFF"
                    font.pixelSize: 20
                    font.bold: true
                    wrapMode: Text.Wrap
                }
                AppButton { text: "Close"; fillColor: "#27272A"; onClicked: root.close() }
            }
            Text { text: "Goal title *"; color: "#A1A1AA"; font.pixelSize: 12 }
            PlannerField { id: nameInput; Layout.fillWidth: true; placeholderText: "What do you want to achieve?" }
            Text { text: "Description"; color: "#A1A1AA"; font.pixelSize: 12 }
            PlannerArea { id: descriptionInput; Layout.fillWidth: true; placeholderText: "Describe your goal and why it matters." }
            Text { text: "Definition of success"; color: "#A1A1AA"; font.pixelSize: 12 }
            PlannerArea { id: successInput; Layout.fillWidth: true; placeholderText: "What will be true when you have achieved this goal?" }
            DateField { id: targetDate; Layout.fillWidth: true; label: "Target date (optional)"; allowEmpty: true; emptyLabel: "No deadline" }
            CheckBox { id: moreDetails; text: "More details"; palette.windowText: "#D4D4D8"; palette.text: "#D4D4D8" }
            ColumnLayout {
                visible: moreDetails.checked
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Category"; color: "#A1A1AA"; font.pixelSize: 12 }
                ComboBox {
                    id: categoryInput
                    Layout.fillWidth: true
                    model: ["Personal", "Work", "Health"]
                    palette.text: "#FFFFFF"
                    palette.buttonText: "#FFFFFF"
                    palette.button: "#27272A"
                    palette.base: "#27272A"
                }
                Text { text: "Starting point / current progress"; color: "#A1A1AA"; font.pixelSize: 12 }
                PlannerArea { id: startingPoint; Layout.fillWidth: true; placeholderText: "What have you already done or learned?" }
                Text { text: "Available hours per week (0 = unspecified)"; color: "#A1A1AA"; font.pixelSize: 12 }
                SpinBox {
                    id: weeklyHours
                    from: 0
                    to: 336
                    editable: true
                    Layout.fillWidth: true
                    palette.text: "#FFFFFF"
                    palette.base: "#27272A"
                    textFromValue: function(value, locale) { return (value / 2).toLocaleString(locale, 'f', 1) }
                    valueFromText: function(text, locale) { return Math.round(Number.fromLocaleString(locale, text) * 2) }
                }
            }
            Text { Layout.fillWidth: true; visible: root.errorMessage.length > 0; text: root.errorMessage; color: "#FCA5A5"; wrapMode: Text.Wrap }
            AppButton {
                Layout.fillWidth: true
                text: "Save goal"
                fillColor: "#059669"
                onClicked: {
                    root.errorMessage = ""
                    var goalId = taskManager.saveGoal({
                        name: nameInput.text, description: descriptionInput.text, successCriteria: successInput.text,
                        targetDate: targetDate.value, category: categoryInput.currentText,
                        startingPoint: startingPoint.text, weeklyHours: weeklyHours.value / 2
                    }, root.editingGoalId)
                    if (goalId > 0) { root.close(); root.goalSaved(goalId) }
                }
            }
        }
    }
    Connections {
        target: taskManager
        function onErrorOccurred(message) { if (root.visible) root.errorMessage = message }
    }
}
