#!/bin/bash
# "Pin the kernel" (kpin), retired: newer linux-cachyos releases rebooted the
# Steam Machine instead of shutting down, which the power-off fix
# (lib/fremont-poweroff.sh) made unnecessary. Only what removes an existing pin
# is still offered (kpin_available), a sub-option of Steam Machine support.
# Sourced by steamify.sh; not meant to be run on its own.

# Kernel pinned on a Steam Machine (optional): newer linux-cachyos releases
# rebooted it instead of shutting down, which the power-off fix now handles. The packages are kept in
# PINNED_KERNEL_DIR, so re-applying (or reinstalling after an update slipped
# through) needs no download.
PINNED_KERNEL_VER="7.1.6-1"
PINNED_KERNEL_KVER="7.1.6-1-cachyos"
PINNED_KERNEL_PKGS=(linux-cachyos linux-cachyos-headers)
PINNED_KERNEL_DIR="${PINNED_KERNEL_DIR:-/var/cache/steamify/kernel}"
# SHA-256 of each package, so a file from any source is the one reviewed
# here; its CachyOS signature is checked as well.
declare -A PINNED_KERNEL_SHA256=(
    [linux-cachyos]=417fcd07102192b86e78e92ed7171d5a49378e9f57faea3fa2c7c541e9f68d08
    [linux-cachyos-headers]=d069866a11d9092746e1d5133cefd8924f027da2c9bf5af38d30b3aed6ded9bf
)
# Tried in order, after the kernel dir and pacman's cache. Our own release
# always has these files; the archive keeps every release; the mirror only
# the current one. PINNED_KERNEL_URL puts another source (a directory
# holding the files) in front.
PINNED_KERNEL_SOURCES=(
    ${PINNED_KERNEL_URL:+"$PINNED_KERNEL_URL"}
    "https://github.com/theupriser/steamify-cachyos/releases/download/kernel-$PINNED_KERNEL_VER"
    "https://archive.cachyos.org/archive/cachyos"
    "https://mirror.cachyos.org/repo/x86_64/cachyos"
)

pinned_kernel_installed() {
    local p
    for p in "${PINNED_KERNEL_PKGS[@]}"; do
        [[ "$(pacman -Q "$p" 2>/dev/null)" == "$p $PINNED_KERNEL_VER" ]] || return 1
    done
}

fetch_pinned_kernel_file() {
    # $1 = file name. Local kernel dir first, then pacman's cache, then the
    # download sources. Downloads go to a .part file so a broken one is never
    # mistaken for a finished one.
    local f="$1" dest="$PINNED_KERNEL_DIR/$1" src
    [[ -s "$dest" ]] && return 0
    if [[ -s "/var/cache/pacman/pkg/$f" ]]; then
        sudo cp "/var/cache/pacman/pkg/$f" "$dest" && return 0
    fi
    for src in "${PINNED_KERNEL_SOURCES[@]}"; do
        if sudo curl -fL --retry 2 --connect-timeout 15 -o "$dest.part" "$src/$f" 2>/dev/null; then
            sudo mv "$dest.part" "$dest"
            return 0
        fi
        warn "Couldn't get $f from $src, trying the next source..."
    done
    sudo rm -f "$dest.part"
    return 1
}

verify_pinned_kernel_pkg() {
    # $1 = package name, $2 = file. Both checks must pass: the SHA-256 from
    # this script, and the CachyOS signature (pacman on its own installs a
    # local file without a .sig: LocalFileSigLevel = Optional).
    local sum
    sum="$(sha256sum "$2" | cut -d' ' -f1)"
    if [[ "$sum" != "${PINNED_KERNEL_SHA256[$1]}" ]]; then
        err "$(basename "$2") doesn't match its expected checksum."
        return 1
    fi
    if ! sudo pacman-key --verify "$2.sig" "$2" >/dev/null 2>&1; then
        err "$(basename "$2") doesn't have a valid CachyOS signature."
        return 1
    fi
}

