pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    readonly property var goals: { var revision = taskManager.revision; return taskManager.getGoals() }
    signal goalRequested(int goalId)
    spacing: 18
    Text { text: "Long-term goal"; color: "#FFFFFF"; font.pixelSize: 24; font.bold: true }
    Text {
        visible: root.goals.length === 0
        Layout.fillWidth: true
        text: "What would you like to achieve? Tap + to create a goal and turn it into manageable tasks."
        color: "#A1A1AA"
        font.pixelSize: 14
        wrapMode: Text.Wrap
    }
    ScrollView {
        id: goalScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            width: goalScroll.availableWidth
            spacing: 12
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
