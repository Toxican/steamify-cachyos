#!/bin/bash
# "Return to Gaming Mode" desktop shortcut.
# Sourced by steamify.sh; not meant to be run on its own.

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
    local shortcut_path="$desktop_dir/Return to Gaming Mode.desktop"
    info "Creating 'Return to Gaming Mode' desktop shortcut at: $shortcut_path"

    cat << EOF > "$shortcut_path"
[Desktop Entry]
Name=Return to Gaming Mode
Comment=Switch session back to Gamescope
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
    local shortcut
    shortcut="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")/Return to Gaming Mode.desktop"
    [[ -f "$shortcut" ]] && sed -i "s/^Icon=.*/Icon=$1/" "$shortcut"
    return 0
}

remove_desktop_shortcut() {
    local desktop_dir
    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
    rm -f "$desktop_dir/Return to Gaming Mode.desktop"
    sudo rm -f /etc/sudoers.d/gamescope-session-switch
}
