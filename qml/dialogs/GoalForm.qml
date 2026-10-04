import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FormDrawer {
    maximumCardWidth: 540
    maximumCardHeight: 780
    id: root
    property int editingGoalId: 0
    signal goalSaved(int goalId)
    heading: editingGoalId > 0 ? "Edit goal" : "Create long-term goal"
    subtitle: "Define the outcome. Turn it into manageable steps with AI after saving."
    saveText: editingGoalId > 0 ? "Save changes" : "Create goal"
    saveEnabled: nameInput.text.trim().length > 0

    function openForGoal(goalId) {
        editingGoalId = goalId
        var goal = goalId > 0 ? taskManager.getGoal(goalId) : ({})
        nameInput.text = goal.name || ""
        descriptionInput.text = goal.description || ""
        successInput.text = goal.successCriteria || ""
        targetDate.value = goal.targetDate || ""
        categoryInput.value = goal.category || "Personal"
        startingPoint.text = goal.startingPoint || ""
        weeklyHours.value = Math.round((goal.weeklyHours || 0) * 2)
        moreDetails.checked = !!goal.startingPoint || goal.weeklyHours > 0
        errorMessage = ""
        open()
    }
    onSubmitRequested: {
        errorMessage = ""
        var goalId = taskManager.saveGoal({
            name: nameInput.text, description: descriptionInput.text, successCriteria: successInput.text,
            targetDate: targetDate.value, category: categoryInput.value,
            startingPoint: startingPoint.text, weeklyHours: weeklyHours.value / 2
        }, editingGoalId)
        if (goalId > 0) { close(); goalSaved(goalId) }
    }

    Text { Layout.fillWidth: true; text: "GOAL TITLE"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    PlannerField { id: nameInput; Layout.fillWidth: true; placeholderText: "What do you want to achieve?" }
    Text { Layout.fillWidth: true; text: "DESCRIPTION"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    PlannerArea { id: descriptionInput; Layout.fillWidth: true; placeholderText: "Describe your goal and why it matters." }
    Text { Layout.fillWidth: true; text: "DEFINITION OF SUCCESS"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    PlannerArea { id: successInput; Layout.fillWidth: true; placeholderText: "What will be true when you have achieved this goal?" }
    Text { Layout.fillWidth: true; text: "CATEGORY"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
    CategorySelector { id: categoryInput; Layout.fillWidth: true; value: "Personal"; onSelected: function(category) { categoryInput.value = category } }
    DateField {
        id: targetDate
        Layout.fillWidth: true
        label: "Target date (optional)"
        allowEmpty: true
        placeholderText: "Select a deadline"
        emptyLabel: "No deadline"
    }
    PlannerCheckBox { id: moreDetails; text: "Add starting point and weekly availability"; Layout.fillWidth: true }
    ColumnLayout {
        visible: moreDetails.checked
        Layout.fillWidth: true
        spacing: 12
        Text { Layout.fillWidth: true; text: "STARTING POINT"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
        PlannerArea { id: startingPoint; Layout.fillWidth: true; placeholderText: "What have you already done or learned?" }
        Text { Layout.fillWidth: true; text: "HOURS AVAILABLE PER WEEK"; color: "#B3B3C6"; font.pixelSize: 11; font.bold: true }
        DurationSpinBox {
            id: weeklyHours
            Layout.fillWidth: true
            from: 0
            to: 336
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            Accessible.name: "Hours available per week"
            validator: DoubleValidator { bottom: 0; top: 168; decimals: 1; locale: weeklyHours.locale.name }
            textFromValue: function(value, locale) { return (value / 2).toLocaleString(locale, 'f', 1) }
            valueFromText: function(text, locale) {
                try {
                    var hours = Number.fromLocaleString(locale, text)
                    return Number.isFinite(hours) ? Math.round(hours * 2) : weeklyHours.value
                } catch (error) { return weeklyHours.value }
            }
        }
        Text { Layout.fillWidth: true; text: "Use half-hour increments, or leave 0 if you are unsure."; color: "#9999AF"; font.pixelSize: 12; wrapMode: Text.Wrap }
    }
    Connections {
        target: taskManager
        function onErrorOccurred(message) { if (root.visible) root.errorMessage = message }
    }
}
