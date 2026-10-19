#!/bin/bash
# Multi-user mode (single user mode off): the PC boots to the login screen, but
# switching between gamescope and the desktop while logged in must not show
# it. plasma-login-manager logs in again by itself only with User= and
# Relogin=true, so this writes them for the logged-in user when a session
# switch is asked for, and empties them once the next session is there.
CONF=/etc/plasmalogin.conf.d/zzt-steamify-relogin.conf

seat_session() {
    # "<id> <user>" of the user session on seat0.
    loginctl list-sessions --no-legend 2>/dev/null | awk '$4 == "seat0" && $6 == "user" { print $1, $3; exit }'
}

read -r old user < <(seat_session)
[[ -n "${user:-}" ]] || exit 0

printf '[Autologin]\nUser=%s\nRelogin=true\n' "$user" > "$CONF"
for _ in $(seq 40); do
    sleep 1
    read -r new _ < <(seat_session)
    [[ -n "${new:-}" && "$new" != "$old" ]] && break
done
: > "$CONF"
