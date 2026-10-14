#!/bin/bash
# "Return to Gaming Mode" desktop shortcut and the sudoers rule it needs.
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

    # On SDDM, steamos-session-select logging out is enough: Relogin=true
    # logs straight back in to the newly selected session, like SteamOS.
    # plasma-login-manager needs the sync bridge run and a restart, which
    # the shortcut can't sudo for interactively (Terminal=false), so it gets
    # a password-less rule scoped to exactly those two commands.
    local exec_line="steamos-session-select gamescope"
    if [[ "$LOGIN_MANAGER" == "gdm" ]]; then
        # Its own steamos-session-select (lib/login-manager.sh) restarts GDM, through the helper and rule gdm_fix_install adds.
        :
    elif [[ "$LOGIN_MANAGER" == "plasmalogin" ]]; then
        exec_line="sh -c 'steamos-session-select gamescope && sudo -n /usr/bin/systemctl start sync-steamos-session.service && sudo -n /usr/bin/systemctl restart plasmalogin'"
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
    else
        sudo rm -f /etc/sudoers.d/gamescope-session-switch
    fi
    # GNOME shows no icons on the desktop: the application grid gets the shortcut too.
    gnome_app_shortcut=false
    [[ "$(desktop_kind)" == gnome ]] && gnome_app_shortcut=true

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
    if [[ "$gnome_app_shortcut" == true ]]; then
        mkdir -p "$user_home/.local/share/applications"
        cp "$shortcut_path" "$user_home/.local/share/applications/steamify-return-to-gaming-mode.desktop"
        # GNOME only starts launchers it trusts.
        gio set "$shortcut_path" metadata::trusted true 2>/dev/null || true
        gnome_dash_pin
        gnome_extensions_enable
    fi

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
    rm -f "$desktop_dir/Return to Gaming Mode.desktop" "$HOME/.local/share/applications/steamify-return-to-gaming-mode.desktop"
    gnome_dash_unpin
    sudo rm -f /etc/sudoers.d/gamescope-session-switch
}

# GNOME draws no icons on the desktop: the shortcut is pinned to the dash
# (the favorites bar) as well. Only in a running session (gsettings needs its dconf).
GNOME_SHORTCUT_ID=steamify-return-to-gaming-mode.desktop

gnome_dash_pin() {
    user_session && command -v gsettings >/dev/null || return 0
    local favorites
    favorites="$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)" || return 0
    [[ "$favorites" == *"$GNOME_SHORTCUT_ID"* ]] && return 0
    favorites="$(sed "s/\]\$/, '$GNOME_SHORTCUT_ID']/; s/^\[, /[/; s/\[\], /[/" <<< "$favorites")"
    [[ "$favorites" == "[ '$GNOME_SHORTCUT_ID']" ]] && favorites="['$GNOME_SHORTCUT_ID']"
    gsettings set org.gnome.shell favorite-apps "$favorites"
}

gnome_dash_unpin() {
    user_session && command -v gsettings >/dev/null || return 0
    local favorites
    favorites="$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)" || return 0
    [[ "$favorites" == *"$GNOME_SHORTCUT_ID"* ]] || return 0
    favorites="$(sed -e "s/, '$GNOME_SHORTCUT_ID'//; s/'$GNOME_SHORTCUT_ID', //; s/'$GNOME_SHORTCUT_ID'//" <<< "$favorites")"
    gsettings set org.gnome.shell favorite-apps "$favorites"
}

# GNOME draws no desktop icons and no tray icons (Steam's, for one) itself:
# the Desktop Icons NG and AppIndicator extensions, installed with the other
# GNOME packages (lib/packages.sh). Enabled in the user's settings; GNOME
# loads a new extension at the next login.
GNOME_EXTENSIONS=(ding@rastersoft.com appindicatorsupport@rgcjonas.gmail.com)

gnome_extensions_enable() {
    user_session && command -v gsettings >/dev/null || return 0
    local uuid enabled
    for uuid in "${GNOME_EXTENSIONS[@]}"; do
        [[ -d "/usr/share/gnome-shell/extensions/$uuid" ]] || continue
        enabled="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)" || return 0
        [[ "$enabled" == *"$uuid"* ]] && continue
        if [[ "$enabled" == "@as []" || "$enabled" == "[]" ]]; then enabled="['$uuid']"
        else enabled="${enabled%]}, '$uuid']"; fi
        gsettings set org.gnome.shell enabled-extensions "$enabled"
    done
}
