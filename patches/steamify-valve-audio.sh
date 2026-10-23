#!/bin/bash
# Keeps /var/lib/steamify/valve-audio, a local pacman repository, in step with Valve's builds of the audio
# libraries (PipeWire, WirePlumber) from its SteamOS repositories. Installed by Steamify's "HDMI-CEC volume"
# option as /usr/local/lib/steamify/steamify-valve-audio and run by its timer; it only fills the repository
# (the next `pacman -Syu` installs what is newer), it never installs anything itself.
# Runs as root. Only what is installed here is mirrored: the 64-bit packages from Valve's newest jupiter-X.Y
# repository, the 32-bit ones from the multilib-X.Y of the same release.
set -uo pipefail

MIRROR="https://steamdeck-packages.steamos.cloud/archlinux-mirror"
REPO_NAME=steamify-valve-audio
REPO_DIR=/var/lib/steamify/valve-audio
SYNC_DB="/var/lib/pacman/sync/$REPO_NAME.db"

die() { echo "steamify-valve-audio: $*" >&2; exit 1; }

# The installed packages the swap covers: the PipeWire family and WirePlumber, 64-bit and 32-bit.
tracked() {
    pacman -Qq | grep -E '^(lib32-)?(lib)?pipewire($|-)|^(lib32-)?gst-plugin-pipewire$|^(lib32-)?(lib)?wireplumber$' | sort -u
}

# db_entry <db> <package>: the directory name ("pipewire-1:1.6.8-1.7") of <package> in a repository database.
db_entry() { tar -tf "$1" 2>/dev/null | grep -E "^$2-[0-9r][^/]*/desc$" | head -n 1 | sed 's|/desc$||'; }
desc_field() { tar -xOf "$1" "$2/desc" | awk -v f="%$3%" '$0 == f { getline; print }'; }

refresh() {
    local work rel jdb mdb p entry db file sha mirrored=() kept=()
    work="$(mktemp -d)" || die "no temporary directory"
    trap 'rm -rf "$work"' RETURN
    rel="$(curl -fsL "$MIRROR/" | grep -oE 'jupiter-[0-9]+\.[0-9]+/' | tr -d / | sed 's/jupiter-//' | sort -V | tail -n 1)"
    [[ -n "$rel" ]] || die "couldn't read Valve's SteamOS package index ($MIRROR)"
    curl -fsL "$MIRROR/jupiter-$rel/os/x86_64/jupiter-$rel.db" -o "$work/jupiter.db" || die "no jupiter-$rel database"
    curl -fsL "$MIRROR/multilib-$rel/os/x86_64/multilib-$rel.db" -o "$work/multilib.db" 2>/dev/null || : >"$work/multilib.db"
    mkdir -p "$REPO_DIR"
    for p in $(tracked); do
        entry="" db=""
        for db in jupiter multilib; do
            [[ -s "$work/$db.db" ]] && entry="$(db_entry "$work/$db.db" "$p")"
            [[ -n "$entry" ]] && break
        done
        if [[ -z "$entry" ]]; then kept+=("$p"); continue; fi
        file="$(desc_field "$work/$db.db" "$entry" FILENAME)"
        sha="$(desc_field "$work/$db.db" "$entry" SHA256SUM)"
        [[ -n "$file" && -n "$sha" ]] || die "no file name or checksum for $p in Valve's $db repository"
        if [[ ! -f "$REPO_DIR/$file" ]]; then
            local repo_path="jupiter-$rel/os/x86_64"
            [[ "$db" == multilib ]] && repo_path="multilib-$rel/os/x86_64"
            curl -fsL "$MIRROR/$repo_path/$file" -o "$work/$file" || die "downloading $file failed"
            echo "$sha  $work/$file" | sha256sum -c --quiet - || die "checksum mismatch for $file; not using it"
            mv "$work/$file" "$REPO_DIR/$file"
        fi
        mirrored+=("$file")
    done
    [[ ${#mirrored[@]} -gt 0 ]] || die "none of the installed audio packages is in Valve's repositories"
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
