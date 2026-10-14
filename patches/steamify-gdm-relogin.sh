#!/bin/bash
# Log the autologin user in again, into the session steam-set-session picked
# (Steamify prototype, GDM). Run as root through sudo, from inside the session
# that is being left. GDM logs in by itself only when the daemon starts, and
# a new session refuses to start while the old user manager still runs
# ("A graphical session is already running!"): so the user is ended first,
# then GDM restarted. That work runs in its own transient unit, because
# ending the user kills this process too.
if [[ "$1" != --work ]]; then
    [[ -n "${SUDO_USER:-}" ]] || exit 1
    exec systemd-run --no-block --collect --unit=steamify-gdm-relogin "$0" --work "$SUDO_USER"
fi
USER_NAME="$2"
# No waiting for the old user manager to go: systemd starts the new login
# after it, and waiting only keeps GDM's login screen up in the meantime.
loginctl terminate-user "$USER_NAME"
systemctl restart gdm.service
