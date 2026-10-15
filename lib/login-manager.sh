#!/bin/bash
# Booting into gaming mode: autologin into gamescope with SDDM or
# plasma-login-manager (plus the session sync bridge the latter needs).
# Sourced by steamify.sh; not meant to be run on its own.

BASE_CONF="/etc/plasmalogin.conf"
GDM_CONF="/etc/gdm/custom.conf"
GDM_FIX_DIR=/usr/local/share/steamify-gdm
GDM_HOOK=/etc/pacman.d/hooks/95-steamify-gdm.hook
GDM_SUDOERS=/etc/sudoers.d/steamify-gdm-relogin
GDM_RELOGIN=/usr/local/libexec/steamify-gdm-relogin

# The "SteamOS conversion" menu item: gaming mode boot, the Return to
# Gaming Mode shortcut and Steam on the desktop (lib/steam-desktop.sh).
gaming_status() {
    # Autologin into gamescope is configured for this user.
    case "$(current_display_manager)" in
        sddm) [[ -f /etc/sddm.conf.d/10-gamescope-autologin.conf ]] ;;
        plasmalogin)
            sed -n '/^\[Autologin\]/,/^\[/p' "$BASE_CONF" 2>/dev/null | grep -qx "User=$USER" &&
                [[ -f /etc/systemd/system/sync-steamos-session.path ]] ;;
        gdm)
            sed -n '/^\[daemon\]/,/^\[/p' /etc/gdm/custom.conf 2>/dev/null | grep -qx "AutomaticLogin=$USER" &&
                [[ -f "$GDM_FIX_DIR/steam-set-session" ]] ;;
        *) return 1 ;;
    esac
}

# What Steam shows in its System settings besides the OS name (which stays
# CachyOS's, for legal clarity and because limine-snapper-sync finds the boot
# entries by it): the SteamOS release as the OS version, steam-machine as the
# codename, Steamify with its version as the variant (os-release VERSION_ID,
# VERSION_CODENAME, VARIANT_ID; see patches/steamify-os-release.sh).
OS_NAME_SCRIPT=/usr/local/libexec/steamify-os-release
OS_NAME_HOOK=/etc/pacman.d/hooks/zz-steamify-os-release.hook
# limine's tools take the OS name from TARGET_OS_NAME, else os-release's
# PRETTY_NAME: pinned to CachyOS, the boot entries never depend on os-release.
LIMINE_DEFAULTS=/etc/default/limine

steamos_release() {
    # The SteamOS release Steamify follows: Valve's newest jupiter-X.Y repo
    # (where the SteamOS extras come from), as an os-release ID (no spaces or
    # capitals: steamos-3.9). Offline (e.g. in the installer): the one set
    # before, if any.
    local v
    v="$(curl -fsL --max-time 15 "$VALVE_MIRROR/" 2>/dev/null | grep -oE 'jupiter-[0-9]+\.[0-9]+/' | tr -d / | sort -V | tail -n 1)"
    if [[ -n "$v" ]]; then echo "steamos-${v#jupiter-}"
    else sed -n 's/^VERSION_ID=\(steamos-.*\)$/\1/p' /etc/os-release 2>/dev/null; fi
}

os_name_enable() {
    # 2.9.0 pre-releases renamed the OS itself; the name stays CachyOS's.
    if grep -q '^DISTRIB_DESCRIPTION=.*with Steamify' /etc/lsb-release 2>/dev/null &&
        [[ -x /usr/share/libalpm/scripts/cachyos-branding ]]; then
        sudo /usr/share/libalpm/scripts/cachyos-branding lsb-release
    fi
    [[ -n "$(kreadconfig6 --file kcm-about-distrorc --group General --key Name 2>/dev/null)" ]] &&
        kset gaming kcm-about-distrorc General Name --delete
    # About this System: os-release's VERSION (CachyOS has none) instead of
    # VERSION_ID, which is the SteamOS release now.
    kset gaming kcm-about-distrorc General UseOSReleaseVersion true
    patch_file steamify-os-release.sh | fill VERSION="$VERSION" STEAMOS="$(steamos_release)" |
        sudo install -Dm755 /dev/stdin "$OS_NAME_SCRIPT" &&
        patch_file steamify-os-release.hook | fill SCRIPT="$OS_NAME_SCRIPT" |
            sudo install -Dm644 /dev/stdin "$OS_NAME_HOOK" &&
        sudo "$OS_NAME_SCRIPT" || { err "Setting Steamify's version for Steam failed."; return 1; }
    if [[ -f "$LIMINE_DEFAULTS" ]] && ! grep -q '^TARGET_OS_NAME=' "$LIMINE_DEFAULTS"; then
        backup_file "$LIMINE_DEFAULTS"
        printf '%s\n' 'TARGET_OS_NAME="CachyOS"' | sudo tee -a "$LIMINE_DEFAULTS" > /dev/null
        state_set gaming limine_target 1
    fi
    return 0
}

