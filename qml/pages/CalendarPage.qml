pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "DateUtils.js" as Dates

ColumnLayout {
    id: root
    property string selectedDate: taskManager.todayDate
    readonly property var tasks: { var revision = taskManager.revision; return taskManager.tasksForDate(selectedDate) }
    readonly property var goals: { var revision = taskManager.revision; return taskManager.goalsForDate(selectedDate) }
    signal taskRequested(int taskId)
    signal goalRequested(int goalId)
    signal addTaskRequested(string date)
    spacing: 14

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        Text { text: "Calendar"; color: "#FFFFFF"; font.pixelSize: 24; font.bold: true }
        Text { Layout.fillWidth: true; text: "Your tasks and goal deadlines, one day at a time."; color: "#8B8B9E"; font.pixelSize: 12; wrapMode: Text.Wrap }
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.minimumHeight: 282
        Layout.preferredHeight: Math.max(282, Math.min(360, root.height * 0.47))
        color: "#1B1B26"
        radius: 20
        border.color: "#333341"
        CalendarWidget {
            anchors.fill: parent
            anchors.margins: 14
            selectedDate: root.selectedDate
            showMarkers: true
            onDateSelected: function(date) { root.selectedDate = date }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: Dates.label(root.selectedDate)
            color: "#FFFFFF"
            font.pixelSize: 15
            font.bold: true
            wrapMode: Text.Wrap
        }
        AppButton { text: "+ Task"; onClicked: root.addTaskRequested(root.selectedDate) }
    }
    ScrollView {
        id: dayScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            width: dayScroll.availableWidth
            spacing: 10
            Text { text: "Scheduled tasks"; color: "#A1A1AA"; font.pixelSize: 12; font.bold: true }
            Text {
                visible: root.tasks.length === 0
                text: "No tasks scheduled for this day."
                color: "#71717A"
                font.pixelSize: 13
            }
            Repeater {
                model: root.tasks
                delegate: TaskListCard {
                    required property var modelData
                    Layout.fillWidth: true
                    task: modelData
                    onOpenRequested: function(taskId) { root.taskRequested(taskId) }
                }
            }
            Text {
                text: "Goal deadlines"
                color: "#A1A1AA"
                font.pixelSize: 12
                font.bold: true
                Layout.topMargin: 8
            }
            Text { visible: root.goals.length === 0; text: "No goals due on this day."; color: "#71717A"; font.pixelSize: 13 }
            Repeater {
                model: root.goals
                delegate: GoalListCard {
                    required property var modelData
                    Layout.fillWidth: true
                    goal: modelData
                    onOpenRequested: function(goalId) { root.goalRequested(goalId) }
                }
            }
        }
    }
}
