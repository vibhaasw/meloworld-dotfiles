import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."
import "../theme"

PanelWindow {
    id: dock

    anchors.bottom: true
    anchors.left:   true
    anchors.right:  true

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayershell.Top
    color: "transparent"

    readonly property int margin:     8
    readonly property int pillHeight: 64
    readonly property int fullHeight: pillHeight + margin * 2
    implicitHeight: fullHeight

    mask: Region {
        item: dockVisible ? pill : triggerStrip
    }

    // ── State ──────────────────────────────────────────────────────────────
    property bool hovering:    false
    property bool anyMenuOpen: false

    readonly property bool dockVisible: !windowsPresent || hovering || anyMenuOpen

    // ── Niri IPC: track windows on the focused workspace ──────────────────
    //
    // Strategy: open a persistent Socket to $NIRI_SOCKET, subscribe to the
    // event stream, and maintain two JS objects as lookup tables:
    //   focusedWorkspaceId  — the ID of the currently focused workspace
    //   windowWorkspaceMap  — { windowId: workspaceId } for all open windows
    //
    // windowsPresent becomes true when at least one entry in windowWorkspaceMap
    // has a workspaceId matching focusedWorkspaceId.
    //
    // The event stream sends the full current state as the first batch of
    // events on connect, so there is no need for a separate query.

    property int    focusedWorkspaceId: -1
    property var    windowWorkspaceMap: ({})

    readonly property bool windowsPresent: {
        const id = dock.focusedWorkspaceId
        if (id < 0) return false
        const map = dock.windowWorkspaceMap
        for (const wid in map) {
            if (map[wid] === id) return true
        }
        return false
    }

    Socket {
        id: niriSocket

        // $NIRI_SOCKET is set by niri in every process it launches.
        readonly property string socketPath: Quickshell.env("NIRI_SOCKET")

        path: socketPath
        connected: socketPath !== ""

        // As soon as the connection is established, subscribe to the event stream.
        onConnectedChanged: {
            if (connected) {
                niriSocket.write('"EventStream"\n')
            } else {
                // Socket dropped — retry after a short delay.
                reconnectTimer.start()
            }
        }

        parser: SplitParser {
            onRead: (line) => {
                const trimmed = line.trim()
                if (trimmed.length === 0) return
                try {
                    dock.handleNiriEvent(JSON.parse(trimmed))
                } catch (e) {
                    console.warn("DockWidget: JSON parse error:", e, "raw:", trimmed)
                }
            }
        }
    }

    Timer {
        id: reconnectTimer
        interval: 1000
        onTriggered: niriSocket.connected = niriSocket.socketPath !== ""
    }

    function handleNiriEvent(ev) {
        // Each niri event is a JSON object with a single top-level key
        // naming the event type.  Examples:
        //   {"WorkspacesChanged":{"workspaces":[...]}}
        //   {"WorkspaceActivated":{"id":3,"focused":true}}
        //   {"WindowsChanged":{"windows":[...]}}
        //   {"WindowOpenedOrChanged":{"window":{...}}}
        //   {"WindowClosed":{"id":42}}

        if (ev["WorkspacesChanged"] !== undefined) {
            // Full workspace list — find the one that is both active and focused.
            const ws = ev["WorkspacesChanged"]["workspaces"]
            for (let i = 0; i < ws.length; i++) {
                if (ws[i]["is_focused"]) {
                    dock.focusedWorkspaceId = ws[i]["id"]
                    break
                }
            }

        } else if (ev["WorkspaceActivated"] !== undefined) {
            // Incremental update — only update if this workspace gained focus.
            const data = ev["WorkspaceActivated"]
            if (data["focused"]) {
                dock.focusedWorkspaceId = data["id"]
            }

        } else if (ev["WindowsChanged"] !== undefined) {
            // Full window list — rebuild the map from scratch.
            const wins = ev["WindowsChanged"]["windows"]
            const map = {}
            for (let i = 0; i < wins.length; i++) {
                const w = wins[i]
                if (w["workspace_id"] !== undefined) {
                    map[w["id"]] = w["workspace_id"]
                }
            }
            dock.windowWorkspaceMap = map

        } else if (ev["WindowOpenedOrChanged"] !== undefined) {
            // A single window was opened or moved — surgical map update.
            const w = ev["WindowOpenedOrChanged"]["window"]
            if (w["workspace_id"] !== undefined) {
                const map = Object.assign({}, dock.windowWorkspaceMap)
                map[w["id"]] = w["workspace_id"]
                dock.windowWorkspaceMap = map
            }

        } else if (ev["WindowClosed"] !== undefined) {
            // A window was closed — remove it from the map.
            const id = ev["WindowClosed"]["id"]
            const map = Object.assign({}, dock.windowWorkspaceMap)
            delete map[id]
            dock.windowWorkspaceMap = map
        }
    }

    // ── Hide debounce ──────────────────────────────────────────────────────
    Timer {
        id: hideTimer
        interval: 300
        onTriggered: dock.hovering = false
    }

    // ── Trigger strip ──────────────────────────────────────────────────────
    Item {
        id: triggerStrip
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        height: 4

        HoverHandler {
            onHoveredChanged: {
                if (hovered) { hideTimer.stop(); dock.hovering = true }
                else hideTimer.restart()
            }
        }
    }

    // ── Pill ───────────────────────────────────────────────────────────────
    Item {
        id: pill

        x: (parent.width - width) / 2
        width:  row.implicitWidth + dock.margin * 2
        height: dock.pillHeight

        readonly property real restingY: parent.height - dock.pillHeight - dock.margin
        readonly property real hiddenY:  parent.height + dock.margin
        y: dock.dockVisible ? restingY : hiddenY

        Behavior on y {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }

        opacity: dock.dockVisible ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            color:        PanelColors.barBackground
            Behavior on color { ColorAnimation { duration: PanelColors.transitionDuration } }
            radius:       10
            border.color: PanelColors.border
            Behavior on border.color { ColorAnimation { duration: PanelColors.transitionDuration } }
            border.width: 3
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 6

            Repeater {
                model: PinnedApps.apps
                AppIcon {
                    appId:    modelData.id
                    appLabel: modelData.label
                    iconName: modelData.icon
                    steamId:  modelData.steamId  ?? ""
                    execName: modelData.execName ?? ""
                }
            }
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) { hideTimer.stop(); dock.hovering = true }
                else hideTimer.restart()
            }
        }
    }
}
