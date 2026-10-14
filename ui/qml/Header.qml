// Logo, the screen's name (the version on the menu) and the machine.
import QtQuick

Rectangle {
    required property AppState app
    required property string iconUrl
    // Our own window frame (GNOME): drag the header, double-click to maximize, and the buttons at the right.
    property bool customFrame: false
    readonly property var titles: ({ review: "Review", password: "Password", applying: app.biosRun ? "BIOS update" : "Applying",
                                     done: "Done", bios1: "BIOS update", bios2: "BIOS update" })
    width: parent.width; height: 72; color: Theme.bar
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    Row {
        anchors.left: parent.left; anchors.leftMargin: 40; anchors.verticalCenter: parent.verticalCenter; spacing: 14
        Image { source: iconUrl; width: 40; height: 40; sourceSize: Qt.size(80, 80); anchors.verticalCenter: parent.verticalCenter }
        Text { text: "Steamify"; color: Theme.text; font.family: Theme.display; font.pixelSize: 28; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
        Text { readonly property bool menu: app.screen === "menu"
               text: menu ? "v" + (app.status.version || "") : "/ " + titles[app.screen]
               color: Theme.faint; font.family: menu ? Theme.mono : Theme.body; font.pixelSize: menu ? 13 : 15; anchors.verticalCenter: parent.verticalCenter }
    }
    Rectangle {
        visible: app.status.steamMachine === true
        anchors.right: parent.right; anchors.rightMargin: customFrame ? 190 : 40; anchors.verticalCenter: parent.verticalCenter
        height: 34; radius: 17; color: "#1b2330"; width: mt.implicitWidth + 28
        Text { id: mt; anchors.centerIn: parent; text: "Steam Machine · CachyOS"; color: Theme.label; font.family: Theme.body; font.pixelSize: 14 }
    }
    // Moving the window (and maximizing by double-click) is the part of the header left of the buttons.
    Item {
        visible: customFrame
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: controls.left }
        DragHandler { target: null; onActiveChanged: if (active) Window.window.startSystemMove() }
        TapHandler { onDoubleTapped: Window.window.visibility === Window.Maximized ? Window.window.showNormal() : Window.window.showMaximized() }
    }
    Row {
        id: controls
        visible: customFrame
        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 6
        Repeater {
            model: [ { g: "\u2013", a: "min" }, { g: "\u25a1", a: "max" }, { g: "\u2715", a: "close" } ]
            Rectangle {
                required property var modelData
                width: 44; height: 44; radius: 22
                color: area.containsMouse ? (modelData.a === "close" ? "#c0392b" : Theme.line) : "transparent"
                Text { anchors.centerIn: parent; text: modelData.g; color: Theme.text; font.family: Theme.body; font.pixelSize: 20 }
                MouseArea {
                    id: area
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var w = Window.window
                        if (modelData.a === "min") w.showMinimized()
                        else if (modelData.a === "max") { if (w.visibility === Window.Maximized) w.showNormal(); else w.showMaximized() }
                        else Qt.quit()
                    }
                }
            }
        }
    }
}
