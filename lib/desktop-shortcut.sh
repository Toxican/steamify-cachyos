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

# The packages behind them. Needed by the SteamOS conversion (the desktop shortcut's icon, Steam's tray icon) and by the
# GNOME theme (its desktop and tray icons); a PC that has neither any more gets back what Steamify added.
GNOME_EXTRA_PKGS=(gnome-shell-extension-desktop-icons-ng gnome-shell-extension-appindicator extension-manager)

gnome_extras_note_missing() {
    # Before they are installed: which of them Steamify brings itself (the others were the user's: they stay), one name per
    # line in a file of its own, not a state value: kwriteconfig6 (kconfig) is one of the packages installed in that step.
    # Already noted ones stay noted (they are installed by then, so they aren't "missing" again).
    local p list="$STATE_DIR/gnomeextras.list"
    mkdir -p "$STATE_DIR"
    for p in "${GNOME_EXTRA_PKGS[@]}"; do
        pacman -Q "$p" >/dev/null 2>&1 || grep -qxF "$p" "$list" 2>/dev/null || echo "$p" >> "$list"
    done
}

gnome_extensions_disable() {
    # The two out of the user's list of enabled extensions again.
    user_session && command -v gsettings >/dev/null || return 0
    local uuid enabled
    for uuid in "${GNOME_EXTENSIONS[@]}"; do
        enabled="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)" || return 0
        [[ "$enabled" == *"$uuid"* ]] || continue
        enabled="$(sed -e "s/'$uuid', //; s/, '$uuid'//; s/'$uuid'//" <<<"$enabled")"
        [[ "$enabled" == "[]" ]] && enabled="@as []"
        gsettings set org.gnome.shell enabled-extensions "$enabled"
    done
}

gnome_extras_release() {
    # Called when the SteamOS conversion or the GNOME theme was turned off, after its own undoing. While the other one is
    # still on, the extensions stay (and are enabled again: the theme's undo puts back the list it found). When neither is:
    # they are disabled, and the packages Steamify installed are removed (a failed removal, because something else needs a
    # package, keeps it).
    [[ "$(desktop_kind)" == gnome ]] || return 0
    if gaming_status || gnometheme_status; then gnome_extensions_enable; return 0; fi
    gnome_extensions_disable
    local p list="$STATE_DIR/gnomeextras.list"
    for p in "${GNOME_EXTRA_PKGS[@]}"; do
        grep -qxF "$p" "$list" 2>/dev/null || continue
        pacman -Q "$p" >/dev/null 2>&1 || continue
        sudo pacman -R --noconfirm "$p" >/dev/null 2>&1 || info "Keeping $p installed (another package needs it)."
    done
    rm -f "$list"
}
