#!/bin/bash
# Required packages and AUR helper handling.
# Sourced by steamify.sh; not meant to be run on its own.

aur_noninteractive_flags() {
    # Fully non-interactive install flags for the given AUR helper: no
    # PKGBUILD diff/edit/cleanbuild prompts, no provider-selection prompts
    # (e.g. picking kernel headers for DKMS), and makepkg itself silenced.
    case "$1" in
        yay)
            echo --needed --noconfirm --answerclean None --answerdiff None \
                 --answeredit None --mflags "--noconfirm"
            ;;
        paru)
            echo --needed --noconfirm --skipreview --mflags "--noconfirm"
            ;;
    esac
}

find_aur_helper() {
    if command -v yay >/dev/null 2>&1; then
        echo yay
    elif command -v paru >/dev/null 2>&1; then
        echo paru
    fi
}

bootstrap_yay() {
    # Builds and installs yay from the AUR using only makepkg + base-devel
    # (both from the official repos), so we have an AUR helper available
    # without assuming the user already set one up.
    info "Installing base-devel and git (needed to build an AUR helper)..."
    sudo pacman -S --needed --noconfirm base-devel git || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    info "Cloning yay-bin from the AUR..."
    if ! git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp_dir/yay-bin"; then
        err "Failed to clone yay-bin from the AUR."
        rm -rf "$tmp_dir"
        return 1
    fi

    # Build only, then install it ourselves: makepkg -i runs `sudo -k pacman`,
    # which forgets the cached sudo password and asks for it again.
    info "Building and installing yay (this runs makepkg as your user, not root)..."
    local -a pkgs
    if (cd "$tmp_dir/yay-bin" && makepkg --noconfirm) &&
        mapfile -t pkgs < <(cd "$tmp_dir/yay-bin" && makepkg --packagelist | grep -v -- '-debug-') &&
        sudo pacman -U --noconfirm "${pkgs[@]}"; then
        ok "yay installed."
        rm -rf "$tmp_dir"
        return 0
    else
        err "Building yay failed. See errors above."
        rm -rf "$tmp_dir"
        return 1
    fi
}

# Steamify's own pacman repository (https://github.com/theupriser/steamify-pacman-repo): packages and databases are signed with
# this key (patches/steamify-pacman-repo.pub.asc).
STEAMIFY_REPO_URL="${STEAMIFY_REPO_URL:-https://github.com/theupriser/steamify-pacman-repo/releases/download/repo}"
STEAMIFY_REPO_KEY=767F317AC4F06C54700EC832854F60918B8BC40C

STEAMIFY_PACMAN_CONF="${STEAMIFY_PACMAN_CONF:-/etc/pacman.conf}"
STEAMIFY_REPO_MARKER='# Steamify: packages from steamify-pacman-repo, updated by pacman -Syu'
# What the repository carries and Steamify installs (it stays while one of them is installed).
STEAMIFY_REPO_PKGS=(steamify-gamescope-nvidia steamify-python-hid-shim steamify-cros-ec-cec-dkms steamify-fremont-poweroff-dkms steamify-leds-valve-dkms)

steamify_repo_key_ensure() {
    # pacman trusts the repository's key (added and signed locally); nothing changes when it already does.
    if ! sudo pacman-key --list-keys "$STEAMIFY_REPO_KEY" >/dev/null 2>&1; then
        patch_file steamify-pacman-repo.pub.asc | sudo pacman-key --add - >/dev/null 2>&1 || return 1
    fi
    sudo pacman-key --lsign-key "$STEAMIFY_REPO_KEY" >/dev/null 2>&1
}

steamify_repo_section() { grep -oE '^\[steamify-(generic|v3|v4|znver4)\]' "$STEAMIFY_PACMAN_CONF" 2>/dev/null | head -n 1 | tr -d '[]'; }

steamify_repo_conf_remove() {
    local tmp; tmp="$(mktemp)"
    awk -v marker="$STEAMIFY_REPO_MARKER" '
        $0 == marker { skip = 1; next }
        /^\[steamify-(generic|v3|v4|znver4)\]/ { skip = 1; next }
        skip && /^(SigLevel|Server) *=/ { next }
        skip { skip = 0; if ($0 == "") next }
        { print }
    ' "$STEAMIFY_PACMAN_CONF" > "$tmp"
    if ! cmp -s "$tmp" "$STEAMIFY_PACMAN_CONF"; then
        backup_file "$STEAMIFY_PACMAN_CONF"
        sudo install -m644 "$tmp" "$STEAMIFY_PACMAN_CONF"
    fi
    rm -f "$tmp"
}

