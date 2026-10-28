#!/bin/bash
# Valve's SteamOS repositories (https://steamdeck-packages.steamos.cloud/archlinux-mirror), used for the few packages Steamify
# takes from them: HDMI-CEC (cecd, cec-audio-control, inputattach-cec-units), the Wi-Fi firmware (linux-firmware-holo), the
# SteamOS desktop extras (steamdeck-kde-presets) and, for HDMI-CEC volume, Valve's PipeWire and WirePlumber.
#
# They are never listed in /etc/pacman.conf: a plain `pacman -Syu` can't pull Valve's mesa or linux-firmware over CachyOS's.
# Each use writes a throw-away pacman config with just the repositories it needs, its own signing keyring (only Valve's
# package-builder key, below, trusted; CachyOS's keyring and ours are not involved), a private database folder (the system's
# sync databases stay as they are) and fetches exactly the packages the caller names. A name that a CachyOS repository
# also has is refused unless the caller lists it in VALVE_REPLACE_OK: only the options that replace a package on purpose
# (HDMI-CEC volume) do.
# Sourced by steamify.sh; not meant to be run on its own.

VALVE_MIRROR="${VALVE_MIRROR:-https://steamdeck-packages.steamos.cloud/archlinux-mirror}"
# "GitLab CI Package Builder": signs every package of the repositories (checked for the ones Steamify uses, 2026-10-28; the
# repositories' databases are not signed). The key is in Valve's holo-keyring package and in patches/.
VALVE_KEY=889B5EBDDD505A683621900DAF1D2199EF0A3CCF
VALVE_GPGDIR="${VALVE_GPGDIR:-/etc/steamify/valve-gnupg}"
VALVE_REPLACE_OK="${VALVE_REPLACE_OK:-}"

valve_newest() {
    # valve_newest <family>: the newest <family>-X.Y repository on the mirror (jupiter, holo, multilib), nothing when unreachable.
    curl -fsL --connect-timeout 10 --max-time 30 "$VALVE_MIRROR/" | grep -oE "$1-[0-9]+\.[0-9]+/" | tr -d / | sort -V | tail -n 1
}

valve_key_ensure() {
    # Valve's key in its own keyring, trusted there and nowhere else.
    sudo test -f "$VALVE_GPGDIR/pubring.kbx" -o -f "$VALVE_GPGDIR/pubring.gpg" 2>/dev/null &&
        sudo gpg --homedir "$VALVE_GPGDIR" --batch --list-keys "$VALVE_KEY" >/dev/null 2>&1 && return 0
    local k; k="$(mktemp)"
    patch_file valve-ci-package-builder.pub.asc > "$k"
    # What patches/ carries must be the pinned key, not just a key.
    if [[ "$(gpg --show-keys --with-colons "$k" 2>/dev/null | awk -F: '/^fpr/ {print $10; exit}')" != "$VALVE_KEY" ]]; then
        rm -f "$k"; err "The Valve key Steamify carries is not the pinned one ($VALVE_KEY)."; return 1
    fi
    sudo install -d -m 700 "$VALVE_GPGDIR" &&
        sudo gpg --homedir "$VALVE_GPGDIR" --batch --import "$k" >/dev/null 2>&1 &&
        echo "$VALVE_KEY:6:" | sudo gpg --homedir "$VALVE_GPGDIR" --batch --import-ownertrust >/dev/null 2>&1
    local rc=$?
    rm -f "$k"
    return $rc
}

valve_name_ok() {
    # A package Steamify may take from Valve: not one a system repository also has, unless the option replaces it on purpose.
    local p="$1"
    [[ " $VALVE_REPLACE_OK " == *" $p "* ]] && return 0
    pacman -Si "$p" >/dev/null 2>&1 && return 1
    return 0
}

valve_pacman() {
    # valve_pacman <work dir> <repository>[,<repository>...] <pacman arguments...>: pacman with only those Valve repositories.
    local work="$1" repos="$2" r; shift 2
    valve_key_ensure || return 1
    mkdir -p "$work/db/sync" "$work/cache"
    ln -sfn /var/lib/pacman/local "$work/db/local"
    {
        printf '[options]\nArchitecture = x86_64\nSigLevel = Required DatabaseOptional\nLocalFileSigLevel = Optional\nGPGDir = %s\n' "$VALVE_GPGDIR"
        for r in ${repos//,/ }; do printf '\n[%s]\nServer = %s/%s/os/$arch\n' "$r" "$VALVE_MIRROR" "$r"; done
    } > "$work/pacman.conf"
    sudo pacman --config "$work/pacman.conf" --dbpath "$work/db" --cachedir "$work/cache" "$@"
}

valve_fetch_pkg() {
    # valve_fetch_pkg <dir> <package> <repository>: the newest <package> of that repository, signature checked, into <dir>;
    # prints its path. No dependencies are downloaded (-dd): installing it is the caller's step.
    local dir="$1" pkg="$2" repo="$3" f
    valve_name_ok "$pkg" || { err "$pkg is also in a CachyOS repository: Steamify takes it from Valve only where an option replaces it on purpose."; return 1; }
    [[ -n "$repo" ]] || { err "Couldn't read Valve's SteamOS package index ($VALVE_MIRROR)."; return 1; }
    info "Downloading $pkg from Valve's $repo..." >&2
    valve_pacman "$dir/valve" "$repo" -Sy --noconfirm >/dev/null 2>&1 &&
        valve_pacman "$dir/valve" "$repo" -Sw --noconfirm -dd "$repo/$pkg" >/dev/null 2>&1 ||
        { err "Downloading $pkg from Valve's $repo failed (or its signature didn't check out)."; return 1; }
    f=""
    local c
    for c in "$dir/valve/cache/$pkg"-[0-9]*.pkg.tar.*; do
        [[ "$c" == *.sig || ! -e "$c" ]] && continue
        [[ -z "$f" || "$c" -nt "$f" ]] && f="$c"
    done
    [[ -n "$f" ]] || { err "No $pkg in Valve's $repo repository."; return 1; }
    echo "$f"
}
