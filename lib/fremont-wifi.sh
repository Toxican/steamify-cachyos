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
WIFI_FW_STOCK=/usr/lib/firmware/ath11k/QCA2066/hw2.1/amss.bin.zst
# SHA-256 of the decompressed amss.bin (both report firmware 03926.13): CachyOS's linux-firmware-atheros 20260916, and Valve's.
WIFI_SHA_CACHYOS=6be9c2264898c0190fb39befa5f42d07413014db772daaedd56031415d9880ae
WIFI_SHA_VALVE=a0c75e4c784de85a0624466a87751982091c46dc85c14cf74ff7a0592e8b3c30

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

wifi_build() {
    # Which amss.bin the kernel loads at the next start: ours in updates/ before the package's. Prints valve, cachyos or
    # unknown (another build, e.g. a newer linux-firmware); nothing when there is none or zstd is missing.
    local f sum
    for f in "$WIFI_FW_DEST" "$WIFI_FW_STOCK"; do
        [[ -f "$f" ]] && break
        f=""
    done
    [[ -n "$f" ]] && command -v zstd >/dev/null 2>&1 || return 0
    sum="$(zstd -dc "$f" 2>/dev/null | sha256sum | cut -d' ' -f1)"
    case "$sum" in
        "$WIFI_SHA_VALVE") echo valve ;;
        "$WIFI_SHA_CACHYOS") echo cachyos ;;
        *) echo unknown ;;
    esac
}

wifi_label() {
    # Menu label with the build in use; kept short enough for the row.
    case "$(wifi_build)" in
        valve) echo "Wi-Fi firmware from SteamOS: Wake-on-WLAN works (in use: SteamOS's)" ;;
        cachyos) echo "Wi-Fi firmware from SteamOS: Wake-on-WLAN works (in use: CachyOS's)" ;;
        *) echo "${LABEL[wifi]}" ;;
    esac
}

wifi_enable() {
    local tmp pkg
    # linux-firmware may ship Valve's build one day: then there is nothing to install.
    if ! wifi_status && [[ "$(wifi_build)" == valve ]]; then
        ok "The Wi-Fi firmware already is SteamOS's build; nothing to install."
        return 0
    fi
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
