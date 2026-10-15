// Steamify v2: the window. The state and logic are in AppState.qml, each
// screen in its own file (menu -> review -> password -> applying -> done,
// and the BIOS warnings). Designed at 1280x720 and scaled to the window, so
// it fits a TV too.
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic

ApplicationWindow {
    id: win
    required property var backend
    required property var gamepad
    required property bool fullscreen
    // The app draws the window frame (GNOME): the header carries the buttons, the edges resize.
    required property bool customFrame
    required property string iconUrl
    required property bool fromSteam
    Component.onCompleted: Input.fromSteam = fromSteam

    width: 1280; height: 720
    minimumWidth: 960; minimumHeight: 540
    flags: customFrame ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window
    visibility: fullscreen ? Window.FullScreen : Window.Windowed
    title: "Steamify"
    color: Theme.bg

    AppState {
        id: steamify
        backend: win.backend
        gamepad: win.gamepad
        // Keys go back to the screen when a text field's screen closes.
        onScreenChanged: if (screen !== "password" && screen !== "bios2") stage.forceActiveFocus()
    }

    // The 1280x720 stage, scaled to the window: stretched to the window's
    // own shape, so the bars reach the edges and the content fills it.
    Item {
        id: stage
        // On a desktop (a window, however large) the UI keeps the desktop's own scale: 1 here is one logical pixel, which Qt
        // multiplies by the scale of GNOME or KDE, like any other app (a 1440p or ultrawide monitor would otherwise show
        // everything twice as big). Only a window smaller than the layout shrinks it. The TV mode (--fullscreen, gamescope)
        // scales to the screen: it is read from the couch.
        readonly property real k: Math.min(win.width / 1280, win.height / 720, win.fullscreen ? Infinity : 1)
        width: win.width / k; height: win.height / k
        transformOrigin: Item.TopLeft
        scale: k
        focus: true
        Keys.onPressed: function (e) { steamify.keyPressed(e); }
        Keys.onReleased: function (e) { steamify.keyReleased(e); }

        Header { id: header; app: steamify; iconUrl: win.iconUrl; customFrame: win.customFrame }

        Item {
            id: content
            anchors.top: header.bottom; anchors.bottom: parent.bottom; width: parent.width
            MenuScreen { anchors.fill: parent; app: steamify; visible: steamify.screen === "menu" }
            ReviewScreen { anchors.fill: parent; app: steamify; visible: steamify.screen === "review" }
            PasswordScreen { anchors.fill: parent; app: steamify; visible: steamify.screen === "password" }
            ApplyingScreen { anchors.fill: parent; app: steamify; visible: steamify.screen === "applying" }
            BiosWarningScreen { anchors.fill: parent; app: steamify; visible: steamify.screen === "bios1" }
            BiosConfirmScreen { anchors.fill: parent; app: steamify; visible: steamify.screen === "bios2" }
            DoneScreen { anchors.fill: parent; app: steamify; visible: steamify.screen === "done" }
        }
    }

    // Resize handles around a window with our own frame.
    component Edge: MouseArea {
        required property int edges
        hoverEnabled: true
        onPressed: win.startSystemResize(edges)
    }
    Edge { visible: win.customFrame; edges: Qt.LeftEdge; width: 6; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 8; bottomMargin: 8 } cursorShape: Qt.SizeHorCursor }
    Edge { visible: win.customFrame; edges: Qt.RightEdge; width: 6; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 8; bottomMargin: 8 } cursorShape: Qt.SizeHorCursor }
    Edge { visible: win.customFrame; edges: Qt.TopEdge; height: 6; anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 } cursorShape: Qt.SizeVerCursor }
    Edge { visible: win.customFrame; edges: Qt.BottomEdge; height: 6; anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 } cursorShape: Qt.SizeVerCursor }
    Edge { visible: win.customFrame; edges: Qt.LeftEdge | Qt.TopEdge; width: 8; height: 8; anchors { left: parent.left; top: parent.top } cursorShape: Qt.SizeFDiagCursor }
    Edge { visible: win.customFrame; edges: Qt.RightEdge | Qt.TopEdge; width: 8; height: 8; anchors { right: parent.right; top: parent.top } cursorShape: Qt.SizeBDiagCursor }
    Edge { visible: win.customFrame; edges: Qt.LeftEdge | Qt.BottomEdge; width: 8; height: 8; anchors { left: parent.left; bottom: parent.bottom } cursorShape: Qt.SizeBDiagCursor }
    Edge { visible: win.customFrame; edges: Qt.RightEdge | Qt.BottomEdge; width: 8; height: 8; anchors { right: parent.right; bottom: parent.bottom } cursorShape: Qt.SizeFDiagCursor }
}
