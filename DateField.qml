import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "DateUtils.js" as Dates

ColumnLayout {
    id: root
    property string value: ""
    property string label: "Planned date"
    property string emptyLabel: "Unscheduled"
    property bool allowEmpty: false
    signal edited(string date)
    spacing: 6

    Text { text: root.label; color: "#A1A1AA"; font.pixelSize: 12; font.bold: true }
    RowLayout {
        Layout.fillWidth: true
        AppButton {
            Layout.fillWidth: true
            text: Dates.label(root.value, root.emptyLabel)
            fillColor: "#27272A"
            Accessible.name: root.label + ": " + text
            onClicked: {
                picker.selectedDate = root.value || taskManager.todayDate
                picker.displayedMonth = Dates.parse(picker.selectedDate)
                datePopup.open()
            }
        }
        AppButton {
            visible: root.allowEmpty
            text: root.emptyLabel
            fillColor: "#3F3F46"
            onClicked: { root.value = ""; root.edited("") }
        }
    }
    Popup {
        id: datePopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 24, 400)
        height: Math.min(parent.height - 24, 390)
        padding: 16
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "#18181B"; radius: 18; border.color: "#3F3F46" }
        contentItem: CalendarWidget {
            id: picker
            onDateSelected: function(date) {
                root.value = date
                datePopup.close()
                root.edited(date)
            }
        }
    }
}