steamify_repo_enable() {
    # steamify_repo_enable [variant]: pacman trusts the repository's key and lists the repository of this PC's CPU level (the
    # one the installed build is from) below CachyOS's own, so it never takes a package from them. Only the key and the
    # section: no `pacman -Sy` here (a database refresh without the upgrade is the partial update pacman warns about); the
    # next `pacman -Syu` reads it. A build made here stays out. Idempotent.
    local v="${1:-$(state_get gamescope_nvidia variant)}"
    [[ -n "$v" ]] || v="$(gsn_cpu_variant)"
    if [[ "$v" == local ]]; then steamify_repo_conf_remove; return 0; fi
    steamify_repo_key_ensure || return 1
    if [[ "$(steamify_repo_section)" == "steamify-$v" ]] && grep -qxF "Server = $STEAMIFY_REPO_URL" "$STEAMIFY_PACMAN_CONF"; then return 0; fi
    steamify_repo_conf_remove
    local tmp; tmp="$(mktemp)"
    { cat "$STEAMIFY_PACMAN_CONF"; printf '\n%s\n[steamify-%s]\nSigLevel = Required DatabaseRequired\nServer = %s\n' "$STEAMIFY_REPO_MARKER" "$v" "$STEAMIFY_REPO_URL"; } > "$tmp"
    backup_file "$STEAMIFY_PACMAN_CONF"
    sudo install -m644 "$tmp" "$STEAMIFY_PACMAN_CONF"
    rm -f "$tmp"
    state_set gamescope_nvidia variant "$v"
    steamify_repo_fetch_db "$v" || warn "Couldn't download Steamify's package database: run  sudo pacman -Sy  before installing packages, or pacman stops with \"could not find database\"."
    return 0
}

steamify_repo_fetch_db() {
    # steamify_repo_fetch_db <level>: the repository's database and its signature into pacman's sync folder, as `pacman -Sy`
    # would for this one repository. A section in pacman.conf without its database file makes every later `pacman -S <package>`
    # stop with "could not find database" until the next -Sy; a full -Sy here would be the partial update pacman warns about.
    local v="$1" tmp ok=0
    tmp="$(mktemp -d)" || return 1
    if curl -fsL --connect-timeout 10 --max-time 60 -o "$tmp/db" "$STEAMIFY_REPO_URL/steamify-$v.db" &&
        curl -fsL --connect-timeout 10 --max-time 60 -o "$tmp/db.sig" "$STEAMIFY_REPO_URL/steamify-$v.db.sig"; then
        sudo install -d /var/lib/pacman/sync &&
            sudo install -m644 "$tmp/db" "/var/lib/pacman/sync/steamify-$v.db" &&
            sudo install -m644 "$tmp/db.sig" "/var/lib/pacman/sync/steamify-$v.db.sig" &&
            # pacman checks the signature when it loads the database: a bad one must not stay
            { pacman -Sl "steamify-$v" >/dev/null 2>&1 && ok=1 || sudo rm -f "/var/lib/pacman/sync/steamify-$v.db" "/var/lib/pacman/sync/steamify-$v.db.sig"; }
    fi
    rm -rf "$tmp"
    [[ $ok == 1 ]]
}

steamify_repo_disable() {
    # Back to no repository, but only when nothing from it is installed: those packages stay when an option goes off (like
    # the other packages of the conversion) and keep updating with pacman -Syu.
    local p
    for p in "${STEAMIFY_REPO_PKGS[@]}"; do pacman -Q "$p" >/dev/null 2>&1 && return 0; done
    steamify_repo_conf_remove
    sudo rm -f /var/lib/pacman/sync/steamify-{generic,v3,v4,znver4}.db* 2>/dev/null
    sudo pacman-key --delete "$STEAMIFY_REPO_KEY" >/dev/null 2>&1
    return 0
}

steamify_repo_pkg_url() {
    # steamify_repo_pkg_url <package>: the URL of the newest file of an architecture-independent package, read from the
    # repository's database (every variant has them).
    local pkg="$1" tmp d f
    tmp="$(mktemp)" || return 1
    curl -fsL --connect-timeout 10 --max-time 30 -o "$tmp" "$STEAMIFY_REPO_URL/steamify-generic.db" || { rm -f "$tmp"; return 1; }
    d="$(tar -I unzstd -tf "$tmp" 2>/dev/null | grep -E "^$pkg-[0-9][^/]*/desc$" | head -n 1)"
    f="$([[ -n "$d" ]] && tar -I unzstd -xOf "$tmp" "$d" | awk '/^%FILENAME%$/ { getline; print }')"
    rm -f "$tmp"
    [[ -n "$f" ]] || return 1
    echo "$STEAMIFY_REPO_URL/$f"
}

