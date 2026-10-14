#!/bin/bash
# steam-set-session with GDM support (Steamify prototype). CachyOS's own only
# knows plasma-login-manager and SDDM and quietly does nothing on GDM. GDM
# has no autologin fragment: it takes the user's session from
# AccountsService, so that is where the session goes.
set -e

DM_ID="$(systemctl show -p Id --value display-manager)"
DM_ID="${DM_ID%.service}"
SESSION="${1:-gamescope-session.desktop}"

case "$DM_ID" in
    plasmalogin) CONF_FILE="/etc/plasmalogin.conf.d/zz-steamos-autologin.conf" ;;
    sddm) CONF_FILE="/etc/sddm.conf.d/zz-steamos-autologin.conf" ;;
    gdm)
        if [[ -n "${PKEXEC_UID:-}" ]]; then TARGET_USER="$(id -un "$PKEXEC_UID")"
        else TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null)}"; fi
        # At boot (steamify-boot-desktop.service) nobody is logged in: the autologin user.
        [[ -n "$TARGET_USER" ]] || TARGET_USER="$(sed -n 's/^AutomaticLogin=//p' /etc/gdm/custom.conf 2>/dev/null)"
        [[ -n "$TARGET_USER" ]] || exit 0
        ACCOUNT="/var/lib/AccountsService/users/$TARGET_USER"
        SESSION_ID="${SESSION%.desktop}"
        mkdir -p /var/lib/AccountsService/users
        touch "$ACCOUNT"
        grep -q '^\[User\]' "$ACCOUNT" || echo "[User]" >> "$ACCOUNT"
        for key in Session XSession; do
            if grep -q "^$key=" "$ACCOUNT"; then sed -i "s|^$key=.*|$key=$SESSION_ID|" "$ACCOUNT"
            else sed -i "/^\[User\]/a $key=$SESSION_ID" "$ACCOUNT"; fi
        done
        systemctl restart accounts-daemon 2>/dev/null || true
        exit 0 ;;
esac

# Any other login manager: nothing to do.
[[ -n "${CONF_FILE:-}" ]] || exit 0
mkdir -p "$(dirname "$CONF_FILE")"
printf '[Autologin]\nSession=%s\n' "$SESSION" > "$CONF_FILE"
