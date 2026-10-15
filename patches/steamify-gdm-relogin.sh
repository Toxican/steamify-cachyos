#!/bin/bash
# Log the autologin user in again, into the session steam-set-session picked
# (Steamify prototype, GDM). Run as root through sudo, from inside the session
# that is being left. GDM logs in by itself only when the daemon starts, and
# a new session refuses to start while the old user manager still runs
# ("A graphical session is already running!"): so the user is ended first,
# then GDM restarted. That work runs in its own transient unit, because
# ending the user kills this process too.
#
# An optional session id as the argument ("gnome"): that session is logged in
# for this time only. The session in AccountsService (what the next boot goes
# to: gaming mode after the SteamOS conversion) is put back once the new
# session is up.
if [[ "$1" != --work ]]; then
    [[ -n "${SUDO_USER:-}" ]] || exit 1
    exec systemd-run --no-block --collect --unit=steamify-gdm-relogin "$0" --work "$SUDO_USER" "${1:-}"
fi
USER_NAME="$2"
SESSION="$3"
ACCOUNT="/var/lib/AccountsService/users/$USER_NAME"

# Session= and XSession= of the user, as GDM reads them at the next login.
get_session() { sed -n "s/^$1=//p" "$ACCOUNT" 2>/dev/null | head -1; }
set_session() {
    local key
    touch "$ACCOUNT"
    grep -q '^\[User\]' "$ACCOUNT" || echo "[User]" >> "$ACCOUNT"
    for key in Session XSession; do
        if grep -q "^$key=" "$ACCOUNT"; then sed -i "s|^$key=.*|$key=$1|" "$ACCOUNT"
        else sed -i "/^\[User\]/a $key=$1" "$ACCOUNT"; fi
    done
    systemctl restart accounts-daemon 2>/dev/null || true
}
if [[ -n "$SESSION" ]]; then
    OLD_SESSION="$(get_session Session)"; OLD_XSESSION="$(get_session XSession)"
    set_session "${SESSION%.desktop}"
fi

# GDM is stopped first, so its login screen doesn't show while the old user
# manager shuts down; a new login right away fails ("A graphical session is
# already running!", or the session dies at once), so wait until it is gone.
systemctl stop gdm.service
loginctl terminate-user "$USER_NAME"
# (not `loginctl show-user`: it still lists the user about 10 s after it is gone)
USER_RUNTIME="/run/user/$(id -u "$USER_NAME")"
for _ in $(seq 120); do [[ -d "$USER_RUNTIME" ]] || break; sleep 0.25; done
systemctl start gdm.service

if [[ -n "$SESSION" ]]; then
    # The new session has read what it logs in to once its user manager runs; then the next boot's session goes back.
    for _ in $(seq 120); do [[ -d "$USER_RUNTIME" ]] && break; sleep 0.25; done
    sleep 8
    if [[ -n "$OLD_SESSION" ]]; then
        sed -i "s|^Session=.*|Session=$OLD_SESSION|" "$ACCOUNT"
        if [[ -n "$OLD_XSESSION" ]]; then sed -i "s|^XSession=.*|XSession=$OLD_XSESSION|" "$ACCOUNT"; fi
        systemctl restart accounts-daemon 2>/dev/null || true
    fi
fi
