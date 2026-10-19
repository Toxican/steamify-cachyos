#!/bin/bash
# The desktop shortcut that switches to gaming mode: "Return to Gaming Mode"
# when the PC boots into gaming mode, "Switch to Gaming Mode" when it boots into
# the desktop (nothing to return to).
# Sourced by steamify.sh; not meant to be run on its own.

SHORTCUT_NAMES=("Return to Gaming Mode" "Switch to Gaming Mode")

shortcut_name() {
    # Follows "Boot into" (lib/boot-session.sh).
    if boot_status; then echo "Switch to Gaming Mode"; else echo "Return to Gaming Mode"; fi
}

shortcut_dir() { xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop"; }

refresh_desktop_shortcut() {
    # After "Boot into" changed: the shortcut is renamed to match.
    gaming_status && create_desktop_shortcut
    return 0
}

create_desktop_shortcut() {
    # Determine the home directory of the target user
    local user_home
    user_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

    # Locate the correct Desktop directory
    local desktop_dir
    if [[ -f "$user_home/.config/user-dirs.dirs" ]]; then
        desktop_dir=$(grep '^XDG_DESKTOP_DIR=' "$user_home/.config/user-dirs.dirs" | cut -d '"' -f 2)
        desktop_dir="${desktop_dir/\$HOME/$user_home}"
    fi
    desktop_dir="${desktop_dir:-$user_home/Desktop}"

    mkdir -p "$desktop_dir"

    # steamos-session-select writes the session and logs out; the login
    # manager logs in to it by itself (Relogin=true, or the relogin helper in
    # multi-user mode). Versions before 2.13.0 restarted the login manager,
    # with a sudoers rule that is removed now.
    local exec_line="steamos-session-select gamescope"
    sudo rm -f /etc/sudoers.d/gamescope-session-switch

    # SteamOS itself uses Valve's "gaming-return" icon (Steam logo with a
    # return arrow; the Deck-style arrow is only used on Steam Deck
    # hardware). The theme installs it (lib/steamos-extras.sh) and updates
    # the shortcut via set_shortcut_icon; without it, use Steam's icon.
    local shortcut_icon="steam"
    [[ -f /usr/local/share/icons/hicolor/scalable/actions/gaming-return.svg ]] &&
        shortcut_icon="gaming-return"

    # 2. Generate the .desktop shortcut with instant session switcher strings
    local name n shortcut_path
    name="$(shortcut_name)"
    shortcut_path="$desktop_dir/$name.desktop"
    for n in "${SHORTCUT_NAMES[@]}"; do [[ "$n" == "$name" ]] || rm -f "$desktop_dir/$n.desktop"; done
    info "Creating '$name' desktop shortcut at: $shortcut_path"

    cat << EOF > "$shortcut_path"
[Desktop Entry]
Name=$name
Comment=Switch session to Gamescope
Exec=$exec_line
Icon=$shortcut_icon
Terminal=false
Type=Application
Categories=System;
EOF

    # Fix permissions for the target user and KDE Plasma desktop ecosystem
    chmod +x "$shortcut_path"

    ok "Desktop shortcut created successfully."
}

set_shortcut_icon() {
    # set_shortcut_icon <icon>: update an existing shortcut, if any.
    local n
    for n in "${SHORTCUT_NAMES[@]}"; do
        [[ -f "$(shortcut_dir)/$n.desktop" ]] && sed -i "s/^Icon=.*/Icon=$1/" "$(shortcut_dir)/$n.desktop"
    done
    return 0
}

remove_desktop_shortcut() {
    local n
    for n in "${SHORTCUT_NAMES[@]}"; do rm -f "$(shortcut_dir)/$n.desktop"; done
    sudo rm -f /etc/sudoers.d/gamescope-session-switch
}
