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
    color: cardHover.hovered ? "#20202B" : "#18181F"
    radius: 16
    border.color: activeFocus ? "#818CF8" : "#30303C"
    activeFocusOnTab: true
    Accessible.name: root.task.name || "Task"
    Keys.onReturnPressed: root.openRequested(root.task.taskId)
    Keys.onSpacePressed: root.openRequested(root.task.taskId)
    HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
    Behavior on color { ColorAnimation { duration: 150 } }
    MouseArea { anchors.fill: parent; onClicked: root.openRequested(root.task.taskId) }
    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        PlannerCheckBox {
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
            RowLayout {
                spacing: 6
                InfoBadge { text: (root.task.effectiveMinutes || 0) + " min"; tint: "#B3B3C6" }
                InfoBadge {
                    text: root.task.category || "Personal"
                    tint: root.task.category === "Work" ? "#A5B4FC" : root.task.category === "Health" ? "#6EE7B7" : "#FCD34D"
                }
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
            Rectangle {
                Layout.fillWidth: true
                visible: root.task.subtaskCount > 0
                implicitHeight: 4
                radius: 2
                color: "#30303B"
                Rectangle {
                    height: parent.height
                    width: parent.width * (root.task.subtaskCount > 0 ? root.task.completedSubtaskCount / root.task.subtaskCount : 0)
                    radius: 2
                    color: root.task.isCompleted ? "#34D399" : "#818CF8"
                    Behavior on width { NumberAnimation { duration: 180 } }
                }
            }
        }
    }
}
