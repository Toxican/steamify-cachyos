#!/bin/bash
# SteamOS look for GNOME, the counterpart of lib/vapor-theme.sh: the Vapor
# palette from CachyOS's cachyos-vapor package (also the Steam Deck
# wallpapers), as dark mode, a blue accent, the wallpaper and libadwaita/GTK4
# colors. Settings go through gsettings and its undo journal (lib/state.sh).
# Sourced by steamify.sh; not meant to be run on its own.

GNOME_THEME_MARK="/* Steamify GNOME theme */"
GNOME_THEME_CSS="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/gtk.css"
# The Ubuntu-style look: the dock (Ubuntu Dock is Dash to Dock) and our own extension,
# Steamify Vapor, which carries the shell colors (its stylesheet.css) and starts GNOME on
# the desktop. (Desktop Icons NG and AppIndicator come with the conversion, lib/desktop-shortcut.sh.)
GNOME_THEME_EXTENSIONS=(ubuntu-dock@ubuntu.com tiling-assistant@ubuntu.com steamify-vapor@steamify.github.io)
# Ubuntu's own builds, the ones Ubuntu 26.04 ships (they are the more mature): Ubuntu Dock from its source tag
# (built here: needs make, sassc and gettext) and Tiling Assistant (Ubuntu maintains it now) from its release.
DOCK_URL="https://github.com/micheleg/dash-to-dock/archive/refs/tags/ubuntu-dock-109ubuntu2.tar.gz"
DOCK_SHA256=599057fa27d922d4730bfc27c803b1b14b05f49a20e580e154e151b8481e5d41
TILING_URL="https://github.com/ubuntu/Tiling-Assistant/releases/download/v56/tiling-assistant@leleat-on-github.shell-extension.zip"
TILING_SHA256=961da0c6b8e5960770e68a06d71205765870435dbe8fe0ccc1ec50d4cc78265a
GNOME_USER_EXTENSIONS="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
GNOME_THEME_WALLPAPER="/usr/share/wallpapers/Steam Deck Logo Default.jpg"
# GNOME Settings with the "GNOME Desktop" panel (dock, desktop icons, tiling): built by GitHub Actions on current Arch
# and rebuilt weekly (steamify-gnome-theme, settings/), so it isn't compiled here (a few minutes, 800 steps).
GNOME_SETTINGS_PKG=steamify-gnome-control-center
GNOME_SETTINGS_URL="https://github.com/theupriser/steamify-gnome-theme/releases/download/settings"

gnometheme_status() {
    grep -qsF "$GNOME_THEME_MARK" "$GNOME_THEME_CSS"
}

