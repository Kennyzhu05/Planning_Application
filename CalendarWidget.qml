pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "DateUtils.js" as Dates

ColumnLayout {
    id: root
    property string selectedDate: taskManager.todayDate
    property bool showMarkers: false
    property var displayedMonth: Dates.parse(selectedDate) || new Date()
    signal dateSelected(string date)
    spacing: 8

    onSelectedDateChanged: {
        var date = Dates.parse(selectedDate)
        if (date) displayedMonth = date
    }

    function changeMonth(offset) {
        displayedMonth = new Date(displayedMonth.getFullYear(), displayedMonth.getMonth() + offset, 1)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        AppButton { text: "‹"; Accessible.name: "Previous month"; fillColor: "#27272A"; onClicked: root.changeMonth(-1) }
        Text {
            Layout.fillWidth: true
            text: Qt.formatDate(root.displayedMonth, "MMMM yyyy")
            color: "#FFFFFF"
            font.pixelSize: 16
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
        AppButton { text: "›"; Accessible.name: "Next month"; fillColor: "#27272A"; onClicked: root.changeMonth(1) }
        AppButton {
            text: "Today"
            fillColor: "#312E81"
            onClicked: {
                root.selectedDate = taskManager.todayDate
                root.displayedMonth = Dates.parse(root.selectedDate)
                root.dateSelected(root.selectedDate)
            }
        }
    }
    DayOfWeekRow {
        Layout.fillWidth: true
        implicitHeight: 22
        spacing: monthGrid.spacing
        topPadding: 0
        bottomPadding: 0
        locale: monthGrid.locale
        delegate: Text {
            required property string shortName
            text: shortName
            color: "#A1A1AA"
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    MonthGrid {
        id: monthGrid
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 168
        Layout.preferredHeight: 240
        month: root.displayedMonth.getMonth()
        year: root.displayedMonth.getFullYear()
        spacing: 3
        delegate: Rectangle {
            id: dayCell
            required property var model
            readonly property string dateKey: Dates.key(model.date)
            readonly property bool selected: dateKey === root.selectedDate
            readonly property bool hasItems: {
                var revision = taskManager.revision
                return root.showMarkers && taskManager.hasItemsOnDate(dateKey)
            }
            radius: 8
            color: selected ? "#6366F1" : "transparent"
            border.width: dateKey === taskManager.todayDate ? 1 : 0
            border.color: "#A5B4FC"
            Text {
                anchors.centerIn: parent
                text: dayCell.model.day
                color: dayCell.selected ? "#FFFFFF" : (dayCell.model.month === monthGrid.month ? "#D4D4D8" : "#52525B")
                font.pixelSize: 13
                font.bold: dayCell.selected
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                width: 4
                height: 4
                radius: 2
                visible: dayCell.hasItems
                color: dayCell.selected ? "#FFFFFF" : "#A5B4FC"
            }
        }
        onClicked: function(date) {
            root.selectedDate = Dates.key(date)
            root.dateSelected(root.selectedDate)
        }
    }
}