os_name_disable() {
    sudo rm -f "$OS_NAME_HOOK" "$OS_NAME_SCRIPT"
    [[ -f /etc/os-release ]] && sudo sed -i -e '/^VARIANT=/d' -e '/^VARIANT_ID=/d' -e '/^VERSION_ID=/d' -e '/^VERSION_CODENAME=/d' /etc/os-release
    # CachyOS's own values back, the way its hooks write them.
    if [[ -x /usr/share/libalpm/scripts/cachyos-branding ]]; then
        sudo /usr/share/libalpm/scripts/cachyos-branding os-release
        # Undoes 2.9.0 pre-releases, which changed lsb-release's name too.
        sudo /usr/share/libalpm/scripts/cachyos-branding lsb-release
    fi
    if [[ -n "$(state_get gaming limine_target)" ]]; then
        sudo sed -i '/^TARGET_OS_NAME="CachyOS"$/d' "$LIMINE_DEFAULTS"
        state_set gaming limine_target ""
    fi
    return 0
}

os_version_refresh() {
    # After every run that changed something (sudo is at hand then): Steam's
    # OS version follows Steamify's, not just the one that set it up. Silent:
    # the app reads the backend's stdout as JSON.
    gaming_status 2>/dev/null || return 0
    grep -qx "VARIANT_ID=steamify-$VERSION" /etc/os-release 2>/dev/null && return 0
    os_name_enable > /dev/null 2>&1
    return 0
}

gaming_enable() {
    # LOGIN_MANAGER (sddm with single user, else plasmalogin) is set by the
    # menu. Re-running with the other value switches over cleanly.
    install_required_packages || return 1
    # NVIDIA: gamescope's picture is corrupted unless it is the patched one (no-op elsewhere).
    gsn_enable || return 1
    case "$LOGIN_MANAGER" in
        sddm)
            switch_to_sddm || return 1
            configure_sddm_autologin
            remove_session_sync
            ;;
        plasmalogin)
            remove_sddm_autologin
            switch_to_plasmalogin || return 1
            configure_autologin
            install_session_sync
            ;;
        gdm)
            # GNOME (prototype): GDM autologin, plus CachyOS's session tools made GDM-aware.
            remove_sddm_autologin
            remove_session_sync
            switch_to_gdm || return 1
            configure_gdm_autologin || return 1
            ;;
    esac
    # CachyOS's own session tools only go to Plasma and only know SDDM and plasma-login-manager: with GNOME installed ours replace them.
    if [[ "$LOGIN_MANAGER" == gdm ]] || desktop_installed gnome; then session_tools_install || return 1; fi
    # (NVIDIA with single user mode from before the conversion: its desktop autologin would pin the Plasma session.)
    single_login_release
    create_desktop_shortcut
    steam_enable
    os_name_enable || return 1
}

gaming_disable() {
    # Back to a normal desktop boot with CachyOS's default login manager.
    # Packages (steam, gamescope-session-cachyos, ...) are kept.
    info "Turning off booting into gaming mode..."
    remove_sddm_autologin
    remove_session_sync
    session_tools_remove
    if [[ "$(current_display_manager)" == gdm ]]; then
        restore_gdm_config
    else
        restore_plasmalogin_config
        switch_to_plasmalogin
    fi
    remove_desktop_shortcut
    steam_disable
    gsn_disable
    krevert gaming
    os_name_disable
    # NVIDIA with single user mode still on: nothing else logs in by itself any more.
    nvidia_present && single_status && single_login_enable
    gnome_extras_release
    ok "The PC boots to the normal login screen again (from the next boot)."
}

