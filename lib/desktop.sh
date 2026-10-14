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
        for f in /usr/share/wayland-sessions/gnome*.desktop /usr/share/xsessions/gnome*.desktop; do
            [[ -f "$f" ]] && { basename "$f"; return; }
        done
        echo gnome.desktop
    else
        echo plasma.desktop
    fi
}

choose_login_manager() {
    # LOGIN_MANAGER for gaming_enable: gdm on GNOME, else sddm with single
    # user mode and plasmalogin without.
    if [[ "$(desktop_kind)" == gnome ]]; then LOGIN_MANAGER=gdm
    elif [[ "${WANTED[single]:-0}" == 1 ]]; then LOGIN_MANAGER=sddm
    else LOGIN_MANAGER=plasmalogin; fi
}
