#!/bin/bash
# "Wake-on-LAN" (wol) and "Wake-on-WLAN" (wowlan) menu items, opt-in sub-options of Steam Machine support: the Steam
# Machine wakes up on a magic packet, over the cable (from sleep, and from power-off when the BIOS allows it) or over
# Wi-Fi (from sleep only: the adapter has no power when the machine is off). Linux doesn't keep either setting by
# itself (ethtool and `iw ... wowlan` are gone after a restart), so NetworkManager does: one drop-in each, as the
# default for every connection that doesn't set its own (ethernet.wake-on-lan, wifi.wake-on-wlan). Nothing of
# NetworkManager's own files is edited; off removes the drop-in. Wake-on-WLAN only works with the SteamOS Wi-Fi
# firmware (lib/fremont-wifi.sh): with CachyOS's the machine wakes up again at once (#108).
# Sourced by steamify.sh; not meant to be run on its own.

WOL_CONF=/etc/NetworkManager/conf.d/90-steamify-wake-on-lan.conf
WOWLAN_CONF=/etc/NetworkManager/conf.d/90-steamify-wake-on-wlan.conf
# NetworkManager's flag values: NM_SETTING_WIRED_WAKE_ON_LAN_MAGIC and NM_SETTING_WIRELESS_WAKE_ON_WLAN_MAGIC.
WOL_MAGIC=64
WOWLAN_MAGIC=8

wake_nm_available() { command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager; }

wol_available() {
    detect_valve_fremont || return 1
    local d
    for d in /sys/class/net/en*; do
        [[ -e "$d/device" ]] && return 0
    done
    return 1
}
wowlan_available() { wifi_available; }

wake_conf_write() {
    # wake_conf_write <file> <section> <key> <value> <what>
    local file="$1" section="$2" key="$3" value="$4" what="$5"
    sudo mkdir -p "$(dirname "$file")"
    printf '%s\n' "# Written by Steamify: $what, as the default for connections that don't set it themselves." \
        "[$section]" "$key=$value" | sudo tee "$file" >/dev/null
}

wake_conf_apply() {
    # New defaults are read on reload; a connection that is up gets them re-applied without dropping it.
    sudo nmcli general reload conf >/dev/null 2>&1
    local dev
    nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: -v t="$1" '$2 == t { print $1 }' | while read -r dev; do
        sudo nmcli device reapply "$dev" >/dev/null 2>&1 </dev/null
    done
}

wol_status() { [[ -f "$WOL_CONF" ]]; }
wol_enable() {
    wake_nm_available || { err "NetworkManager isn't running; Wake-on-LAN can't be set up."; return 1; }
    wake_conf_write "$WOL_CONF" connection-steamify-wake-on-lan ethernet.wake-on-lan "$WOL_MAGIC" "Wake-on-LAN (magic packet) on the cable" || return 1
    wake_conf_apply ethernet
    ok "Wake-on-LAN on: the Steam Machine wakes on a magic packet over the cable. From power-off it also needs wake-on-LAN in the BIOS."
}
wol_disable() {
    [[ -e "$WOL_CONF" ]] || return 0
    sudo rm -f "$WOL_CONF"
    wake_nm_available && wake_conf_apply ethernet
    ok "Wake-on-LAN off again (after the next restart or reconnect)."
}

wowlan_status() { [[ -f "$WOWLAN_CONF" ]]; }
wowlan_enable() {
    wake_nm_available || { err "NetworkManager isn't running; Wake-on-WLAN can't be set up."; return 1; }
    # With CachyOS's Wi-Fi firmware the machine wakes up again at once when it sleeps with this on (#108): the firmware item is
    # ticked along with this one in the menu; this only warns when it wasn't applied.
    [[ "$(wifi_build)" == valve ]] || warn "The Wi-Fi firmware isn't SteamOS's: with it the Steam Machine may wake up again right after going to sleep."
    wake_conf_write "$WOWLAN_CONF" connection-steamify-wake-on-wlan wifi.wake-on-wlan "$WOWLAN_MAGIC" "Wake-on-WLAN (magic packet) over Wi-Fi" || return 1
    wake_conf_apply wifi
    ok "Wake-on-WLAN on: the Steam Machine wakes from sleep on a magic packet over Wi-Fi (not from power-off)."
}
wowlan_disable() {
    [[ -e "$WOWLAN_CONF" ]] || return 0
    sudo rm -f "$WOWLAN_CONF"
    wake_nm_available && wake_conf_apply wifi
    ok "Wake-on-WLAN off again (after the next restart or reconnect)."
}
