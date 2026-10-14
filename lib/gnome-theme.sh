#!/bin/bash
# SteamOS look for GNOME, the counterpart of lib/vapor-theme.sh: the Vapor
# palette from CachyOS's cachyos-vapor package (also the Steam Deck
# wallpapers), as dark mode, a blue accent, the wallpaper and libadwaita/GTK4
# colors. Settings go through gsettings and its undo journal (lib/state.sh).
# Sourced by steamify.sh; not meant to be run on its own.

GNOME_THEME_MARK="/* Steamify GNOME theme */"
GNOME_THEME_CSS="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/gtk.css"
GNOME_THEME_SHELL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/themes/SteamifyVapor/gnome-shell"
# The Ubuntu-style look: the dock (Ubuntu Dock is Dash to Dock) and the User
# Themes extension, which loads the shell theme. (Desktop Icons NG and
# AppIndicator come with the conversion, lib/desktop-shortcut.sh.)
GNOME_THEME_PACKAGES=(gnome-shell-extensions)
GNOME_THEME_EXTENSIONS=(user-theme@gnome-shell-extensions.gcampax.github.com dash-to-dock@micxgx.gmail.com
    steamify-desktop-start@steamify.github.io)
# CachyOS's dash-to-dock package (106) doesn't load on GNOME 51: upstream's release, from extensions.gnome.org's tag.
DOCK_URL="https://github.com/micheleg/dash-to-dock/releases/download/extensions.gnome.org-v110/dash-to-dock@micxgx.gmail.com.zip"
DOCK_SHA256=3e60680fe7217b905aac4f10deb042e39fcf49168c9b8fdcc5a711bdd49bd3d2
GNOME_USER_EXTENSIONS="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
GNOME_THEME_WALLPAPER="/usr/share/wallpapers/Steam Deck Logo Default.jpg"

gnometheme_status() {
    grep -qsF "$GNOME_THEME_MARK" "$GNOME_THEME_CSS"
}

gnometheme_extensions_install() {
    # The dock (pinned upstream release) and the start-on-the-desktop extension, in the user's own extensions folder.
    local zip dir="$GNOME_USER_EXTENSIONS/dash-to-dock@micxgx.gmail.com"
    if [[ ! -f "$dir/metadata.json" ]] || ! grep -q '"version": 110' "$dir/metadata.json"; then
        zip="$(mktemp --suffix=.zip)"
        if curl -fsSL --max-time 60 "$DOCK_URL" -o "$zip" && [[ "$(sha256sum < "$zip")" == "$DOCK_SHA256  -" ]]; then
            rm -rf "$dir"; mkdir -p "$dir"
            python3 -c 'import sys,zipfile;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$dir"
            glib-compile-schemas "$dir/schemas" 2>/dev/null
        else
            warn "Couldn't download the dock (Dash to Dock 110); it stays off."
        fi
        rm -f "$zip"
    fi
    dir="$GNOME_USER_EXTENSIONS/steamify-desktop-start@steamify.github.io"
    mkdir -p "$dir"
    patch_file steamify-desktop-start.js > "$dir/extension.js"
    patch_file steamify-desktop-start.json > "$dir/metadata.json"
}

gnometheme_shell() {
    # The top bar and dash colors: a shell theme, loaded by User Themes, and the dock beside it.
    sudo pacman -S --needed --noconfirm "${GNOME_THEME_PACKAGES[@]}" >/dev/null 2>&1 ||
        { warn "Couldn't install the dock and the shell theme extension; the colors of apps are set."; return 0; }
    gnometheme_extensions_install
    mkdir -p "$GNOME_THEME_SHELL_DIR"
    patch_file steamify-gnome-shell.css > "$GNOME_THEME_SHELL_DIR/gnome-shell.css"
    gset gnometheme org.gnome.shell.extensions.user-theme name "'SteamifyVapor'" || true
    # Like Ubuntu's dock: on the left, full height, always there, in Vapor's panel color.
    local d=org.gnome.shell.extensions.dash-to-dock
    gset gnometheme $d dock-position "'LEFT'" || true
    gset gnometheme $d extend-height true || true
    gset gnometheme $d dock-fixed true || true
    gset gnometheme $d transparency-mode "'FIXED'" || true
    gset gnometheme $d custom-background-color true || true
    gset gnometheme $d background-color "'#24272c'" || true
    gset gnometheme $d background-opacity 0.95 || true
    gset gnometheme $d running-indicator-style "'DOTS'" || true
    gset gnometheme $d custom-theme-shrink true || true
    local uuid enabled
    for uuid in "${GNOME_THEME_EXTENSIONS[@]}"; do
        enabled="$(gs get org.gnome.shell enabled-extensions 2>/dev/null)" || return 0
        [[ "$enabled" == *"$uuid"* ]] && continue
        if [[ "$enabled" == "@as []" || "$enabled" == "[]" ]]; then enabled="['$uuid']"
        else enabled="${enabled%]}, '$uuid']"; fi
        gset gnometheme org.gnome.shell enabled-extensions "$enabled"
    done
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
    gset gnometheme org.gnome.desktop.interface gtk-theme "'Vapor'" || true
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
    ok "SteamOS theme for GNOME on (apps pick up the colors when they start again)."
}

gnometheme_disable() {
    info "Restoring GNOME's previous look..."
    grevert gnometheme
    rm -rf "${GNOME_THEME_SHELL_DIR%/gnome-shell}" "$GNOME_USER_EXTENSIONS/steamify-desktop-start@steamify.github.io" \
        "$GNOME_USER_EXTENSIONS/dash-to-dock@micxgx.gmail.com"
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
    state_clear gnometheme
    ok "Previous GNOME look restored."
}
