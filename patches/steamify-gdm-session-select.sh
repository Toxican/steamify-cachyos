#!/bin/bash
# steamos-session-select for GDM (Steamify prototype): CachyOS's own ends the
# session with a KDE-only D-Bus call. GDM logs in by itself only when it
# starts, so after the new session is set the user is ended and GDM restarted
# (patches/steamify-gdm-relogin.sh): it then logs the autologin user straight into it.
set -e

DM_ID="$(systemctl show -p Id --value display-manager)"
DM_ID="${DM_ID%.service}"
DESKTOP_SESSION=@DESKTOP_SESSION@

relogin() {
    # Out of the running session into the one that was set.
    case "$DM_ID" in
        gdm) sudo -n /usr/local/libexec/steamify-gdm-relogin ;;
        *) qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout ;;
    esac
}

case "$1" in
    persistent)
        systemctl --user mask cachyos-gamescope-autologin.service
        pkexec /usr/lib/steamos/steam-set-session "$DESKTOP_SESSION" ;;
    oneshot)
        systemctl --user unmask cachyos-gamescope-autologin.service
        pkexec /usr/lib/steamos/steam-set-session gamescope-session.desktop ;;
    gamescope)
        pkexec /usr/lib/steamos/steam-set-session gamescope-session.desktop
        relogin ;;
    desktop|plasma|gnome)
        pkexec /usr/lib/steamos/steam-set-session "$DESKTOP_SESSION"
        steam -shutdown || true
        systemctl --user stop gamescope-session.target || true
        # Under GDM nothing logs in again by itself after the session ends.
        [[ "$DM_ID" == gdm ]] && relogin ;;
    *)
        [[ -n "$1" ]] && echo -e "Unknown session '$1'\n"
        echo "Usage: $(basename "$0") persistent|oneshot|gamescope|desktop"
        exit 1 ;;
esac

if [[ -e /dev/input/.hidden ]]; then
    pkexec mv /dev/input/.hidden/* /dev/input
    pkexec rm -r /dev/input/.hidden
fi
