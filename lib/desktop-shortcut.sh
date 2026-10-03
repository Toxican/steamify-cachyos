#!/bin/bash
# "Return to Gaming Mode" desktop shortcut and the sudoers rule it needs.
# Sourced by steamify.sh; not meant to be run on its own.

shortcut_desktop_dir() {
    # The target user's Desktop folder, from their user-dirs.dirs.
    local user_home desktop_dir
    user_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    if [[ -f "$user_home/.config/user-dirs.dirs" ]]; then
        desktop_dir=$(grep '^XDG_DESKTOP_DIR=' "$user_home/.config/user-dirs.dirs" | cut -d '"' -f 2)
        desktop_dir="${desktop_dir/\$HOME/$user_home}"
    fi
    echo "${desktop_dir:-$user_home/Desktop}"
}

shortcut_install_sudoers() {
    # plasma-login-manager needs the sync bridge run and a restart, which the
    # shortcut can't sudo for interactively (Terminal=false), so it gets a
    # password-less rule scoped to exactly those two commands.
    local sudoers_tmp
    sudoers_tmp="$(mktemp)"
    cat > "$sudoers_tmp" << EOF
$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/systemctl start sync-steamos-session.service, /usr/bin/systemctl restart plasmalogin
EOF
    if sudo visudo -cf "$sudoers_tmp" >/dev/null; then
        sudo install -m 0440 -o root -g root "$sudoers_tmp" /etc/sudoers.d/gamescope-session-switch
        ok "Installed /etc/sudoers.d/gamescope-session-switch for the shortcut."
    else
        warn "Generated sudoers rule failed validation; the shortcut will not be able to restart plasmalogin."
    fi
    rm -f "$sudoers_tmp"
}

create_desktop_shortcut() {
    local desktop_dir
    desktop_dir="$(shortcut_desktop_dir)"
    mkdir -p "$desktop_dir"

    # On SDDM, steamos-session-select logging out is enough: Relogin=true
    # logs straight back in to the newly selected session, like SteamOS.
    local exec_line="steamos-session-select gamescope"
    if [[ "$LOGIN_MANAGER" == "plasmalogin" ]]; then
        exec_line="sh -c 'steamos-session-select gamescope && sudo -n /usr/bin/systemctl start sync-steamos-session.service && sudo -n /usr/bin/systemctl restart plasmalogin'"
        shortcut_install_sudoers
    else
        sudo rm -f /etc/sudoers.d/gamescope-session-switch
    fi

    # SteamOS itself uses Valve's "gaming-return" icon (Steam logo with a
    # return arrow; the Deck-style arrow is only used on Steam Deck
    # hardware). The theme installs it (lib/steamos-extras.sh) and updates
    # the shortcut via set_shortcut_icon; without it, use Steam's icon.
    local shortcut_icon="steam"
    [[ -f /usr/local/share/icons/hicolor/scalable/actions/gaming-return.svg ]] &&
        shortcut_icon="gaming-return"

    local shortcut_path="$desktop_dir/Return to Gaming Mode.desktop"
    info "Creating 'Return to Gaming Mode' desktop shortcut at: $shortcut_path"
    # Written with its mode already set: Plasma opens a desktop icon it first
    # saw non-executable in an editor.
    install_executable "$shortcut_path" 755 << EOF
[Desktop Entry]
Name=Return to Gaming Mode
Comment=Switch session back to Gamescope
Exec=$exec_line
Icon=$shortcut_icon
Terminal=false
Type=Application
Categories=System;
EOF
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
