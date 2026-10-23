#!/bin/bash
# Installed by Steamify as /usr/lib/systemd/system-sleep/steamify-wowlan (Wake-on-WLAN, lib/wake-on-lan.sh).
# systemd runs it with "pre" right before every suspend: the Wi-Fi adapter wakes the machine on a magic packet.
# Done here, right before sleeping, because nothing keeps the setting otherwise: it is gone after a restart, and NetworkManager
# doesn't set it with the iwd backend (the Steam Machine's).
[[ "${1:-}" == pre ]] || exit 0
for phy in /sys/class/ieee80211/*; do
    [[ -e "$phy" ]] && iw phy "${phy##*/}" wowlan enable magic-packet >/dev/null 2>&1
done
exit 0
