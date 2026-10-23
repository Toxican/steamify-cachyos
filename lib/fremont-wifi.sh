#!/bin/bash
# "Wi-Fi firmware" menu item (wifi), an opt-in sub-option of Steam Machine
# support: Wake-on-WLAN works. The Steam Machine's Wi-Fi chip (Qualcomm
# QCA2066, ath11k) reports the same firmware version on CachyOS and on SteamOS,
# but SteamOS ships a different amss.bin build (package linux-firmware-holo,
# Valve's holo-main repository). With CachyOS's build the machine wakes up
# again at once when it suspends with Wake-on-WLAN on (a PCIe PME from the
# adapter); with Valve's it stays asleep and wakes on a Wi-Fi magic packet
# (#108). The file goes to /usr/lib/firmware/updates, which the kernel reads
# before /usr/lib/firmware: nothing of linux-firmware is overwritten, so its
# updates don't undo it, and turning the item off is removing one file.
# Sourced by steamify.sh; not meant to be run on its own.

WIFI_FW_REPO=holo-main
WIFI_FW_PKG=linux-firmware-holo
WIFI_FW_FILE=usr/lib/firmware/updates/ath11k/QCA2066/hw2.1/amss.bin.zst
WIFI_FW_DEST="/$WIFI_FW_FILE"

wifi_available() {
    detect_valve_fremont || return 1
    # The adapter is Qualcomm QCNFA765 [17cb:1103]; other Wi-Fi cards in a Steam Machine aren't touched.
    local d
    for d in /sys/bus/pci/devices/*; do
        [[ "$(cat "$d/vendor" 2>/dev/null)" == 0x17cb && "$(cat "$d/device" 2>/dev/null)" == 0x1103 ]] && return 0
    done
    return 1
}

wifi_status() { [[ -f "$WIFI_FW_DEST" ]]; }

wifi_enable() {
    local tmp pkg
    tmp="$(mktemp -d)"
    info "Downloading Valve's Wi-Fi firmware for the Steam Machine..."
    pkg="$(fetch_holo_pkg "$tmp" "$WIFI_FW_PKG" "$WIFI_FW_REPO")" || { rm -rf "$tmp"; return 1; }
    if ! tar -xf "$pkg" -C "$tmp" "$WIFI_FW_FILE" 2>/dev/null || ! zstd -t -q "$tmp/$WIFI_FW_FILE" 2>/dev/null; then
        rm -rf "$tmp"
        err "$WIFI_FW_PKG has no usable $(basename "$WIFI_FW_FILE"); the Wi-Fi firmware stays as it is."
        return 1
    fi
    sudo install -D -m 644 "$tmp/$WIFI_FW_FILE" "$WIFI_FW_DEST" || { rm -rf "$tmp"; err "Installing the Wi-Fi firmware failed."; return 1; }
    rm -rf "$tmp"
    ok "Wi-Fi firmware from SteamOS installed; it is loaded at the next restart."
}

wifi_disable() {
    [[ -e "$WIFI_FW_DEST" ]] || return 0
    sudo rm -f "$WIFI_FW_DEST"
    # Only the directories we made, and only while they are empty.
    sudo rmdir -p --ignore-fail-on-non-empty "$(dirname "$WIFI_FW_DEST")" 2>/dev/null
    ok "SteamOS's Wi-Fi firmware removed; CachyOS's own is used again after the next restart."
}
