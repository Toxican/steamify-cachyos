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

shortcut_user_home() { getent passwd "$TARGET_USER" | cut -d: -f6; }

shortcut_desktop_dir() {
    # The target user's Desktop folder, from their user-dirs.dirs.
    local user_home desktop_dir
    user_home="$(shortcut_user_home)"
    if [[ -f "$user_home/.config/user-dirs.dirs" ]]; then
        desktop_dir=$(grep '^XDG_DESKTOP_DIR=' "$user_home/.config/user-dirs.dirs" | cut -d '"' -f 2)
        desktop_dir="${desktop_dir/\$HOME/$user_home}"
    fi
    echo "${desktop_dir:-$user_home/Desktop}"
}

refresh_desktop_shortcut() {
    # After "Boot into" changed: the shortcut is renamed to match.
    gaming_status && create_desktop_shortcut
    return 0
}

create_desktop_shortcut() {
    local user_home desktop_dir
    user_home="$(shortcut_user_home)"
    desktop_dir="$(shortcut_desktop_dir)"
    mkdir -p "$desktop_dir"

    # steamos-session-select writes the session and logs out; the login
    # manager logs in to it by itself (Relogin=true, or the relogin helper in
    # multi-user mode). Versions before 2.13.0 restarted the login manager,
    # with a sudoers rule that is removed now.
    local exec_line="steamos-session-select gamescope"
    if [[ "$LOGIN_MANAGER" == "gdm" ]]; then
        # Its own steamos-session-select (lib/login-manager.sh) restarts GDM, through the helper and rule gdm_fix_install adds.
        :
    else
        sudo rm -f /etc/sudoers.d/gamescope-session-switch
    fi
    # GNOME shows no icons on the desktop: the application grid gets the shortcut too.
    local gnome_app_shortcut=false
    [[ "$(desktop_kind)" == gnome ]] && gnome_app_shortcut=true

    # SteamOS itself uses Valve's "gaming-return" icon (Steam logo with a
    # return arrow; the Deck-style arrow is only used on Steam Deck
    # hardware). The theme installs it (lib/steamos-extras.sh) and updates
    # the shortcut via set_shortcut_icon; without it, use Steam's icon.
    local shortcut_icon="steam"
    [[ -f /usr/local/share/icons/hicolor/scalable/actions/gaming-return.svg ]] &&
        shortcut_icon="gaming-return"

    local name n shortcut_path
    name="$(shortcut_name)"
    shortcut_path="$desktop_dir/$name.desktop"
    for n in "${SHORTCUT_NAMES[@]}"; do [[ "$n" == "$name" ]] || rm -f "$desktop_dir/$n.desktop"; done
    info "Creating '$name' desktop shortcut at: $shortcut_path"

    # Written with its mode already set: Plasma opens a desktop icon it first
    # saw non-executable in an editor.
    install_executable "$shortcut_path" 755 << EOF
[Desktop Entry]
Name=$name
Comment=Switch session to Gamescope
Exec=$exec_line
Icon=$shortcut_icon
Terminal=false
Type=Application
Categories=System;
EOF

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
    local n dir
    dir="$(shortcut_desktop_dir)"
    for n in "${SHORTCUT_NAMES[@]}"; do
        [[ -f "$dir/$n.desktop" ]] && sed -i "s/^Icon=.*/Icon=$1/" "$dir/$n.desktop"
    done
    return 0
}

remove_desktop_shortcut() {
    local n dir
    dir="$(shortcut_desktop_dir)"
    for n in "${SHORTCUT_NAMES[@]}"; do rm -f "$dir/$n.desktop"; done
    rm -f "$(shortcut_user_home)/.local/share/applications/$GNOME_SHORTCUT_ID"
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
