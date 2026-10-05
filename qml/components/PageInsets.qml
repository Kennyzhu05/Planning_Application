import QtQuick

// Keep this item at the window origin so moving page content cannot feed back
// into its own safe-area calculation. Available with Qt 6.9 and newer.
Item {
    readonly property real topInset: SafeArea.margins.top
}