gnometheme_extensions_install() {
    # Ubuntu Dock and Tiling Assistant (pinned downloads, checked) and our own Steamify Vapor, in the user's own extensions folder.
    local file work dir
    dir="$GNOME_USER_EXTENSIONS/ubuntu-dock@ubuntu.com"
    if [[ ! -f "$dir/metadata.json" ]]; then
        file="$(mktemp --suffix=.tar.gz)"; work="$(mktemp -d)"
        sudo pacman -S --needed --noconfirm make sassc gettext >/dev/null 2>&1
        if curl -fsSL --max-time 60 "$DOCK_URL" -o "$file" && [[ "$(sha256sum < "$file")" == "$DOCK_SHA256  -" ]] &&
            tar xzf "$file" -C "$work" --strip-components=1 &&
            make -C "$work" install-local INSTALLBASE="$GNOME_USER_EXTENSIONS" >/dev/null 2>&1; then
            :
        else
            warn "Couldn't set up Ubuntu Dock; the dock stays off."
        fi
        rm -rf "$file" "$work"
    fi
    dir="$GNOME_USER_EXTENSIONS/tiling-assistant@ubuntu.com"
    if [[ ! -f "$dir/metadata.json" ]]; then
        file="$(mktemp --suffix=.zip)"
        if curl -fsSL --max-time 60 "$TILING_URL" -o "$file" && [[ "$(sha256sum < "$file")" == "$TILING_SHA256  -" ]]; then
            rm -rf "$dir"; mkdir -p "$dir"
            python3 -c 'import sys,zipfile;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$file" "$dir"
            # Under the name Ubuntu gives it (GNOME Settings' desktop panel looks for it).
            sed -i 's|"uuid": "tiling-assistant@leleat-on-github"|"uuid": "tiling-assistant@ubuntu.com"|' "$dir/metadata.json"
            glib-compile-schemas "$dir/schemas" 2>/dev/null
        else
            warn "Couldn't download Tiling Assistant; it stays off."
        fi
        rm -f "$file"
    fi
    # GNOME Settings' Desktop panel finds the settings of the dock and of tiling in the default schema folders.
    local schemas="${XDG_DATA_HOME:-$HOME/.local/share}/glib-2.0/schemas" ext
    mkdir -p "$schemas"
    for ext in ubuntu-dock@ubuntu.com tiling-assistant@ubuntu.com; do
        cp "$GNOME_USER_EXTENSIONS/$ext"/schemas/*.gschema.xml "$schemas/" 2>/dev/null
    done
    glib-compile-schemas "$schemas" 2>/dev/null
    dir="$GNOME_USER_EXTENSIONS/steamify-vapor@steamify.github.io"
    mkdir -p "$dir"
    patch_file steamify-vapor.js > "$dir/extension.js"
    patch_file steamify-vapor.json > "$dir/metadata.json"
    patch_file steamify-gnome-shell.css > "$dir/stylesheet.css"
}

gnometheme_backgrounds() {
    # The SteamOS wallpapers of cachyos-vapor in GNOME Settings' background list: its XML list in the user's folder.
    local xml="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-background-properties/steamify-steamos.xml" f name
    mkdir -p "$(dirname "$xml")"
    {
        printf '%s\n' '<?xml version="1.0"?>' '<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">' '<wallpapers>'
        for f in /usr/share/wallpapers/*.jpg; do
            [[ -f "$f" ]] || continue
            name="$(basename "$f" .jpg)"
            printf '  <wallpaper deleted="false">\n    <name>SteamOS: %s</name>\n    <filename>%s</filename>\n    <filename-dark>%s</filename-dark>\n    <options>zoom</options>\n    <pcolor>#24272c</pcolor>\n    <scolor>#24272c</scolor>\n    <shade_type>solid</shade_type>\n  </wallpaper>\n' "$name" "$f" "$f"
        done
        echo '</wallpapers>'
    } > "$xml"
}

gnometheme_shell() {
    # The top bar and dash colors (the Steamify Vapor extension), and the dock beside it.
    gnometheme_extensions_install
    gnometheme_backgrounds
    # Like Ubuntu's dock: on the left, always there; its look is Ubuntu's own, left as it is. Its shape (a
    # panel to the screen edge or floating) is left to the user: Dock Settings.
    local d=org.gnome.shell.extensions.dash-to-dock
    gset gnometheme $d dock-position "'LEFT'" || true
    gset gnometheme $d dock-fixed true || true
    gset gnometheme $d running-indicator-style "'DOTS'" || true
    gset gnometheme $d click-action "'minimize-or-previews'" || true
    # Trash is in the dock, not on the desktop (Ubuntu does the same).
    gset gnometheme org.gnome.shell.extensions.ding show-trash false || true
    gset gnometheme $d show-trash true || true
    local uuid enabled
    for uuid in "${GNOME_THEME_EXTENSIONS[@]}"; do
        enabled="$(gs get org.gnome.shell enabled-extensions 2>/dev/null)" || return 0
        [[ "$enabled" == *"$uuid"* ]] && continue
        if [[ "$enabled" == "@as []" || "$enabled" == "[]" ]]; then enabled="['$uuid']"
        else enabled="${enabled%]}, '$uuid']"; fi
        gset gnometheme org.gnome.shell enabled-extensions "$enabled"
    done
}

gnometheme_relogin_needed() {
    # A GNOME session is running and this run changed the theme: GNOME Shell on Wayland can't be restarted in place, so
    # the new extensions, the dock and the Settings panel show after the user logs in again.
    [[ " $* " == *" gnometheme "* ]] && pgrep -u "$(id -u)" -x gnome-shell >/dev/null 2>&1
}

gnometheme_relogin() {
    # End the GNOME session. With GDM autologin set up by the conversion, steamify-gdm-relogin logs the user straight back
    # into the session they were in (GDM takes it from AccountsService; the session is not changed here, unlike
    # steamos-session-select, which would make GNOME the one gaming mode's boot goes back to). Without that helper there
    # is no autologin: a plain logout, and the user logs in again.
    local helper=/usr/local/libexec/steamify-gdm-relogin
    if [[ -x "$helper" ]] && sudo -n "$helper" "${XDG_SESSION_DESKTOP:-gnome}"; then return 0; fi
    gnome-session-quit --logout --no-prompt
}

gnometheme_settings_install() {
    # The prebuilt GNOME Settings with the Desktop panel, replacing the stock one. Never fatal: the theme works without the
    # panel, so a failed download or install keeps the stock Settings and says so.
    pacman -Q "$GNOME_SETTINGS_PKG" >/dev/null 2>&1 && return 0
    pacman -Q gnome-control-center >/dev/null 2>&1 || return 0
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/steamify" file="$GNOME_SETTINGS_PKG-x86_64.pkg.tar.zst" want got
    mkdir -p "$cache" || return 0
    info "Downloading GNOME Settings with the Desktop panel..."
    want="$(curl -fsL --connect-timeout 10 --max-time 30 "$GNOME_SETTINGS_URL/$file.sha256" 2>/dev/null | awk 'NR==1 {print $1}')"
    if [[ -z "$want" ]] ||
        ! curl -fsL --retry 2 --connect-timeout 15 --max-time 300 -o "$cache/$file.part" "$GNOME_SETTINGS_URL/$file"; then
        rm -f "$cache/$file.part"
        warn "Couldn't download GNOME Settings with the Desktop panel: the stock GNOME Settings stays."
        return 0
    fi
    got="$(sha256sum "$cache/$file.part" | awk '{print $1}')"
    if [[ "$got" != "$want" ]]; then
        rm -f "$cache/$file.part"
        warn "GNOME Settings with the Desktop panel didn't match its checksum: the stock GNOME Settings stays."
        return 0
    fi
    mv -f "$cache/$file.part" "$cache/$file"
    # --ask 4: pacman may replace the stock gnome-control-center it conflicts with.
    if sudo pacman -U --noconfirm --ask 4 "$cache/$file"; then
        state_set gnometheme installed_settings 1
        ok "GNOME Settings with the Desktop panel installed (under Appearance, after the next login)."
    else
        warn "Installing GNOME Settings with the Desktop panel failed (its libraries may differ from this PC's): the stock GNOME Settings stays."
    fi
    return 0
}

gnometheme_enable() {
    if ! pacman -Q cachyos-vapor >/dev/null 2>&1; then
        info "Installing cachyos-vapor (its wallpapers and colors)..."
        sudo pacman -S --needed --noconfirm cachyos-vapor || { err "Installing cachyos-vapor failed."; return 1; }
        # Only remove it again on disable if we were the ones installing it.
        state_set gnometheme installed_pkg 1
    fi
    info "Applying the SteamOS look to GNOME..."
    gset gnometheme org.gnome.desktop.interface color-scheme "'prefer-dark'"
    gset gnometheme org.gnome.desktop.interface accent-color "'blue'" || true
    # adw-gtk3 follows the light/dark style of Settings > Appearance (CachyOS's adw-gtk3-dark would pin it dark).
    [[ -d /usr/share/themes/adw-gtk3 ]] && gset gnometheme org.gnome.desktop.interface gtk-theme "'adw-gtk3'"
    # Windows with minimize and maximize buttons, like Ubuntu (GNOME shows only close by default).
    gset gnometheme org.gnome.desktop.wm.preferences button-layout "'appmenu:minimize,maximize,close'" || true
    if [[ -f "$GNOME_THEME_WALLPAPER" ]]; then
        local uri="file://${GNOME_THEME_WALLPAPER// /%20}"
        gset gnometheme org.gnome.desktop.background picture-uri "'$uri'"
        gset gnometheme org.gnome.desktop.background picture-uri-dark "'$uri'" || true
        gset gnometheme org.gnome.desktop.background picture-options "'zoom'"
    fi
    # GTK4/libadwaita apps ignore GTK themes: their colors come from this file.
    mkdir -p "$(dirname "$GNOME_THEME_CSS")"
    if [[ -f "$GNOME_THEME_CSS" ]] && ! gnometheme_status; then
        cp -a "$GNOME_THEME_CSS" "$STATE_DIR/gnometheme-gtk4.css"
    fi
    { echo "$GNOME_THEME_MARK"; patch_file steamify-gnome-gtk4.css; } > "$GNOME_THEME_CSS"
    gnometheme_shell
    gnometheme_settings_install
    ok "SteamOS theme for GNOME on (apps pick up the colors when they start again)."
    # (GNOME Shell on Wayland can't restart in place: the app offers "Restart GNOME", which is this.)
    gnometheme_relogin_needed gnometheme && info "Log out and back in for the dock, the extensions and the Settings panel to show."
}

gnometheme_disable() {
    info "Restoring GNOME's previous look..."
    grevert gnometheme
    # (The Dock/Desktop Icons/Tiling Settings launchers of earlier prototypes.)
    rm -f "${XDG_DATA_HOME:-$HOME/.local/share}"/applications/steamify-{dock,icons,tiling}-settings.desktop \
        "${XDG_DATA_HOME:-$HOME/.local/share}/gnome-background-properties/steamify-steamos.xml"
    # The schemas of the dock and of tiling that were copied next to the user's own for GNOME Settings' panel
    # (gnometheme_extensions_install): they go with the extensions, or settings schemas of nothing are left behind.
    local schemas="${XDG_DATA_HOME:-$HOME/.local/share}/glib-2.0/schemas" ext f
    for ext in ubuntu-dock@ubuntu.com tiling-assistant@ubuntu.com; do
        for f in "$GNOME_USER_EXTENSIONS/$ext"/schemas/*.gschema.xml; do
            [[ -e "$f" ]] && rm -f "$schemas/$(basename "$f")"
        done
    done
    # (Also by name: the extension folders may be gone already.)
    rm -f "$schemas"/org.gnome.shell.extensions.{dash-to-dock,tiling-assistant}.gschema.xml
    if compgen -G "$schemas/*.gschema.xml" >/dev/null; then glib-compile-schemas "$schemas" 2>/dev/null
    else rm -f "$schemas/gschemas.compiled"; rmdir "$schemas" 2>/dev/null; fi
    rm -rf "$GNOME_USER_EXTENSIONS/steamify-vapor@steamify.github.io" "$GNOME_USER_EXTENSIONS/ubuntu-dock@ubuntu.com" "$GNOME_USER_EXTENSIONS/tiling-assistant@ubuntu.com"
    if [[ -f "$STATE_DIR/gnometheme-gtk4.css" ]]; then
        mv -f "$STATE_DIR/gnometheme-gtk4.css" "$GNOME_THEME_CSS"
    else
        gnometheme_status && rm -f "$GNOME_THEME_CSS"
    fi
    if [[ -n "$(state_get gnometheme installed_pkg)" ]]; then
        # Fails, and stays installed, when the KDE theme or another package needs it.
        sudo pacman -R --noconfirm cachyos-vapor >/dev/null 2>&1 ||
            info "Keeping cachyos-vapor installed (another package needs it)."
    fi
    if [[ -n "$(state_get gnometheme installed_settings)" ]]; then
        # The stock GNOME Settings back (it conflicts with, and so replaces, ours).
        sudo pacman -S --noconfirm --ask 4 gnome-control-center >/dev/null 2>&1 ||
            info "Keeping GNOME Settings with the Desktop panel (the stock one couldn't be installed)."
    fi
    state_clear gnometheme
    ok "Previous GNOME look restored."
}