steamify_dkms_install() {
    # steamify_dkms_install <package> <dkms name> <dkms version>: a DKMS driver as a signed package from the repository,
    # for every kernel that has headers. A copy that Steamify put into /usr/src earlier (or another package's, like the AUR
    # leds-valve-dkms-git, which the new package replaces) is removed first, since pacman refuses to overwrite files it doesn't own.
    # Returns 1 when the repository can't be used: the caller falls back to what it did before.
    local pkg="$1" name="$2" ver="$3" url src="/usr/src/$2-$3" k
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
        pacman -Q dkms >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm dkms >/dev/null || return 1
        install_kernel_headers || return 1
        steamify_repo_key_ensure || return 1
        url="$(steamify_repo_pkg_url "$pkg")" || return 1
        if [[ -d "$src" ]] && ! pacman -Qo "$src" >/dev/null 2>&1; then
            sudo dkms remove "$name/$ver" --all >/dev/null 2>&1
            sudo rm -rf "$src"
        fi
        info "Installing $pkg from Steamify's repository..."
        sudo pacman -U --noconfirm --needed --ask 4 "$url" >/dev/null || return 1
    fi
    steamify_repo_enable "$(steamify_repo_variant)" || warn "Couldn't list Steamify's pacman repository: $pkg won't update with pacman -Syu."
    # pacman's DKMS hook builds it for the kernels that have headers; the ones it missed, here.
    for k in /usr/lib/modules/*/build; do
        [[ -d "$k" ]] || continue
        k="$(basename "$(dirname "$k")")"
        dkms status -k "$k" "$name" 2>/dev/null | grep -q installed && continue
        sudo dkms install "$name/$ver" -k "$k" >/dev/null 2>&1 || warn "Building $name for $k failed."
    done
    return 0
}

steamify_dkms_remove() {
    # steamify_dkms_remove <package> <dkms name> <dkms version>: the package, or the copy an older Steamify put there.
    local pkg="$1" name="$2" ver="$3"
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        sudo pacman -Rns --noconfirm "$pkg" >/dev/null
    else
        sudo dkms remove "$name/$ver" --all >/dev/null 2>&1
        sudo rm -rf "/usr/src/$name-$ver"
    fi
    steamify_repo_disable
}

steamify_repo_variant() {
    # The CPU level the repository section uses: the installed patched gamescope's (its build decides), else this CPU's.
    local v; v="$(state_get gamescope_nvidia variant)"
    [[ "$v" =~ ^(generic|v3|v4|znver4)$ ]] || v="$(gsn_cpu_variant)"
    echo "$v"
}

python_hid_shim_ensure() {
    # jupiter-hw-support (a dependency of gamescope-session-cachyos) wants python-hid, which conflicts with python-hidapi, and
    # a PC can need python-hidapi (liquidctl does). Only Valve's Steam Deck controller firmware updater uses python-hid, which
    # a PC doesn't run: so a placeholder package that provides python-hid keeps python-hidapi and satisfies the dependency
    # (also at later updates, which a one-time --assume-installed wouldn't). It stays when the conversion goes off:
    # jupiter-hw-support, which stays, depends on it.
    pacman -Q python-hidapi >/dev/null 2>&1 || return 0
    pacman -Q python-hid steamify-python-hid-shim >/dev/null 2>&1 && return 0
    local dir pkg cache="${XDG_CACHE_HOME:-$HOME/.cache}/steamify"
    warn "python-hidapi is installed (liquidctl and others need it) and conflicts with python-hid, which Steam Deck's tools ask for: keeping python-hidapi, with a small placeholder package for python-hid."
    # The signed package from Steamify's repository (pacman checks its signature against the key); built here when that fails.
    if steamify_repo_key_ensure && sudo pacman -U --noconfirm "$STEAMIFY_REPO_URL/steamify-python-hid-shim-1-1-any.pkg.tar.zst"; then
        ok "python-hidapi kept; python-hid is covered by a placeholder."
        return 0
    fi
    warn "The placeholder package couldn't be downloaded: building it here."
    sudo pacman -S --needed --noconfirm base-devel >/dev/null || { err "Installing the build tools failed."; return 1; }
    mkdir -p "$cache" && dir="$(mktemp -d -p "$cache" hid-shim.XXXXXX)" || return 1
    patch_file python-hid-shim.PKGBUILD > "$dir/PKGBUILD" || { rm -rf "$dir"; return 1; }
    if ! (cd "$dir" && makepkg -f --noconfirm >/dev/null) ||
        ! pkg="$(ls "$dir"/steamify-python-hid-shim-*.pkg.tar.* 2>/dev/null | head -1)" ||
        ! sudo pacman -U --noconfirm "$pkg"; then
        rm -rf "$dir"
        err "Couldn't set up the python-hid placeholder: python-hidapi and python-hid conflict, so the packages can't be installed."
        return 1
    fi
    rm -rf "$dir"
    ok "python-hidapi kept; python-hid is covered by a placeholder."
}

install_required_packages() {
    # Step 2: gamescope/Steam and the desktop helpers the rest of the setup uses.
    local -a MISSING
    info "Checking required packages: gamescope-session-cachyos, steam, mangohud, xterm, ttf-liberation, wqy-zenhei, plasma-keyboard"
    mapfile -t MISSING < <(pacman -T gamescope-session-cachyos steam mangohud xterm ttf-liberation wqy-zenhei plasma-keyboard)

    if [[ ${#MISSING[@]} -gt 0 ]]; then
        python_hid_shim_ensure || return 1
        info "Installing missing packages: ${MISSING[*]}"
        sudo pacman -S --needed --noconfirm "${MISSING[@]}" || { err "Package installation failed."; return 1; }
    else
        ok "All required packages already installed."
    fi
}

ensure_aur_helper() {
    # yay or paru, bootstrapping yay from the AUR when neither is installed.
    if [[ -n "$(find_aur_helper)" ]]; then
        ok "AUR helper already present."
    else
        info "No AUR helper (yay/paru) found. Installing yay..."
        bootstrap_yay
    fi
}
