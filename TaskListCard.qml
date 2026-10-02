import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "DateUtils.js" as Dates

Rectangle {
    id: root
    property var task: ({})
    property bool showDate: false
    signal openRequested(int taskId)
    implicitHeight: details.implicitHeight + 24
    color: "#18181B"
    radius: 14
    border.color: "#27272A"
    MouseArea { anchors.fill: parent; onClicked: root.openRequested(root.task.taskId) }
    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        CheckBox {
            checked: !!root.task.isCompleted
            Accessible.name: "Complete " + (root.task.name || "task")
            onClicked: taskManager.toggleTaskById(root.task.taskId)
        }
        ColumnLayout {
            id: details
            Layout.fillWidth: true
            spacing: 4
            Text {
                Layout.fillWidth: true
                text: root.task.name || ""
                textFormat: Text.PlainText
                color: root.task.isCompleted ? "#71717A" : "#FFFFFF"
                font.pixelSize: 14
                font.bold: true
                font.strikeout: !!root.task.isCompleted
                wrapMode: Text.Wrap
            }
            Text {
                text: (root.task.effectiveMinutes || 0) + " min • " + (root.task.category || "")
                color: "#A1A1AA"
                font.pixelSize: 12
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
            Text {
                visible: root.showDate
                text: Dates.label(root.task.plannedDate || "", "Unscheduled")
                color: "#A1A1AA"
                font.pixelSize: 12
            }
            Text {
                visible: root.task.subtaskCount > 0
                text: (root.task.completedSubtaskCount || 0) + " of " + (root.task.subtaskCount || 0) + " steps completed"
                color: "#A5B4FC"
                font.pixelSize: 12
            }
        }
    }
}
