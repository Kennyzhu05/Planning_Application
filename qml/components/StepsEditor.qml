pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var stepsModel
    property bool showDates: false
    property string targetDate: ""
    property int revision: 0
    signal edited()
    spacing: 12

    function change(index, role, value) {
        stepsModel.setProperty(index, role, value)
        revision++
        edited()
    }
    function move(index, offset) {
        var destination = index + offset
        if (destination < 0 || destination >= stepsModel.count) return
        stepsModel.move(index, destination, 1)
        revision++
        edited()
    }
    Repeater {
        model: root.stepsModel
        delegate: Rectangle {
            id: step
            required property int index
            required property string name
            required property string description
            required property int minutes
            readonly property string plannedDate: {
                var updated = root.revision
                return root.showDates && index >= 0 && index < root.stepsModel.count
                       ? root.stepsModel.get(index).plannedDate || "" : ""
            }
            Layout.fillWidth: true
            implicitHeight: fields.implicitHeight + 28
            color: "#22222C"
            radius: 16
            border.color: "#343441"
            ColumnLayout {
                id: fields
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: 9; color: "#353054"
                        Text { anchors.centerIn: parent; text: step.index + 1; color: "#C7D2FE"; font.bold: true; font.pixelSize: 12 }
                    }
                    Text { Layout.fillWidth: true; text: "STEP " + (step.index + 1); color: "#A5B4FC"; font.pixelSize: 11; font.bold: true }
                    AppButton {
                        text: "↑"; implicitWidth: 36; implicitHeight: 36; padding: 4
                        fillColor: "#30303B"; enabled: step.index > 0
                        Accessible.name: "Move step " + (step.index + 1) + " up"
                        onClicked: { root.forceActiveFocus(); root.move(step.index, -1) }
                    }
                    AppButton {
                        text: "↓"; implicitWidth: 36; implicitHeight: 36; padding: 4
                        fillColor: "#30303B"; enabled: step.index < root.stepsModel.count - 1
                        Accessible.name: "Move step " + (step.index + 1) + " down"
                        onClicked: { root.forceActiveFocus(); root.move(step.index, 1) }
                    }
                }
                PlannerField {
                    objectName: "suggestedTitle" + step.index
                    Layout.fillWidth: true
                    text: step.name
                    placeholderText: "Step title"
                    maximumLength: 200
                    onTextEdited: root.change(step.index, "name", text)
                }
                PlannerArea {
                    Layout.fillWidth: true
                    text: step.description
                    placeholderText: "Guidance or notes (optional)"
                    onTextChanged: if (activeFocus) root.change(step.index, "description", text)
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: fields.width < 270 ? 2 : 4
                    columnSpacing: 8
                    rowSpacing: 8
                    DurationSpinBox {
                        objectName: "suggestedMinutes" + step.index
                        Layout.preferredWidth: 132
                        value: step.minutes
                        onValueModified: root.change(step.index, "minutes", value)
                    }
                    Text { text: "min"; color: "#A1A1AA"; font.pixelSize: 12 }
                    Item { Layout.fillWidth: true; visible: fields.width >= 270 }
                    AppButton {
                        Layout.columnSpan: fields.width < 270 ? 2 : 1
                        Layout.alignment: Qt.AlignRight
                        objectName: "removeSuggestion" + step.index
                        text: "Remove"; fillColor: "#3F2935"; implicitHeight: 38; padding: 8
                        Accessible.name: "Remove step " + (step.index + 1)
                        onClicked: { root.forceActiveFocus(); root.stepsModel.remove(step.index); root.revision++; root.edited() }
                    }
                }
                DateField {
                    Layout.fillWidth: true
                    visible: root.showDates
                    value: step.plannedDate
                    allowEmpty: true
                    onEdited: function(date) { root.change(step.index, "plannedDate", date) }
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.showDates && root.targetDate.length > 0
                             && step.plannedDate > root.targetDate
                    text: "This task is scheduled after the goal's target date."
                    color: "#FCD34D"; font.pixelSize: 12; wrapMode: Text.Wrap
                }
            }
        }
    }
    AppButton {
        Layout.fillWidth: true
        text: "+ Add " + (root.showDates ? "task" : "subtask")
        fillColor: "#302B4D"
        enabled: root.stepsModel.count < 12
        onClicked: {
            root.forceActiveFocus()
            if (root.stepsModel.count >= 12) return
            if (root.showDates)
                root.stepsModel.append({ name: "", description: "", minutes: 15, plannedDate: "" })
            else
                root.stepsModel.append({ subtaskId: 0, name: "", description: "", minutes: 15 })
            root.revision++
            root.edited()
        }
    }
    Text {
        Layout.fillWidth: true
        text: root.stepsModel.count + " of 12 steps • 1–120 minutes per step"
        color: "#8B8B9E"; font.pixelSize: 11; wrapMode: Text.Wrap
    }
}
