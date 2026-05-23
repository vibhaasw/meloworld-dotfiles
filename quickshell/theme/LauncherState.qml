pragma Singleton
import QtQuick
import Quickshell

// ── LauncherState ─────────────────────────────────────────────────────────────
// Manages the open/close state of the app launcher.
// Placed in the theme module so SessionState (and bar widgets) can reach it
// without any circular dependency.
Singleton {
    property bool visible: false

    function toggle() { visible = !visible }
    function show()   { visible = true      }
    function hide()   { visible = false     }
}
