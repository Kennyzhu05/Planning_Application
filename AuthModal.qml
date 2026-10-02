pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: authService.busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    width: Math.min(440, parent.width - 24)
    height: Math.min(610, parent.height - 24)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    padding: 20
    property string mode: "signin"
    readonly property bool needsPassword: mode === "signin" || mode === "signup" || mode === "reset"
    readonly property bool needsCode: mode === "verify" || mode === "reset"

    function openForSignIn() {
        if (opened) return
        mode = "signin"
        passwordField.clear()
        codeField.clear()
        authService.clearMessages()
        open()
    }
    function switchMode(nextMode) {
        mode = nextMode
        passwordField.clear()
        codeField.clear()
        authService.clearMessages()
    }
    function submit() {
        if (authService.busy) return
        var password = passwordField.text
        if (mode === "signin") authService.signIn(emailField.text, password)
        else if (mode === "signup") authService.signUp(emailField.text, password)
        else if (mode === "verify") authService.confirmEmail(emailField.text, codeField.text)
        else if (mode === "recover") authService.sendPasswordReset(emailField.text)
        else if (mode === "reset") authService.resetPassword(emailField.text, codeField.text, password)
        passwordField.clear()
    }
    onClosed: { passwordField.clear(); codeField.clear() }
    background: Rectangle { color: "#18181B"; radius: 20; border.color: "#3F3F46" }
    Overlay.modal: Rectangle { color: "#B309090B" }

    Connections {
        target: authService
        function onVerificationRequired(email) {
            if (!root.visible) return
            root.mode = "verify"
            emailField.text = email
            passwordField.clear()
            codeField.clear()
        }
        function onPasswordResetCodeSent(email) {
            if (!root.visible) return
            root.mode = "reset"
            emailField.text = email
            passwordField.clear()
            codeField.clear()
        }
        function onPasswordResetComplete() {
            root.mode = "signin"
            passwordField.clear()
            codeField.clear()
        }
        function onSignedInChanged() {
            if (authService.signedIn && root.visible) root.close()
        }
    }

    contentItem: ColumnLayout {
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: root.mode === "signup" ? "Create account" : root.mode === "verify" ? "Verify your email"
                    : root.mode === "recover" || root.mode === "reset" ? "Reset password" : "Sign in"
                color: "#FFFFFF"
                font.pixelSize: 23
                font.bold: true
            }
            AppButton { text: "Close"; fillColor: "#3F3F46"; enabled: !authService.busy; onClicked: root.close() }
        }
        ScrollView {
            id: authScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: authScroll.availableWidth
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: root.mode === "verify" ? "Enter the code sent to your email."
                        : root.mode === "reset" ? "Enter your email code and choose a new password."
                        : root.mode === "recover" ? "We'll email you a code to reset your password."
                        : "Sign in to break down tasks and goals with AI. Your planner stays on this device."
                    textFormat: Text.PlainText
                    color: "#A1A1AA"
                    wrapMode: Text.WordWrap
                    font.pixelSize: 13
                }
                Text {
                    Layout.fillWidth: true
                    visible: !authService.configured
                    text: "Account services need setup before sign-in is available. You can continue using your local planner."
                    wrapMode: Text.WordWrap
                    color: "#FBBF24"
                }
                Text { text: "EMAIL"; color: "#A1A1AA"; font.pixelSize: 11; font.bold: true }
                PlannerField {
                    id: emailField
                    Layout.fillWidth: true
                    placeholderText: "you@example.com"
                    maximumLength: 254
                    enabled: !authService.busy
                    inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
                    onAccepted: if (root.needsCode) codeField.forceActiveFocus(); else if (root.needsPassword) passwordField.forceActiveFocus(); else root.submit()
                }
                Text { visible: root.needsCode; text: "EMAIL CODE"; color: "#A1A1AA"; font.pixelSize: 11; font.bold: true }
                PlannerField {
                    id: codeField
                    visible: root.needsCode
                    Layout.fillWidth: true
                    placeholderText: "Verification code"
                    maximumLength: 10
                    inputMethodHints: Qt.ImhDigitsOnly
                    enabled: !authService.busy
                    onAccepted: if (root.mode === "reset") passwordField.forceActiveFocus(); else root.submit()
                }
                Text {
                    visible: root.needsPassword
                    text: root.mode === "reset" ? "NEW PASSWORD" : "PASSWORD"
                    color: "#A1A1AA"; font.pixelSize: 11; font.bold: true
                }
                PlannerField {
                    id: passwordField
                    visible: root.needsPassword
                    Layout.fillWidth: true
                    placeholderText: root.mode === "signin" ? "Password" : "At least 8 characters"
                    echoMode: TextInput.Password
                    maximumLength: 128
                    enabled: !authService.busy
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    onAccepted: root.submit()
                }
                Text {
                    Layout.fillWidth: true
                    visible: authService.errorMessage.length > 0
                    text: authService.errorMessage
                    textFormat: Text.PlainText
                    color: "#FCA5A5"
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: authService.message.length > 0
                    text: authService.message
                    textFormat: Text.PlainText
                    color: "#A7F3D0"
                    wrapMode: Text.WordWrap
                }
                BusyIndicator { Layout.alignment: Qt.AlignHCenter; visible: authService.busy; running: visible; implicitHeight: 32; implicitWidth: 32 }
                AppButton {
                    Layout.fillWidth: true
                    enabled: authService.configured && !authService.busy
                    text: authService.busy ? "Please wait…" : root.mode === "signup" ? "Create account"
                        : root.mode === "verify" ? "Verify email" : root.mode === "recover" ? "Send reset code"
                        : root.mode === "reset" ? "Save new password" : "Sign in"
                    onClicked: root.submit()
                }
                AppButton {
                    Layout.fillWidth: true
                    visible: root.mode === "signin"
                    enabled: !authService.busy
                    text: "Create an account"
                    fillColor: "#3F3F46"
                    onClicked: root.switchMode("signup")
                }
                AppButton {
                    Layout.fillWidth: true
                    visible: root.mode === "signin"
                    enabled: !authService.busy
                    text: "Forgot password?"
                    fillColor: "#27272A"
                    onClicked: root.switchMode("recover")
                }
                AppButton {
                    Layout.fillWidth: true
                    visible: root.mode === "signin" || root.mode === "verify"
                    enabled: authService.configured && !authService.busy
                    text: root.mode === "verify" ? "Resend verification code" : "Verify an existing account"
                    fillColor: "#27272A"
                    onClicked: authService.resendConfirmation(emailField.text)
                }
                AppButton {
                    Layout.fillWidth: true
                    visible: root.mode === "reset"
                    enabled: authService.configured && !authService.busy
                    text: "Send a new reset code"
                    fillColor: "#27272A"
                    onClicked: authService.sendPasswordReset(emailField.text)
                }
                AppButton {
                    Layout.fillWidth: true
                    visible: root.mode !== "signin"
                    enabled: !authService.busy
                    text: "Back to sign in"
                    fillColor: "#27272A"
                    onClicked: root.switchMode("signin")
                }
            }
        }
    }
}
