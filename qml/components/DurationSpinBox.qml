import QtQuick
import QtQuick.Controls

SpinBox {
    id: root
    from: 1
    to: 120
    editable: true
    hoverEnabled: true
    implicitWidth: 132
    implicitHeight: 42
    padding: 0
    leftPadding: 38
    rightPadding: 38
    font.pixelSize: 14
    textFromValue: function(value, locale) { return String(value) }
    valueFromText: function(text, locale) {
        try {
            var entered = Number.fromLocaleString(locale, text)
            return Number.isInteger(entered) ? entered : root.value
        } catch (error) { return root.value }
    }
    contentItem: TextInput {
        text: root.textFromValue(root.value, root.locale)
        color: "#FFFFFF"
        font: root.font
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        readOnly: !root.editable
        validator: root.validator
        inputMethodHints: root.inputMethodHints
        selectByMouse: true
        selectionColor: "#4F46E5"
        onTextEdited: {
            // Keep live totals working on Qt 6.5 as well (SpinBox.live was
            // introduced later). Incomplete or out-of-range text is not saved.
            if (!acceptableInput) return
            var entered = root.valueFromText(text, root.locale)
            if (!Number.isInteger(entered) || entered < root.from || entered > root.to || entered === root.value) return
            var previousCursor = cursorPosition
            root.value = entered
            root.valueModified()
            cursorPosition = Math.min(previousCursor, text.length)
        }
    }
    up.indicator: Rectangle {
        x: root.width - width
        width: 36
        height: root.height
        radius: 9
        color: root.up.pressed ? "#4338CA" : root.up.hovered ? "#373345" : "#30303B"
        Text { anchors.centerIn: parent; text: "+"; color: root.enabled && root.value < root.to ? "#C7D2FE" : "#71717A"; font.pixelSize: 22 }
    }
    down.indicator: Rectangle {
        width: 36
        height: root.height
        radius: 9
        color: root.down.pressed ? "#4338CA" : root.down.hovered ? "#373345" : "#30303B"
        Text { anchors.centerIn: parent; text: "−"; color: root.enabled && root.value > root.from ? "#C7D2FE" : "#71717A"; font.pixelSize: 22 }
    }
    background: Rectangle {
        color: "#16161E"
        radius: 10
        border.color: root.activeFocus ? "#818CF8" : "#3F3F46"
    }
}
