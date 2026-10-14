#!/bin/bash
# Which desktop Steamify is running on (KDE Plasma or GNOME), and the
# session the login manager has to start for it. GNOME (GDM) is a prototype.
# Sourced by steamify.sh; not meant to be run on its own.

desktop_kind() {
    # gnome or kde: the running session first, else what the login manager
    # is (GDM means GNOME), else KDE, which Steamify was made for.
    case ":${STEAMIFY_DESKTOP:-${XDG_CURRENT_DESKTOP:-}}:" in
        *:GNOME:*|*:gnome:*) echo gnome; return ;;
        *:KDE:*|*:kde:*) echo kde; return ;;
    esac
    [[ "$(current_display_manager)" == gdm ]] && { echo gnome; return; }
    echo kde
}

desktop_session_file() {
    # The login manager's session entry for the desktop: plasma.desktop, or
    # whichever GNOME one is installed (gnome.desktop, gnome-xorg.desktop).
    local f
    if [[ "$(desktop_kind)" == gnome ]]; then
        # The plain session, not GNOME Classic (gnome-classic.desktop, from gnome-shell-extensions) or Xorg's.
        for f in /usr/share/wayland-sessions/gnome.desktop /usr/share/xsessions/gnome.desktop \
            /usr/share/wayland-sessions/gnome-wayland.desktop; do
            [[ -f "$f" ]] && { basename "$f"; return; }
        done
        echo gnome.desktop
    else
        echo plasma.desktop
    fi
}

choose_login_manager() {
    # LOGIN_MANAGER for gaming_enable. With KDE and GNOME both installed the active login
    # manager stays (switching it would be a surprise); otherwise gdm on GNOME, sddm with
    # single user mode and plasmalogin without.
    local current
    current="$(current_display_manager)"
    if desktop_installed gnome && desktop_installed kde; then
        case "$current" in gdm|sddm|plasmalogin) LOGIN_MANAGER="$current"; return ;; esac
    fi
    if [[ "$(desktop_kind)" == gnome ]]; then LOGIN_MANAGER=gdm
    elif [[ "${WANTED[single]:-0}" == 1 ]]; then LOGIN_MANAGER=sddm
    else LOGIN_MANAGER=plasmalogin; fi
}

# Which desktop "Switch to Desktop" (and booting into the desktop) goes to when both are
# installed: kde, gnome, or last (the one you left for gamescope). Read by the session tool.
DESKTOP_PREF_FILE=/etc/steamify/desktop

desktop_pref_get() {
    cat "$DESKTOP_PREF_FILE" 2>/dev/null || echo last
}

desktop_pref_set() {
    printf '%s\n' "$1" | sudo install -Dm644 /dev/stdin "$DESKTOP_PREF_FILE"
}

desktop_installed() {
    # desktop_installed kde|gnome: its session is installed (both can be: the
    # menu then offers the theme of each).
    local name=plasma f
    [[ "$1" == gnome ]] && name=gnome
    for f in /usr/share/wayland-sessions/$name*.desktop /usr/share/xsessions/$name*.desktop; do
        [[ -f "$f" ]] && return 0
    done
    return 1
}
