#!/bin/bash
# Run by steamify-relogin.service when something picks a session for the next login: steam-set-session
# (zz-steamos-autologin.conf: Return to Gaming Mode, the boot unit) or steamos-manager (the one-shot
# zzt-*-temp-login.conf of Steam's Switch to Desktop). Two jobs, in this order:
#
# 1. The last pick wins. A one-shot login sorts after zz-steamos-autologin.conf and so beats it, and
#    nothing removes it any more (the login manager's restart did, before 2.13.0): after Switch to
#    Desktop, Return to Gaming Mode would write gamescope into zz-steamos-autologin.conf and the
#    one-shot would send the PC back to the desktop. So a one-shot that is older than the pick in
#    zz-steamos-autologin.conf is emptied.
# 2. With --relogin (multi-user mode, single user mode off: the PC boots to the login screen):
#    plasma-login-manager logs in again by itself only with User= and Relogin=true, so write them for
#    the logged-in user, and empty them once the next session is there.
CONF_DIR=/etc/plasmalogin.conf.d
RELOGIN_CONF=$CONF_DIR/zzt-steamify-relogin.conf

mtime() { stat -c %.9Y "$1" 2>/dev/null || echo 0; }

pick=$(mtime "$CONF_DIR/zz-steamos-autologin.conf")
for f in "$CONF_DIR"/zzt-*-temp-login.conf; do
    [[ -s "$f" ]] || continue
    awk -v pick="$pick" -v oneshot="$(mtime "$f")" 'BEGIN { exit !(pick >= oneshot) }' && : > "$f"
done

[[ "${1:-}" == --relogin ]] || exit 0

seat_session() {
    # "<id> <user>" of the user session on seat0.
    loginctl list-sessions --no-legend 2>/dev/null | awk '$4 == "seat0" && $6 == "user" { print $1, $3; exit }'
}

read -r old user < <(seat_session)
[[ -n "${user:-}" ]] || exit 0

printf '[Autologin]\nUser=%s\nRelogin=true\n' "$user" > "$RELOGIN_CONF"
for _ in $(seq 40); do
    sleep 1
    read -r new _ < <(seat_session)
    [[ -n "${new:-}" && "$new" != "$old" ]] && break
done
: > "$RELOGIN_CONF"
