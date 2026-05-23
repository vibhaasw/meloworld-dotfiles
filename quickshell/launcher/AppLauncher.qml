import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../theme"

// ── AppLauncher ───────────────────────────────────────────────────────────────
// A floating, centered app launcher window.
//
// Architecture:
//   • PanelWindow spans the full screen (Overlay layer, exclusiveZone 0).
//   • A Region mask restricts pointer input to only the launcher panel, so
//     clicks outside the panel pass straight through to the compositor.
//   • The panel Rectangle is positioned slightly above centre (mirroring the
//     COSMIC launcher aesthetic) and animates in with a slide-up + fade.
//   • animState mirrors the pattern used in PopupBase ("closed"/"open"/"closing").
//   • Super+A must be bound in the compositor — see the keybind comment below.
//
PanelWindow {
    id: root

    // ── Layer-shell setup ────────────────────────────────────────────────────
    anchors.top:    true
    anchors.bottom: true
    anchors.left:   true
    anchors.right:  true
    exclusiveZone:  0

    WlrLayershell.layer:         WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    color:   "transparent"
    // Keep the window alive through the close animation so it can play fully.
    visible: animState !== "closed"

    // Only the panel rect receives pointer events; clicks outside pass through.
    mask: Region { item: panel }

    // ── Animation state machine ──────────────────────────────────────────────
    // Follows the exact same "closed/open/closing" contract as PopupBase so the
    // rest of the shell can treat this consistently.
    property string animState: "closed"
    
    // Tracks the currently focused app index for keyboard navigation
    property int selectedIndex: 0

    // Updates the selection to the first visible app when searching
    function updateSelection() {
        for (var i = 0; i < appsRepeater.count; i++) {
            var item = appsRepeater.itemAt(i)
            if (item && item.isMatch) {
                selectedIndex = i
                return
            }
        }
        selectedIndex = -1
    }

    Connections {
        target: LauncherState
        function onVisibleChanged() {
            root.animState = LauncherState.visible ? "open" : "closing"
            
            // Reset state when opening
            if (LauncherState.visible) {
                searchInput.text = ""
                appGrid.contentY = 0
                root.selectedIndex = 0
            }
        }
    }

    // Forward focus to the search field once the panel is fully in "open" state.
    onAnimStateChanged: {
        if (animState === "open") searchInput.forceActiveFocus()
    }

    // ── IPC Handler ──────────────────────────────────────────────────────────
    IpcHandler {
        target: "launcher"
        function toggle(): void {
            LauncherState.toggle()
        }
    }

    // ── Super+A keybind ──────────────────────────────────────────────────────
    // Add the following to your compositor config to bind Super+A:
    //
    //   Miracle WM / Hyprland:
    //     bind = SUPER, a, exec, qs ipc call launcher toggle
    //
    //   Niri (~/.config/niri/config.kdl):
    //     binds { Mod+A { action spawn "sh" "-c" "qs ipc call launcher toggle" } }
    //

    // ── Panel ────────────────────────────────────────────────────────────────
    Rectangle {
        id: panel

        // Design dimensions
        readonly property int panelWidth: 600

        width:  panelWidth
        height: panelColumn.implicitHeight + 20

        // Perfectly centered
        x: Math.round((parent.width  - width)  / 2)
        y: Math.round((parent.height - height) / 2)

        radius:       12
        color:        PanelColors.popupBackground
        Behavior on color { ColorAnimation { duration: PanelColors.transitionDuration } }

        border.color: PanelColors.border
        Behavior on border.color { ColorAnimation { duration: PanelColors.transitionDuration } }
        border.width: 4

        clip: false

        // ── Animation targets ────────────────────────────────────────────────
        opacity: 0.0
        transform: Translate { id: panelSlide; y: 28 }

        // ── States ───────────────────────────────────────────────────────────
        states: [
            State {
                name: "open"
                when: root.animState === "open"
                PropertyChanges { target: panel;      opacity: 1.0 }
                PropertyChanges { target: panelSlide; y: 0         }
            },
            State {
                name: "closing"
                when: root.animState === "closing"
                PropertyChanges { target: panel;      opacity: 0.0 }
                PropertyChanges { target: panelSlide; y: 28        }
            }
        ]

        transitions: [
            // ── Slide up + fade in ───────────────────────────────────────────
            Transition {
                to: "open"
                SequentialAnimation {
                    // Snap to the offset start position before beginning the
                    // animation so reopening always plays from the same origin.
                    PropertyAction { target: panelSlide; property: "y";       value: 28  }
                    PropertyAction { target: panel;      property: "opacity"; value: 0.0 }
                    ParallelAnimation {
                        NumberAnimation {
                            target: panelSlide; property: "y"
                            to: 0;   duration: 280; easing.type: Easing.OutExpo
                        }
                        NumberAnimation {
                            target: panel; property: "opacity"
                            to: 1.0; duration: 200; easing.type: Easing.OutCubic
                        }
                    }
                }
            },
            // ── Slide down + fade out ────────────────────────────────────────
            Transition {
                to: "closing"
                SequentialAnimation {
                    ParallelAnimation {
                        NumberAnimation {
                            target: panelSlide; property: "y"
                            to: 28; duration: 180; easing.type: Easing.InCubic
                        }
                        NumberAnimation {
                            target: panel; property: "opacity"
                            to: 0.0; duration: 150; easing.type: Easing.InCubic
                        }
                    }
                    // Flip the root window off once the animation finishes.
                    ScriptAction { script: root.animState = "closed" }
                }
            }
        ]

        // ── Content layout ───────────────────────────────────────────────────
        Column {
            id: panelColumn
            anchors {
                top:     parent.top
                left:    parent.left
                right:   parent.right
                margins: 10
            }
            spacing: 8

            // ── Search bar ───────────────────────────────────────────────────
            Rectangle {
                id:     searchBar
                width:  parent.width
                height: 44
                radius: 8

                color: PanelColors.rowBackground
                Behavior on color { ColorAnimation { duration: PanelColors.transitionDuration } }

                border.color: searchInput.activeFocus ? PanelColors.launcher : "transparent"
                Behavior on border.color { ColorAnimation { duration: 150 } }
                border.width: 0

                // Search field + manual placeholder overlay
                Item {
                    anchors {
                        fill:       parent
                        leftMargin: 12
                        rightMargin: 12
                    }

                    // Placeholder text (visible only when the field is empty)
                    Text {
                        anchors.fill: parent
                        text:             " Search..."
                        font.pixelSize:   13
                        font.bold:        true
                        font.family:      "JetBrainsMono Nerd Font"
                        color:            PanelColors.textDim
                        verticalAlignment: Text.AlignVCenter
                        visible:          searchInput.text === ""
                    }

                    TextInput {
                        id:            searchInput
                        anchors.fill:  parent
                        color:         PanelColors.textMain
                        font.pixelSize: 13
                        font.bold:     true
                        font.family:   "JetBrainsMono Nerd Font"
                        selectByMouse: true
                        clip:          true
                        verticalAlignment: TextInput.AlignVCenter

                        onTextChanged: root.updateSelection()

                        Keys.onReturnPressed: {
                            if (root.selectedIndex !== -1) {
                                var item = appsRepeater.itemAt(root.selectedIndex)
                                if (item) item.executeApp()
                            }
                        }
                        Keys.onEscapePressed: LauncherState.hide()
                    }
                }
            }
            // ── App Grid ─────────────────────────────────────────────────────
            Flickable {
                id:             appGrid
                width:          parent.width
                height:         360
                contentHeight:  flowLayout.implicitHeight
                clip:           true
                boundsBehavior: Flickable.StopAtBounds

                Flow {
                    id:       flowLayout
                    width:    parent.width
                    spacing:  8

                    Repeater {
                        id: appsRepeater
                        model: DesktopEntries.applications

                        delegate: Rectangle {
                            id: delegateRect
                            
                            // Filtering logic: hide items that don't match the search
                            property bool isMatch: searchInput.text === "" || modelData.name.toLowerCase().includes(searchInput.text.toLowerCase())
                            
                            visible: isMatch
                            width:   isMatch ? 108 : 0
                            height:  isMatch ? 104 : 0
                            radius:  12

                            property bool isSelected: root.selectedIndex === index

                            // Dock hover logic (auto-applied if selected via keyboard)
                            color: (isSelected || rowMouse.containsMouse) ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            function executeApp() {
                                modelData.execute()
                                LauncherState.hide()
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 8

                                // App Icon
                                IconImage {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    implicitSize: 48
                                    source:       Quickshell.iconPath(modelData.icon)
                                    
                                    // Dock hover scaling
                                    scale: (delegateRect.isSelected || rowMouse.containsMouse) ? 1.1 : 1.0
                                    Behavior on scale {
                                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                    }
                                }

                                // App Name
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text:                   modelData.name
                                    font.pixelSize:         12
                                    font.bold:              true
                                    font.family:            "JetBrainsMono Nerd Font"
                                    color:                  PanelColors.textMain
                                    width:                  100
                                    horizontalAlignment:    Text.AlignHCenter
                                    elide:                  Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor

                                onEntered: root.selectedIndex = index
                                onClicked: delegateRect.executeApp()
                            }
                        }
                    }
                }
            }
        }

        // Escape anywhere on the panel also closes.
        Keys.onEscapePressed: LauncherState.hide()
        focus: true
    }
}
