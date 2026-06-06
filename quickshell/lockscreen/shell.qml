// lockscreen/shell.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam

ShellRoot {

    // ── Colors (inlined from PanelColors/Colors — no imports available) ──
    readonly property color clrBg:      "#212121"
    readonly property color clrBgAlt:   "#424242"
    readonly property color clrFg:      "#ffffffdd"
    readonly property color clrFgDim:   "#616161"
    readonly property color clrAccent:  "#80cbc4"   // teal200
    readonly property color clrBorder:  "#424242"   // grey800
    readonly property color clrUrgent:  "#ef9a9a"   // red200
    readonly property color clrClock:   "#ffffffdd" // PanelColors.clock (dark)
    readonly property color clrPillFg:  "#212121"   // PanelColors.pillForeground (dark)
    readonly property string fontMain:  "JetBrainsMono Nerd Font"
    readonly property int radiusLarge:  12
    readonly property int radiusMed:    8

    // Resolved once at startup; Quickshell.env() reads the process environment.
    readonly property string currentUser: Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user"

    WlSessionLock {
        id: sessionLock
        locked: true  // declarative is cleaner than Component.onCompleted

        WlSessionLockSurface {
            id: lockSurface

            // ── PAM ─────────────────────────────────────────────────────
            PamContext {
                id: pam
                config: "login"
                // Best Practice: Explicitly bind the user property to avoid ambiguity
                user: currentUser

                onCompleted: result => {
                    if (result === PamResult.Success) {
                        fadeOutAnim.start()
                    } else {
                        passwordField.text = ""
                        passwordField.forceActiveFocus()
                        shakeAnim.start()
                    }
                }

                onError: error => {
                    passwordField.text = ""
                    passwordField.forceActiveFocus()
                    shakeAnim.start()
                }

                onPamMessage: {
                    // BUG FIX: Explicitly read pam.responseRequired
                    // Otherwise it evaluates to undefined, and the password is never sent.
                    if (pam.responseRequired) {
                        pam.respond(passwordField.text)
                    }
                }
            }

            // ── Solid Base ───────────────────────────────────────────────
            // This prevents the compositor from flashing white when the UI fades out.
            Rectangle {
                id: windowBase
                anchors.fill: parent
                color: "black" // Always opaque

                // ── Fading Content Surface ───────────────────────────────
                Item {
                    id: rootSurface
                    anchors.fill: parent
                    opacity: 0 // Start fully transparent for the fade-in

                    // ── Fade Animations ──────────────────────────────────
                    NumberAnimation {
                        id: fadeInAnim
                        target: rootSurface
                        property: "opacity"
                        to: 1
                        duration: 400
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        id: fadeOutAnim
                        target: rootSurface
                        property: "opacity"
                        to: 0
                        duration: 400
                        easing.type: Easing.InCubic
                        onFinished: {
                            sessionLock.locked = false
                            Qt.quit()
                        }
                    }

                    // Background color fallback
                    Rectangle {
                        anchors.fill: parent
                        color: clrBg
                    }

                    // Wallpaper
                    Image {
                        anchors.fill: parent
                        source: "file://" + Quickshell.env("HOME") + "/.config/quickshell/lockscreen/wallpaper.png"
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready

                        Rectangle {
                            anchors.fill: parent
                            color: "black"
                            opacity: 0.2
                        }
                    }

                    // ── Top Center Bar (clock pill + lock icon) ──────────
                    Item {
                        id: topBar
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 10
                        height: 40
                        width: topBarInner.implicitWidth + 12

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: clrBg
                            opacity: 0.85
                        }

                        Row {
                            id: topBarInner
                            anchors.centerIn: parent
                            spacing: 6

                            // Clock pill
                            Rectangle {
                                id: clockPill
                                height: 28
                                width: clockPillRow.implicitWidth + 16
                                radius: 5
                                color: clrClock

                                Row {
                                    id: clockPillRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    // Analog clock canvas
                                    Canvas {
                                        id: clockCanvas
                                        width: 16
                                        height: 16
                                        antialiasing: true
                                        anchors.verticalCenter: parent.verticalCenter

                                        property var timeDate: new Date()

                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            ctx.clearRect(0, 0, width, height)
                                            var cx = width / 2
                                            var cy = height / 2
                                            var r  = width / 2 - 1
                                            ctx.strokeStyle = clrPillFg
                                            ctx.lineWidth = 2
                                            ctx.beginPath()
                                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                                            ctx.stroke()
                                            var h = timeDate.getHours() % 12
                                            var m = timeDate.getMinutes()
                                            var mAngle = m * (Math.PI * 2 / 60) - Math.PI / 2
                                            ctx.beginPath(); ctx.lineWidth = 1.5; ctx.lineCap = "round"
                                            ctx.moveTo(cx, cy)
                                            ctx.lineTo(cx + Math.cos(mAngle) * (r - 2.5), cy + Math.sin(mAngle) * (r - 2.5))
                                            ctx.stroke()
                                            var hAngle = (h + m / 60) * (Math.PI * 2 / 12) - Math.PI / 2
                                            ctx.beginPath(); ctx.lineWidth = 1.75; ctx.lineCap = "round"
                                            ctx.moveTo(cx, cy)
                                            ctx.lineTo(cx + Math.cos(hAngle) * (r - 4.0), cy + Math.sin(hAngle) * (r - 4.0))
                                            ctx.stroke()
                                        }
                                    }

                                    Text {
                                        id: clockText
                                        text: Qt.formatTime(clockCanvas.timeDate, "HH:mm")
                                        font.pixelSize: 16
                                        font.bold: true
                                        font.family: fontMain
                                        color: clrPillFg
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    // Lock icon pill
                                    Text {
                                        text: ""
                                        font.family: fontMain
                                        font.pixelSize: 14
                                        color: clrPillFg
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Timer {
                                    interval: 60000
                                    running: true
                                    repeat: true
                                    onTriggered: {
                                        clockCanvas.timeDate = new Date()
                                        clockCanvas.requestPaint()
                                    }
                                }
                            }
                        }
                    }

                    // ── Auth Card ─────────────────────────────────────────
                    Rectangle {
                        id: card
                        anchors.centerIn: parent
                        width: 360
                        height: cardLayout.implicitHeight + 48
                        radius: radiusLarge
                        color: clrBg
                        border.width: 4
                        border.color: passwordField.activeFocus && !shakeAnim.running ? clrAccent : clrBorder

                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; from: 0;   to: 10;  duration: 50; easing.type: Easing.OutQuad }
                            NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; from: 10;  to: -10; duration: 50; easing.type: Easing.OutQuad }
                            NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; from: -10; to: 10;  duration: 50; easing.type: Easing.OutQuad }
                            NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; from: 10;  to: 0;   duration: 50; easing.type: Easing.OutQuad }
                        }

                        ColumnLayout {
                            id: cardLayout
                            anchors.centerIn: parent
                            width: parent.width - 48
                            spacing: 12

                            // ── User row ──────────────────────────────────
                            Rectangle {
                                Layout.fillWidth: true
                                height: 38
                                radius: radiusMed
                                color: clrBorder

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 12
                                    Text {
                                        text: ""
                                        font.family: fontMain
                                        font.pixelSize: 16
                                        color: clrAccent
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: currentUser
                                        font.pixelSize: 14
                                        font.bold: true
                                        font.family: fontMain
                                        color: clrAccent
                                    }
                                }
                            }

                            // ── Password field ────────────────────────────
                            Rectangle {
                                Layout.fillWidth: true
                                height: 40
                                radius: radiusMed
                                color: clrBgAlt
                                border.width: passwordField.activeFocus ? 3 : 0
                                border.color: clrAccent

                                Behavior on border.width { NumberAnimation { duration: 100 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 12

                                    Text {
                                        text: ""
                                        font.family: fontMain
                                        font.pixelSize: 16
                                        color: passwordField.activeFocus ? clrAccent : clrFgDim
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    TextInput {
                                        id: passwordField
                                        Layout.fillWidth: true
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: TextInput.Password
                                        passwordCharacter: "•"
                                        font.pixelSize: 14
                                        font.family: fontMain
                                        color: clrFg
                                        focus: true
                                        onAccepted: rootSurface.submitPassword()

                                        Text {
                                            anchors.fill: parent
                                            text: "Password..."
                                            verticalAlignment: Text.AlignVCenter
                                            font.pixelSize: 14
                                            font.family: fontMain
                                            color: clrFgDim
                                            visible: passwordField.text.length === 0 && !passwordField.activeFocus
                                        }
                                    }
                                }
                            }

                            // ── Login button ──────────────────────────────
                            Rectangle {
                                id: loginButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: radiusMed
                                color: loginMa.containsMouse ? Qt.lighter(clrAccent, 1.15) : clrAccent
                                scale: loginMa.containsMouse ? 1.03 : 1.0
                                transformOrigin: Item.Center
                                antialiasing: true

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutSine } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 12
                                    Text { text: "󰍂"; font.family: fontMain; font.pixelSize: 16; color: clrBg }
                                    Text { text: "Unlock"; font.family: fontMain; font.bold: true; font.pixelSize: 14; color: clrBg }
                                }

                                MouseArea {
                                    id: loginMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rootSurface.submitPassword()
                                }
                            }
                        }
                    }

                    // ── Submit logic ──────────────────────────────────────
                    function submitPassword() {
                        if (passwordField.text.length === 0) return
                        if (pam.active) return

                        if (!pam.start()) {
                            shakeAnim.start()
                        }
                    }

                    Component.onCompleted: {
                        passwordField.forceActiveFocus()
                        fadeInAnim.start()
                    }
                }
            }
        }
    }
}
