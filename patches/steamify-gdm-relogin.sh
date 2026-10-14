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
# GDM is stopped first, so its login screen doesn't show while the old user
# manager shuts down; a new login right away fails ("A graphical session is
# already running!", or the session dies at once), so wait until it is gone.
systemctl stop gdm.service
loginctl terminate-user "$USER_NAME"
# (not `loginctl show-user`: it still lists the user about 10 s after it is gone)
USER_RUNTIME="/run/user/$(id -u "$USER_NAME")"
for _ in $(seq 120); do [[ -d "$USER_RUNTIME" ]] || break; sleep 0.25; done
systemctl start gdm.service
