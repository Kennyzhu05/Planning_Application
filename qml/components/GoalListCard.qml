import QtQuick
import QtQuick.Layouts
import "DateUtils.js" as Dates

Rectangle {
    id: root
    property var goal: ({})
    signal openRequested(int goalId)
    implicitHeight: details.implicitHeight + 28
    color: cardHover.hovered ? "#20202B" : "#18181F"
    radius: 16
    border.color: activeFocus ? "#818CF8" : "#30303C"
    activeFocusOnTab: true
    Accessible.name: root.goal.name || "Goal"
    Keys.onReturnPressed: root.openRequested(root.goal.goalId)
    Keys.onSpacePressed: root.openRequested(root.goal.goalId)
    HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
    Behavior on color { ColorAnimation { duration: 150 } }
    MouseArea { anchors.fill: parent; onClicked: root.openRequested(root.goal.goalId) }
    ColumnLayout {
        id: details
        anchors.fill: parent
        anchors.margins: 14
        spacing: 7
        Text {
            Layout.fillWidth: true
            text: root.goal.name || ""
            textFormat: Text.PlainText
            color: root.goal.isCompleted ? "#71717A" : "#FFFFFF"
            font.pixelSize: 16
            font.bold: true
            font.strikeout: !!root.goal.isCompleted
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            text: Dates.label(root.goal.targetDate || "", "No deadline") + " • " + (root.goal.category || "Personal")
            color: "#A1A1AA"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            text: root.goal.isCompleted ? "Goal achieved" : (root.goal.taskCount > 0
                ? root.goal.completedTaskCount + " of " + root.goal.taskCount + " planned tasks completed"
                : "Ready to break down into tasks")
            color: root.goal.isCompleted ? "#34D399" : "#A5B4FC"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
        Rectangle {
            visible: root.goal.taskCount > 0
            Layout.fillWidth: true
            implicitHeight: 5
            radius: 3
            color: "#27272A"
            Rectangle {
                width: parent.width * (root.goal.taskCount > 0 ? root.goal.completedTaskCount / root.goal.taskCount : 0)
                height: parent.height
                radius: 3
                color: "#6366F1"
                Behavior on width { NumberAnimation { duration: 180 } }
            }
        }
    }
}
