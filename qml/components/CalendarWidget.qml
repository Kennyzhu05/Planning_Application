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
        var next = new Date(displayedMonth.getFullYear(), displayedMonth.getMonth() + offset, 1)
        if (next.getFullYear() >= 1900 && next.getFullYear() <= 9999) displayedMonth = next
    }

    Popup {
        id: monthPicker
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 24, 380)
        height: Math.min(parent.height - 24, 390)
        padding: 18
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property int chosenMonth: 0
        onOpened: {
            chosenMonth = root.displayedMonth.getMonth()
            yearInput.value = root.displayedMonth.getFullYear()
        }
        background: Rectangle { color: "#1D1D27"; radius: 20; border.color: "#49425F" }
        Overlay.modal: Rectangle { color: "#99000000" }
        contentItem: ScrollView {
            id: monthScroll
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: monthScroll.availableWidth
                spacing: 14
                Text { text: "Jump to a month"; color: "#FFFFFF"; font.pixelSize: 20; font.bold: true }
                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: "Year"; color: "#A1A1AA"; font.pixelSize: 13 }
                    DurationSpinBox { id: yearInput; from: 1900; to: 9999; implicitWidth: 164; Accessible.name: "Calendar year" }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: 8
                    rowSpacing: 8
                    Repeater {
                        model: 12
                        delegate: AppButton {
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            text: Qt.formatDate(new Date(2000, index, 1), "MMM")
                            fillColor: monthPicker.chosenMonth === index ? "#6366F1" : "#30303B"
                            Accessible.name: Qt.formatDate(new Date(2000, index, 1), "MMMM")
                            Accessible.checkable: true
                            Accessible.checked: monthPicker.chosenMonth === index
                            onClicked: monthPicker.chosenMonth = index
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    AppButton { Layout.fillWidth: true; text: "Cancel"; fillColor: "#30303B"; onClicked: monthPicker.close() }
                    AppButton {
                        Layout.fillWidth: true
                        text: "Show month"
                        onClicked: {
                            root.forceActiveFocus()
                            root.displayedMonth = new Date(yearInput.value, monthPicker.chosenMonth, 1)
                            monthPicker.close()
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        AppButton { text: "‹"; Accessible.name: "Previous month"; fillColor: "#27272A"; onClicked: root.changeMonth(-1) }
        AppButton {
            Layout.fillWidth: true
            text: Qt.formatDate(root.displayedMonth, "MMMM yyyy")
            fillColor: "#252230"
            Accessible.name: "Choose calendar month and year. " + Qt.formatDate(root.displayedMonth, "MMMM yyyy")
            onClicked: monthPicker.open()
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