switch_to_plasmalogin() {
    [[ "$(current_display_manager)" == plasmalogin ]] && return 0
    info "Switching the login manager to plasma-login-manager..."
    sudo pacman -S --needed --noconfirm plasma-login-manager || { err "Installing plasma-login-manager failed."; return 1; }
    local current
    current="$(systemctl show -p Id --value display-manager 2>/dev/null)"
    [[ -n "$current" && "$current" != plasmalogin.service ]] && sudo systemctl disable "$current"
    sudo systemctl enable -f plasmalogin.service || { err "Enabling plasmalogin failed."; return 1; }
    ok "plasma-login-manager is the login manager from the next boot on."
}

remove_sddm_autologin() {
    sudo rm -f /etc/sddm.conf.d/10-gamescope-autologin.conf
}

restore_plasmalogin_config() {
    # Put back the original /etc/plasmalogin.conf from the first run's
    # backup, or at least drop our [Autologin] section.
    if [[ -f "${BASE_CONF}.bak-gamescope-wizard" ]]; then
        sudo cp -a "${BASE_CONF}.bak-gamescope-wizard" "$BASE_CONF"
    elif [[ -f "$BASE_CONF" ]]; then
        sudo awk '/^\[Autologin\]/ { skip=1; next } /^\[/ { skip=0 } !skip { print }' "$BASE_CONF" |
            sudo tee "${BASE_CONF}.tmp" > /dev/null && sudo mv "${BASE_CONF}.tmp" "$BASE_CONF"
    fi
}

switch_to_sddm() {
    # Takes effect at the next boot; the running session is left alone.
    [[ "$(current_display_manager)" == sddm ]] && return 0
    info "Installing and enabling SDDM..."
    sudo pacman -S --needed --noconfirm sddm || { err "Installing sddm failed."; return 1; }
    local current
    current="$(systemctl show -p Id --value display-manager 2>/dev/null)"
    if [[ -n "$current" && "$current" != "sddm.service" ]]; then
        sudo systemctl disable "$current"
    fi
    sudo systemctl enable -f sddm.service || { err "Enabling sddm failed."; return 1; }
    ok "SDDM is the login manager from the next boot on."
}

