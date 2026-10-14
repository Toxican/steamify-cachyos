#!/bin/bash
# steam-set-session with GDM support (Steamify prototype). CachyOS's own only
# knows plasma-login-manager and SDDM and quietly does nothing on GDM. GDM
# has no autologin fragment: it takes the user's session from
# AccountsService, so that is where the session goes.
set -e

DM_ID="$(systemctl show -p Id --value display-manager)"
DM_ID="${DM_ID%.service}"
SESSION="${1:-gamescope-session.desktop}"

# "desktop" is the desktop to go back to: the one chosen in Steamify (/etc/steamify/desktop: kde, gnome or last),
# else the one used last (recorded below when leaving it for gamescope), else whichever is installed.
have_session() { [[ -f "/usr/share/wayland-sessions/$1" || -f "/usr/share/xsessions/$1" ]]; }
resolve_desktop() {
    local pref last
    pref="$(cat /etc/steamify/desktop 2>/dev/null || true)"
    last="$(cat /var/lib/steamify/last-desktop 2>/dev/null || true)"
    [[ -z "$pref" || "$pref" == last ]] && pref="$last"
    case "$pref" in
        gnome) have_session gnome.desktop && { echo gnome.desktop; return; } ;;
        kde) have_session plasma.desktop && { echo plasma.desktop; return; } ;;
    esac
    have_session plasma.desktop && { echo plasma.desktop; return; }
    echo gnome.desktop
}
remember_desktop() {
    # Leaving a desktop for gamescope: which desktop it was (from the user's own session).
    local uid="${PKEXEC_UID:-}" id desktop
    [[ -n "$uid" ]] || return 0
    id="$(loginctl show-user "$uid" -p Display --value 2>/dev/null)"
    [[ -n "$id" ]] || return 0
    desktop="$(loginctl show-session "$id" -p Desktop --value 2>/dev/null | tr 'A-Z' 'a-z')"
    case "$desktop" in
        *gnome*) kind=gnome ;;
        *kde*|*plasma*) kind=kde ;;
        *) return 0 ;;
    esac
    mkdir -p /var/lib/steamify && echo "$kind" > /var/lib/steamify/last-desktop
}
[[ "$SESSION" == desktop ]] && SESSION="$(resolve_desktop)"
[[ "$SESSION" == gamescope-session* ]] && remember_desktop

case "$DM_ID" in
    plasmalogin) CONF_FILE="/etc/plasmalogin.conf.d/zz-steamos-autologin.conf" ;;
    sddm) CONF_FILE="/etc/sddm.conf.d/zz-steamos-autologin.conf" ;;
    gdm)
        if [[ -n "${PKEXEC_UID:-}" ]]; then TARGET_USER="$(id -un "$PKEXEC_UID")"
        else TARGET_USER="${SUDO_USER:-}"; fi
        # (|| true: logname fails without a login, and set -e would end the script before the fallback.)
        [[ -n "$TARGET_USER" ]] || TARGET_USER="$(logname 2>/dev/null || true)"
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
