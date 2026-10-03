#!/bin/bash
# Valve's SteamOS package mirror: finding its newest repository and fetching a
# verified package from it. Used by the SteamOS extras, the Steam Machine CEC
# driver, the BIOS update and the os-release version.
# Sourced by steamify.sh; not meant to be run on its own.

VALVE_MIRROR="https://steamdeck-packages.steamos.cloud/archlinux-mirror"

valve_newest_repo() {
    # valve_newest_repo <prefix> [max-seconds]: the newest <prefix>-X.Y repo
    # (jupiter, holo), compared as versions: 3.10 is newer than 3.9. Prints
    # nothing when the mirror can't be reached.
    local -a limit=()
    [[ -n "${2:-}" ]] && limit=(--max-time "$2")
    curl -fsL "${limit[@]}" "$VALVE_MIRROR/" 2>/dev/null | grep -oE "$1-[0-9]+\.[0-9]+/" | tr -d / | sort -uV | tail -n 1
}

valve_repo_url() { echo "$VALVE_MIRROR/$1/os/x86_64"; }

valve_desc_field() {
    # valve_desc_field <db> <desc path> <FIELD>: one value from a package's
    # entry in a pacman database (FILENAME, SHA256SUM).
    tar -xOf "$1" "$2" 2>/dev/null | awk -v f="%$3%" '$0 == f { getline; print }'
}

valve_fetch_pkg() {
    # valve_fetch_pkg <repo prefix> <package> <dir>: download the newest
    # <package> from the newest <prefix> repository into <dir> and print its
    # path. The file name and SHA-256 come from the repository's database and
    # the checksum is verified; the database is kept in <dir> for more calls.
    local prefix="$1" name="$2" dir="$3" repo db desc file_name sha256
    repo="$(valve_newest_repo "$prefix")"
    db="$dir/$prefix.db"
    if [[ ! -f "$db" ]]; then
        [[ -n "$repo" ]] && curl -fsL "$(valve_repo_url "$repo")/$repo.db" -o "$db" ||
            { err "Couldn't read Valve's SteamOS package index ($VALVE_MIRROR)."; return 1; }
    fi
    desc="$(tar -tf "$db" 2>/dev/null | grep -E "^$name-[0-9][^/]*/desc$" | head -n 1)"
    [[ -n "$desc" ]] || { err "No $name in Valve's $repo repository."; return 1; }
    file_name="$(valve_desc_field "$db" "$desc" FILENAME)"
    sha256="$(valve_desc_field "$db" "$desc" SHA256SUM)"

    info "Downloading $file_name ($repo)..." >&2
    curl -fsL "$(valve_repo_url "$repo")/$file_name" -o "$dir/$file_name" ||
        { err "Downloading $file_name failed."; return 1; }
    echo "$sha256  $dir/$file_name" | sha256sum -c --quiet - >&2 ||
        { err "Checksum mismatch for $file_name; not using it."; return 1; }
    echo "$dir/$file_name"
}