remove_sddm_base_autologin() {
    # /etc/sddm.conf is read last: an [Autologin] there would override our fragments.
    if [[ -f /etc/sddm.conf ]] && grep -q '^\[Autologin\]' /etc/sddm.conf; then
        backup_file /etc/sddm.conf
        sudo awk '
            /^\[Autologin\]/ { skip=1; next }
            /^\[/ { skip=0 }
            !skip { print }
        ' /etc/sddm.conf | sudo tee /etc/sddm.conf.tmp > /dev/null &&
            sudo mv /etc/sddm.conf.tmp /etc/sddm.conf
        info "Removed [Autologin] from /etc/sddm.conf (backup kept)."
    fi
}

configure_sddm_autologin() {
    # User= and Relogin= live in our own fragment; steam-set-session keeps
    # Session= up to date in zz-steamos-autologin.conf, which sorts later
    # and so wins. /etc/sddm.conf is read last, so any [Autologin] there
    # would override both and is removed.
    local conf="/etc/sddm.conf.d/10-gamescope-autologin.conf"
    info "Configuring SDDM autologin for $TARGET_USER into gamescope (Relogin=true)"
    sudo mkdir -p /etc/sddm.conf.d
    sudo tee "$conf" > /dev/null << EOF
[Autologin]
User=$TARGET_USER
Session=gamescope-session.desktop
Relogin=true
EOF

    remove_sddm_base_autologin

    # Start in gamescope, through CachyOS's own tool so its file is current.
    sudo /usr/lib/steamos/steam-set-session gamescope-session.desktop

    ok "SDDM autologin configured:"
    cat "$conf"
    echo
}

remove_session_sync() {
    # The plasmalogin sync bridge from an earlier run isn't needed on SDDM.
    if [[ -f /etc/systemd/system/sync-steamos-session.path ]]; then
        info "Removing the plasma-login-manager sync bridge (not needed with SDDM)..."
        sudo systemctl disable --now sync-steamos-session.path 2>/dev/null
        sudo rm -f /etc/systemd/system/sync-steamos-session.path \
            /etc/systemd/system/sync-steamos-session.service \
            /usr/local/bin/sync-steamos-session.sh
        sudo systemctl daemon-reload
    fi
}

configure_autologin() {
    # Steps 3-5: plasmalogin.conf.d, the base [Autologin] section, stray fragments.
    # 3. Ensure plasmalogin.conf.d exists (fixes Switch-to-Desktop crash)
    info "Ensuring /etc/plasmalogin.conf.d exists (fixes the 'Switching to Desktop' hang bug)"
    sudo mkdir -p /etc/plasmalogin.conf.d
    ok "Directory present."
    echo

    # 4. Fix the base /etc/plasmalogin.conf
    info "Configuring $BASE_CONF (Session=gamescope-session.desktop, User=$TARGET_USER, Relogin=true)"
    backup_file "$BASE_CONF"

    sudo touch "$BASE_CONF"

    sudo awk '
        BEGIN { in_autologin=0 }
        /^\[Autologin\]/ { in_autologin=1; next }
        /^\[/ { in_autologin=0 }
        !in_autologin { print }
    ' "$BASE_CONF" | sudo tee "${BASE_CONF}.tmp" > /dev/null || { err "Failed to rewrite $BASE_CONF."; exit 1; }

    sudo mv "${BASE_CONF}.tmp" "$BASE_CONF"

    sudo tee -a "$BASE_CONF" > /dev/null << EOF
[Autologin]
Session=gamescope-session.desktop
User=$TARGET_USER
Relogin=true
EOF

    ok "Base autologin config written:"
    sudo sed -n '/^\[Autologin\]/,$p' "$BASE_CONF"
    echo

    # 5. Clean up any stray conf.d autologin fragments from manual attempts
    info "Removing any leftover manual conf.d autologin overrides (base config now handles it)"
    sudo rm -f /etc/plasmalogin.conf.d/zzz-steamos-autologin*.conf
    ok "Cleaned."
    echo
}

install_session_sync() {
    # Steps 6-8: sync bridge conf.d -> base config, its systemd units, first run.
    # 6. Install the sync bridge: conf.d -> base config
    local SYNC_SCRIPT="/usr/local/bin/sync-steamos-session.sh"
    info "Installing session sync bridge at $SYNC_SCRIPT"

    patch_file sync-steamos-session.sh | sudo tee "$SYNC_SCRIPT" > /dev/null

    sudo chmod +x "$SYNC_SCRIPT"
    ok "Sync script installed."
    echo

    # 7. systemd path watcher + service
    info "Installing systemd path watcher so session switches take effect immediately"

    service_file sync-steamos-session.path | sudo tee /etc/systemd/system/sync-steamos-session.path > /dev/null

    service_file sync-steamos-session.service | sudo tee /etc/systemd/system/sync-steamos-session.service > /dev/null

    sudo systemctl daemon-reload
    sudo systemctl enable --now sync-steamos-session.path
    ok "Path watcher enabled."
    echo

    # 8. Run it once now so current state is in sync
    info "Running the sync once now to align current state"
    sudo systemctl start sync-steamos-session.service
    ok "Done. Current base config:"
    sudo cat "$BASE_CONF"
    echo
}

switch_to_gdm() {
    # Already the login manager on a GNOME install; this only makes sure it is installed and enabled.
    [[ "$(current_display_manager)" == gdm ]] && return 0
    info "Installing and enabling GDM..."
    sudo pacman -S --needed --noconfirm gdm || { err "Installing gdm failed."; return 1; }
    local current
    current="$(systemctl show -p Id --value display-manager 2>/dev/null)"
    [[ -n "$current" && "$current" != gdm.service ]] && sudo systemctl disable "$current"
    sudo systemctl enable -f gdm.service || { err "Enabling gdm failed."; return 1; }
    ok "GDM is the login manager from the next boot on."
}

configure_gdm_autologin() {
    # [daemon] AutomaticLogin: GDM reads it when it starts, which is why the
    # session tools restart GDM to log in again (see patches/steamify-gdm-session-select.sh).
    info "Configuring GDM autologin for $TARGET_USER"
    sudo mkdir -p /etc/gdm
    sudo touch "$GDM_CONF"
    [[ -f "$GDM_CONF.bak-steamify" ]] || sudo cp -a "$GDM_CONF" "$GDM_CONF.bak-steamify"
    sudo awk '
        /^\[daemon\]/ { print; indaemon=1; next }
        /^\[/ { indaemon=0 }
        indaemon && /^(AutomaticLoginEnable|AutomaticLogin)=/ { next }
        { print }
    ' "$GDM_CONF" | sudo tee "$GDM_CONF.tmp" > /dev/null
    grep -q '^\[daemon\]' "$GDM_CONF.tmp" || printf '[daemon]\n' | sudo tee -a "$GDM_CONF.tmp" > /dev/null
    sudo sed -i "/^\[daemon\]/a AutomaticLoginEnable=True\nAutomaticLogin=$TARGET_USER" "$GDM_CONF.tmp"
    sudo mv "$GDM_CONF.tmp" "$GDM_CONF"
    ok "GDM autologin configured."
}

restore_gdm_config() {
    if [[ -f "$GDM_CONF.bak-steamify" ]]; then
        sudo cp -a "$GDM_CONF.bak-steamify" "$GDM_CONF" && sudo rm -f "$GDM_CONF.bak-steamify"
    else
        sudo sed -i '/^AutomaticLoginEnable=/d;/^AutomaticLogin=/d' "$GDM_CONF" 2>/dev/null
    fi
}

session_tools_install() {
    # CachyOS's steam-set-session and steamos-session-select only know
    # plasma-login-manager/SDDM and KDE. Ours replace them at the same paths
    # (Steam's Switch to Desktop calls them by path); a pacman hook puts them
    # back after every update of gamescope-session-cachyos.
    info "Making the session switching GDM-aware..."
    sudo mkdir -p "$GDM_FIX_DIR"
    patch_file steamify-gdm-steam-set-session.sh | sudo install -Dm755 /dev/stdin "$GDM_FIX_DIR/steam-set-session" &&
        patch_file steamify-gdm-session-select.sh |
            sudo install -Dm755 /dev/stdin "$GDM_FIX_DIR/steamos-session-select" || { err "Installing the GDM session tools failed."; return 1; }
    patch_file steamify-gdm.hook | fill DIR="$GDM_FIX_DIR" | sudo install -Dm644 /dev/stdin "$GDM_HOOK"
    if [[ "$(current_display_manager)" == gdm || "$LOGIN_MANAGER" == gdm ]]; then
        # steamos-session-select logs in again through this helper (no password: it runs from the gaming session and from a shortcut).
        patch_file steamify-gdm-relogin.sh | sudo install -Dm755 /dev/stdin "$GDM_RELOGIN"
        echo "$TARGET_USER ALL=(root) NOPASSWD: $GDM_RELOGIN" | sudo install -Dm440 /dev/stdin "$GDM_SUDOERS"
        sudo visudo -cf "$GDM_SUDOERS" > /dev/null || { sudo rm -f "$GDM_SUDOERS"; err "The sudoers rule for GDM is invalid."; return 1; }
    fi
    for f in /usr/lib/steamos/steam-set-session /usr/bin/steamos-session-select; do
        [[ -f "$f" && ! -f "$f.bak-steamify" ]] && sudo cp -a "$f" "$f.bak-steamify"
    done
    sudo install -m755 "$GDM_FIX_DIR/steam-set-session" /usr/lib/steamos/steam-set-session &&
        sudo install -m755 "$GDM_FIX_DIR/steamos-session-select" /usr/bin/steamos-session-select || return 1
    # Start in gamescope, as with the other login managers.
    sudo /usr/lib/steamos/steam-set-session gamescope-session.desktop
    ok "GDM autologin into gamescope is set up."
}

session_tools_remove() {
    sudo rm -f "$GDM_HOOK" "$GDM_SUDOERS" "$GDM_RELOGIN"
    for f in /usr/lib/steamos/steam-set-session /usr/bin/steamos-session-select; do
        [[ -f "$f.bak-steamify" ]] && sudo mv "$f.bak-steamify" "$f"
    done
    sudo rm -rf "$GDM_FIX_DIR"
}