pin_kernel_in_pacman_conf() {
    # Adds our packages to IgnorePkg in [options], keeping what's there.
    local p
    for p in "${PINNED_KERNEL_PKGS[@]}"; do
        grep -Eq "^IgnorePkg\s*=.*(\s|=)$p(\s|$)" /etc/pacman.conf && continue
        if grep -Eq '^IgnorePkg\s*=' /etc/pacman.conf; then
            sudo sed -i -E "0,/^IgnorePkg\s*=/s/^(IgnorePkg\s*=.*)$/\1 $p/" /etc/pacman.conf
        else
            sudo sed -i -E "0,/^\[options\]/s//[options]\nIgnorePkg = $p/" /etc/pacman.conf
        fi
    done
}

unpin_kernel_in_pacman_conf() {
    local p
    for p in "${PINNED_KERNEL_PKGS[@]}"; do
        sudo sed -i -E "/^IgnorePkg\s*=/s/\s$p(\s|$)/\1/" /etc/pacman.conf
    done
    # Drop the line if nothing is left on it.
    sudo sed -i -E '/^IgnorePkg\s*=\s*$/d' /etc/pacman.conf
}

install_pinned_kernel() {
    sudo mkdir -p "$PINNED_KERNEL_DIR"
    pin_kernel_in_pacman_conf
    if pinned_kernel_installed; then
        ok "Kernel $PINNED_KERNEL_VER already installed and pinned."
        return 0
    fi

    local p f files=()
    info "Getting kernel $PINNED_KERNEL_VER (kept in $PINNED_KERNEL_DIR)..."
    for p in "${PINNED_KERNEL_PKGS[@]}"; do
        f="$p-$PINNED_KERNEL_VER-x86_64.pkg.tar.zst"
        fetch_pinned_kernel_file "$f" && fetch_pinned_kernel_file "$f.sig" ||
            { err "Couldn't download $f from any source."; return 1; }
        if ! verify_pinned_kernel_pkg "$p" "$PINNED_KERNEL_DIR/$f"; then
            # Removed, so the next run fetches it again.
            sudo rm -f "$PINNED_KERNEL_DIR/$f" "$PINNED_KERNEL_DIR/$f.sig"
            err "Removed it; run the wizard again to download it once more."
            return 1
        fi
        files+=("$PINNED_KERNEL_DIR/$f")
    done

    # pacman checks each package against the .sig next to it.
    info "Installing kernel $PINNED_KERNEL_VER..."
    if ! sudo pacman -U --noconfirm "${files[@]}"; then
        err "Installing kernel $PINNED_KERNEL_VER failed."
        return 1
    fi
    [[ "$(uname -r)" != "$PINNED_KERNEL_KVER" ]] && RESTART_FOR_LOGIN=true
    ok "Kernel $PINNED_KERNEL_VER installed and pinned (restart to use it)."
}

remove_kernel_pin() {
    # Back to CachyOS's current kernel. The packages stay in
    # PINNED_KERNEL_DIR, so turning support on again doesn't download.
    unpin_kernel_in_pacman_conf
    pinned_kernel_installed || return 0
    info "Updating the kernel back to CachyOS's current version..."
    sudo pacman -Syu --noconfirm ||
        { warn "Updating the kernel failed; run: sudo pacman -Syu"; return 0; }
    RESTART_FOR_LOGIN=true
}

# "Pin the kernel" menu item, a sub-option of Steam Machine support. The
# power-off fix made it unnecessary: only shown while on, to remove it.
kpin_available() { detect_valve_fremont && kpin_status; }
kpin_status() {
    pinned_kernel_installed && grep -Eq '^IgnorePkg\s*=.*\slinux-cachyos(\s|$)' /etc/pacman.conf
}

kpin_enable() {
    install_pinned_kernel || return 1
    # The DKMS pacman hook built leds-valve for the new headers; make sure.
    if pacman -Qi leds-valve-dkms-git >/dev/null 2>&1 &&
        ! dkms status -k "$PINNED_KERNEL_KVER" leds-valve-dkms 2>/dev/null | grep -q installed; then
        sudo dkms install leds-valve-dkms/0.1 -k "$PINNED_KERNEL_KVER" ||
            warn "Building the LED driver for $PINNED_KERNEL_KVER failed."
    fi
}

kpin_disable() {
    # Saved HDMI refresh boost EDIDs were for the pinned kernel only (newer
    # ones read the whole EDID), also those of displays not connected now.
    hdmi_status && hdmi_forget_all
    remove_kernel_pin
}
