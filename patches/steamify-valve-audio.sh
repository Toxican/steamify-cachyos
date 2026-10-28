#!/bin/bash
# Keeps /var/lib/steamify/valve-audio, a local pacman repository, in step with Valve's builds of the audio
# libraries (PipeWire, WirePlumber) from its SteamOS repositories. Installed by Steamify's "HDMI-CEC volume"
# option as /usr/local/lib/steamify/steamify-valve-audio and run by its timer; it only fills the repository
# (the next `pacman -Syu` installs what is newer), it never installs anything itself. The packages come from Valve's repositories through pacman, signature checked
# (Valve's package key is the only one in /etc/steamify/valve-gnupg).
# Runs as root. Only what is installed here is mirrored: the 64-bit packages from Valve's newest jupiter-X.Y
# repository, the 32-bit ones from the multilib-X.Y of the same release.
set -uo pipefail

MIRROR="https://steamdeck-packages.steamos.cloud/archlinux-mirror"
REPO_NAME=steamify-valve-audio
REPO_DIR=/var/lib/steamify/valve-audio
SYNC_DB="/var/lib/pacman/sync/$REPO_NAME.db"
VALVE_GPGDIR=/etc/steamify/valve-gnupg

die() { echo "steamify-valve-audio: $*" >&2; exit 1; }

# The installed packages the swap covers: the PipeWire family and WirePlumber, 64-bit and 32-bit.
tracked() {
    pacman -Qq | grep -E '^(lib32-)?(lib)?pipewire($|-)|^(lib32-)?gst-plugin-pipewire$|^(lib32-)?(lib)?wireplumber$' | sort -u
}

refresh() {
    local work rel p f repos found=() kept=() mirrored=()
    work="$(mktemp -d)" || die "no temporary directory"
    trap 'rm -rf "$work"' RETURN
    [[ -d "$VALVE_GPGDIR" ]] || die "Valve's package key is missing ($VALVE_GPGDIR): turn HDMI-CEC volume off and on again"
    rel="$(curl -fsL "$MIRROR/" | grep -oE 'jupiter-[0-9]+\.[0-9]+/' | tr -d / | sed 's/jupiter-//' | sort -V | tail -n 1)"
    [[ -n "$rel" ]] || die "couldn't read Valve's SteamOS package index ($MIRROR)"
    # Valve's repositories in a throw-away pacman config of their own, with Valve's key as the only trusted one: the packages
    # are signed, the databases are not (hence DatabaseOptional). The system's databases are not touched.
    mkdir -p "$work/db/sync" "$work/cache" "$REPO_DIR"
    ln -s /var/lib/pacman/local "$work/db/local"
    {
        printf '[options]\nArchitecture = x86_64\nSigLevel = Required DatabaseOptional\nLocalFileSigLevel = Optional\nGPGDir = %s\n' "$VALVE_GPGDIR"
        for repos in "jupiter-$rel" "multilib-$rel"; do printf '\n[%s]\nServer = %s/%s/os/$arch\n' "$repos" "$MIRROR" "$repos"; done
    } > "$work/pacman.conf"
    pm() { pacman --config "$work/pacman.conf" --dbpath "$work/db" --cachedir "$work/cache" "$@"; }
    pm -Sy --noconfirm >/dev/null 2>&1 || die "couldn't read Valve's SteamOS repositories"
    local have; have="$(pm -Sql "jupiter-$rel" "multilib-$rel" 2>/dev/null)"
    for p in $(tracked); do
        if grep -qx "$p" <<<"$have"; then found+=("$p"); else kept+=("$p"); fi
    done
    [[ ${#found[@]} -gt 0 ]] || die "none of the installed audio packages is in Valve's repositories"
    # Only what is installed here is fetched, no dependencies (-dd); pacman checks each package's signature.
    pm -Sw --noconfirm -dd "${found[@]}" >/dev/null 2>&1 || die "downloading Valve's packages failed (or a signature didn't check out)"
    for p in "${found[@]}"; do
        f="$(ls -t "$work/cache/$p"-[0-9]*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -n 1)"
        [[ -n "$f" ]] || die "no file for $p after the download"
        [[ -f "$REPO_DIR/${f##*/}" ]] || install -m644 "$f" "$REPO_DIR/${f##*/}"
        mirrored+=("${f##*/}")
    done
    # Only the current build of each package stays; the database is rebuilt from what is left.
    local f keep
    for f in "$REPO_DIR"/*.pkg.tar.*; do
        [[ -e "$f" ]] || continue
        keep=0
        for file in "${mirrored[@]}"; do [[ "${f##*/}" == "$file" ]] && keep=1; done
        [[ $keep == 1 ]] || rm -f "$f"
    done
    rm -f "$REPO_DIR/$REPO_NAME".db* "$REPO_DIR/$REPO_NAME".files*
    (cd "$REPO_DIR" && repo-add -q "$REPO_NAME.db.tar.zst" "${mirrored[@]}") || die "repo-add failed"
    # pacman reads sync/<repo>.db; copying it is what `pacman -Sy` does for a file:// repository, without
    # refreshing the other repositories (a partial upgrade).
    install -Dm644 "$REPO_DIR/$REPO_NAME.db.tar.zst" "$SYNC_DB"
    echo "mirrored (Valve's SteamOS $rel): ${mirrored[*]%%-[0-9]*}"
    [[ ${#kept[@]} -eq 0 ]] || echo "not in Valve's repositories, left as CachyOS's: ${kept[*]}"
}

case "${1:-refresh}" in
    refresh) refresh ;;
    *) die "usage: $0 [refresh]" ;;
esac
