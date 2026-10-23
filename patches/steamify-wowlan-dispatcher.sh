#!/bin/bash
# NetworkManager runs this as root for every connection event ($1 the interface, $2 the event). Installed as
# /etc/NetworkManager/dispatcher.d/90-steamify-wowlan by Steamify's Wake-on-WLAN: it turns Wake-on-WLAN on for the Wi-Fi adapter as soon as
# a connection is up. Enabling it only right before the first suspend of a boot was too late (the Wi-Fi link is already being taken
# down): that first suspend didn't wake on a magic packet (#108); the following ones did.
[[ "${2:-}" == up ]] || exit 0
[[ -d "/sys/class/net/${1:-}/wireless" ]] || exit 0
phy="$(iw dev "$1" info 2>/dev/null | awk '/wiphy/ { print "phy" $2; exit }')"
[[ -n "$phy" ]] && iw phy "$phy" wowlan enable magic-packet >/dev/null 2>&1
exit 0
