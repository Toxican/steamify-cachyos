#!/bin/bash
# "Boot into: gamescope / desktop" menu item, on top of the SteamOS
# conversion. Gamescope is the default (the conversion's autologin, and
# CachyOS's cachyos-gamescope-autologin resetting to it after a desktop
# session). Desktop: a unit that sets the autologin session to Plasma at
# every boot, before the login manager starts. Switching between the two in
# a running system (Return to Gaming Mode, Steam's Switch to Desktop) works
# the same either way.
# Sourced by steamify.sh; not meant to be run on its own.

BOOT_UNIT_NAME="steamify-boot-desktop.service"
BOOT_UNIT="/etc/systemd/system/$BOOT_UNIT_NAME"

boot_status() {
    # On = boots into the desktop.
    [[ -f "$BOOT_UNIT" ]] && systemctl is-enabled -q "$BOOT_UNIT_NAME" 2>/dev/null
}

boot_desktop_arg() {
    # Our session tool (installed with GNOME) resolves "desktop" to the preferred desktop; CachyOS's own takes a session name.
    if [[ -f "$GDM_FIX_DIR/steam-set-session" ]]; then echo desktop; else echo plasma.desktop; fi
}

boot_enable() {
    info "Setting the PC to boot into the desktop..."
    service_file "$BOOT_UNIT_NAME" DESKTOP_SESSION="$(boot_desktop_arg)" | sudo tee "$BOOT_UNIT" > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable "$BOOT_UNIT_NAME" || { err "Enabling $BOOT_UNIT_NAME failed."; return 1; }
    ok "Boots into the desktop from the next boot on (the shortcut \"Switch to Gaming Mode\" goes to gaming mode)."
}

boot_disable() {
    info "Setting the PC to boot into gaming mode again..."
    best_effort sudo systemctl disable "$BOOT_UNIT_NAME"
    sudo rm -f "$BOOT_UNIT"
    sudo systemctl daemon-reload
    # Next boot into gamescope, as the conversion sets it up.
    sudo /usr/lib/steamos/steam-set-session gamescope-session.desktop
    ok "Boots into gaming mode from the next boot on."
}

boot_choice() {
    # The menu row: the chosen option in brackets.
    if [[ "$1" == 1 ]]; then
        echo "Boot into:  gamescope  [desktop]"
    else
        echo "Boot into: [gamescope]  desktop"
    fi
}
