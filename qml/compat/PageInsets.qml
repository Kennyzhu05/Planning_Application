import QtQuick

// Older Qt versions lack SafeArea. Reserve typical status-bar space on Android
// without referencing a QML type that those versions cannot load.
Item {
    readonly property real topInset: Qt.platform.os === "android" ? 28 : 0
}
