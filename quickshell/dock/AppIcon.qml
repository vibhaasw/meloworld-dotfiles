import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../theme"

Item {
    id: root

    property string appId:    ""
    property string appLabel: ""
    property string iconName: ""
    property string steamId:  ""
    property string execName: ""

    implicitWidth:  56
    implicitHeight: 64

    HoverHandler { id: hover }

    // ── Hover background ───────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width:  48
        height: 48
        radius: 10
        color:  hover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    // ── App icon ───────────────────────────────────────────────────
    IconImage {
        id: icon
        anchors.centerIn: parent
        implicitSize: 40
        source: Quickshell.iconPath(root.iconName)

        scale: hover.hovered ? 1.1 : 1.0
        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    // ── Auto-dismiss: 3 s idle ─────────────────────────────────────
    Timer {
        id: dismissTimer
        interval: 3000
        running:  ctxMenu.isOpen
        onTriggered: {
            ctxMenu.closeMenu()
            DockState.close()
        }
    }

    // Dismiss when dock hides
    Connections {
        target: dock
        function onDockVisibleChanged() {
            if (!dock.dockVisible && ctxMenu.isOpen) {
                ctxMenu.closeMenu()
                DockState.close()
            }
        }
    }

    // Close when another icon opens its menu
    Connections {
        target: DockState
        function onCloseAll() {
            if (ctxMenu.isOpen)
                ctxMenu.closeMenu()
        }
    }

    // ── Mouse ──────────────────────────────────────────────────────
    MouseArea {
        anchors.fill:    parent
        cursorShape:     Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                if (ctxMenu.isOpen) {
                    ctxMenu.closeMenu()
                    DockState.close()
                } else {
                    DockState.openFor(root)
                    ctxMenu.openMenu()
                }
            } else {
                root._launchDefault()
            }
        }
    }

    // ── Launch helpers ─────────────────────────────────────────────
    function _launchDefault() {
        if (root.steamId !== "") {
            Quickshell.execDetached(["xdg-open", "steam://rungameid/" + root.steamId])
        } else {
            var entry = DesktopEntries.byId(root.appId)
            if (entry) entry.execute()
            else Quickshell.execDetached([root.appId])
        }
    }

    function _launchAltGpu() {
        var base = ["switcherooctl", "launch", "-g", String(DockState.nonDefaultGpuIndex)]
        var argv
        if (root.steamId !== "") {
            argv = base.concat(["steam", "-applaunch", root.steamId])
        } else {
            var bin = root.execName !== "" ? root.execName : root.appId
            argv = base.concat([bin])
        }
        Quickshell.execDetached(argv)
    }

    function _buildMenuModel() {
        var entries = [{ label: "Launch", alt: false }]
        if (DockState.gpuInfoReady && DockState.nonDefaultGpuName !== "")
            entries.push({ label: "Launch with " + DockState.nonDefaultGpuName, alt: true })
        return entries
    }

    // ── Context menu popup ─────────────────────────────────────────
    PopupWindow {
        id: ctxMenu

        anchor.item:           icon
        anchor.edges:          Edges.Top
        anchor.gravity:        Edges.Top
        anchor.margins.bottom: 8

        color:          "transparent"
        implicitWidth:  200
        implicitHeight: innerRect.implicitHeight

        visible: false
        property bool isOpen: false

        function openMenu() {
            menuRepeater.model = root._buildMenuModel()
            innerRect.y        = 14
            innerRect.opacity  = 0.0
            visible            = true
            isOpen             = true
            dock.anyMenuOpen   = true
            dock.hovering      = true
            openAnim.restart()
            dismissTimer.restart()
        }

        function closeMenu() {
            if (!isOpen) return
            isOpen = false
            openAnim.stop()
            closeAnim.restart()
        }

        SequentialAnimation {
            id: openAnim
            ParallelAnimation {
                NumberAnimation {
                    target: innerRect; property: "y"
                    to: 0; duration: 220; easing.type: Easing.OutExpo
                }
                NumberAnimation {
                    target: innerRect; property: "opacity"
                    to: 1.0; duration: 170; easing.type: Easing.OutCubic
                }
            }
        }

        SequentialAnimation {
            id: closeAnim
            ParallelAnimation {
                NumberAnimation {
                    target: innerRect; property: "y"
                    to: 14; duration: 160; easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: innerRect; property: "opacity"
                    to: 0.0; duration: 130; easing.type: Easing.InCubic
                }
            }
            ScriptAction {
                script: {
                    ctxMenu.visible  = false
                    dock.anyMenuOpen = false
                }
            }
        }

        mask: Region { item: innerRect }

        Rectangle {
            id: innerRect

            width:          parent.width
            implicitHeight: menuCol.implicitHeight + padding * 2
            height:         implicitHeight
            radius:         10
            color:          PanelColors.popupBackground
            border.color:   PanelColors.border
            border.width:   2
            clip:           true

            readonly property int padding: 12

            Behavior on color        { ColorAnimation { duration: PanelColors.transitionDuration } }
            Behavior on border.color { ColorAnimation { duration: PanelColors.transitionDuration } }

            // Keep the dismiss timer alive while the pointer is on the popup.
            // dock.anyMenuOpen already keeps the dock surface visible, so we
            // only need to manage the auto-dismiss here.
            HoverHandler {
                onHoveredChanged: {
                    if (hovered)
                        dismissTimer.restart()
                }
            }

            Column {
                id: menuCol
                anchors {
                    top:     parent.top
                    left:    parent.left
                    right:   parent.right
                    margins: innerRect.padding
                }
                spacing: 4

                Text {
                    width:          parent.width
                    text:           root.appLabel
                    font.pixelSize: 12
                    font.bold:      true
                    font.family:    "JetBrainsMono Nerd Font"
                    color:          PanelColors.textDim
                    bottomPadding:  4
                }

                Rectangle {
                    width:  parent.width
                    height: 2
                    color:  PanelColors.border
                }

                Repeater {
                    id: menuRepeater
                    model: []

                    delegate: Item {
                        required property var modelData
                        width:  menuCol.width
                        height: 34

                        Rectangle {
                            anchors.fill: parent
                            radius:       6
                            color: rowMouse.containsMouse
                                ? Qt.lighter(PanelColors.rowBackground, 1.15)
                                : PanelColors.rowBackground
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Rectangle {
                                width: 3; height: parent.height - 10; radius: 2
                                anchors {
                                    left:           parent.left
                                    leftMargin:     4
                                    verticalCenter: parent.verticalCenter
                                }
                                color: PanelColors.textDim
                            }

                            Text {
                                anchors {
                                    left:           parent.left
                                    leftMargin:     14
                                    right:          parent.right
                                    rightMargin:    10
                                    verticalCenter: parent.verticalCenter
                                }
                                text:           modelData.label
                                font.pixelSize: 13
                                font.bold:      true
                                font.family:    "JetBrainsMono Nerd Font"
                                color:          PanelColors.textMain
                                elide:          Text.ElideRight
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true

                                onContainsMouseChanged: {
                                    if (containsMouse) dismissTimer.restart()
                                }

                                onClicked: {
                                    var isAlt = modelData.alt
                                    ctxMenu.closeMenu()
                                    DockState.close()
                                    if (isAlt)
                                        root._launchAltGpu()
                                    else
                                        root._launchDefault()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
