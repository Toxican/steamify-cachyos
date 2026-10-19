// The result of a run: all done, a problem, or nothing changed. With a
// problem, the run's output is shown below it (a BIOS check has no progress
// screen, so this is the only place to read why it stopped).
import QtQuick
import QtQuick.Controls.Basic

Item {
    required property AppState app
    readonly property bool problem: app.failed.length > 0 || app.runError !== ""
    // GNOME Shell on Wayland can't restart in place (it is the compositor too), so what a KDE run does for plasmashell is a
    // new login here: started by itself after a countdown, unless the run needs a reboot anyway (which does the same).
    readonly property bool relogin: app.reloginNeeded && !app.restartNeeded && !problem
    property int countdown: 10
    property bool cancelled: false
    property bool fired: false
    readonly property bool counting: relogin && !cancelled && !fired
    onVisibleChanged: if (visible) { countdown = 10; cancelled = false; fired = false; }
    function reloginNow() { fired = true; app.backend.restartGnome(); }
    Timer {
        interval: 1000; repeat: true; running: parent.visible && parent.counting
        onTriggered: { parent.countdown -= 1; if (parent.countdown <= 0) parent.reloginNow(); }
    }
    readonly property string message: {
        if (app.runError) return app.runError;
        if (!app.biosRun) return app.plan.length + (app.plan.length === 1 ? " change" : " changes") + " applied." + (app.restartNeeded ? " Some take effect after a restart." : "")
             + (counting ? " Restarting GNOME in " + countdown + " s, so it loads the new dock, extensions and Settings panel."
                : (relogin ? " GNOME shows the dock, extensions and Settings panel after you log in again." : ""));
        if (app.failed.length) return "The BIOS was not changed.";
        return (app.bios && app.bios.dryRun ? "Dry run: nothing was flashed. " : "BIOS " + (app.biosInfo.newest || "") + " is staged and is written during the restart. ")
             + "Keep the power on and don't touch the machine until it has fully started again, even if the screen stays black.";
    }
    Column {
        anchors.centerIn: parent; width: 760; spacing: 20
        Rectangle { width: 72; height: 72; radius: 36; anchors.horizontalCenter: parent.horizontalCenter; color: problem ? Theme.warnBg : Theme.goodBg
            Text { anchors.centerIn: parent; text: problem ? "!" : "✓"; color: problem ? Theme.warn : Theme.good; font.pixelSize: 36; font.weight: Font.Bold } }
        Text { text: app.runError ? "Nothing changed" : (app.biosRun && app.failed.length ? "The BIOS update stopped" : (app.failed.length ? "Done, with a problem" : "All done"))
               color: Theme.text; font.family: Theme.display; font.pixelSize: 40; font.weight: Font.DemiBold; anchors.horizontalCenter: parent.horizontalCenter }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.soft; font.family: Theme.body; font.pixelSize: 17; text: message }
        Rectangle { visible: app.failed.length > 0; anchors.horizontalCenter: parent.horizontalCenter; width: ft.implicitWidth + 32; height: 44; radius: 12; color: Theme.warnBg
            Text { id: ft; anchors.centerIn: parent; color: "#f2c27a"; font.family: Theme.body; font.pixelSize: 14
                   text: "Had a problem: " + app.failed.map(function (id) { return Texts.label(id); }).join(", ") + (app.log.count ? ". Details below." : ".") } }
        Rectangle { visible: app.failed.length > 0 && app.log.count > 0; width: parent.width; height: 190; radius: 14; color: Theme.card
            ListView { id: details; anchors.fill: parent; anchors.margins: 16; clip: true; model: app.log
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                // The end is where it stopped.
                onCountChanged: positionViewAtEnd()
                onVisibleChanged: if (visible) positionViewAtEnd()
                delegate: Text { required property string line; width: details.width - 12; text: line; color: "#aab5c4"; font.family: Theme.mono; font.pixelSize: 13; wrapMode: Text.WrapAnywhere } } }
        Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 14; topPadding: 8
            Btn { k: Input.g.back; text: "Back to the menu"; height: 52; onClicked: app.act("back") }
            Btn { visible: app.restartNeeded; k: Input.g.ok; text: "Restart now"; primary: true; height: 52; onClicked: app.backend.restart() }
            Btn { visible: relogin; k: Input.g.ok; text: counting ? "Restart GNOME now" : "Restart GNOME"; primary: true; height: 52; onClicked: reloginNow() }
            Btn { visible: counting; text: "Cancel"; height: 52; onClicked: cancelled = true } }
    }
}
