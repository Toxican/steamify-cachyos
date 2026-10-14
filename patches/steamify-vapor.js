// Steamify Vapor (Steamify GNOME theme). Its stylesheet.css, which GNOME Shell loads
// by itself, is the SteamOS look. This code: GNOME opens the overview after login;
// Ubuntu starts on the desktop. So does this: the overview stays closed while the
// shell starts up, and is available again right after.
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class SteamifyDesktopStart extends Extension {
    enable() {
        if (!Main.layoutManager._startingUp)
            return;
        this._hadOverview = Main.sessionMode.hasOverview;
        Main.sessionMode.hasOverview = false;
        this._startupId = Main.layoutManager.connect('startup-complete', () => {
            Main.sessionMode.hasOverview = this._hadOverview;
            Main.overview.hide();
        });
    }

    disable() {
        if (this._startupId) {
            Main.layoutManager.disconnect(this._startupId);
            this._startupId = null;
        }
        if (this._hadOverview !== undefined)
            Main.sessionMode.hasOverview = this._hadOverview;
    }
}
