#!/bin/bash
# "HDMI-CEC volume" menu item (cecaudio), a default sub-option of HDMI-CEC on the Steam Machine (#107): Steam's
# TV Volume buttons (-, +, mute) in the Audio settings, like on SteamOS, instead of a slider that does nothing for
# the TV. They need three things: cec-audio-control (from HDMI-CEC), a WirePlumber rule that hands the HDMI
# output's volume to it, and Valve's builds of PipeWire and WirePlumber: the ALSA plugin of Valve's PipeWire
# (`api.alsa.external-volume-control`) and its WirePlumber (`monitor.alsa.enable-external-volume-control`) carry
# the patch; CachyOS's have neither.
#
# Valve's builds replace CachyOS's (a different version, 1.6.8 against 1.6.10 at the time). So that `pacman -Syu`
# doesn't undo it, and still keeps them up to date, they live in a local pacman repository that is listed before
# CachyOS's repositories; patches/steamify-valve-audio.sh fills it from Valve's newest jupiter-X.Y (64-bit) and
# multilib-X.Y (32-bit) repositories, weekly by a timer and when the option is turned on.
# Sourced by steamify.sh; not meant to be run on its own.

VALVE_AUDIO_REPO=steamify-valve-audio
VALVE_AUDIO_DIR=/var/lib/steamify/valve-audio
VALVE_AUDIO_SCRIPT=/usr/local/lib/steamify/steamify-valve-audio
VALVE_AUDIO_UNIT=steamify-valve-audio
PACMAN_CONF=/etc/pacman.conf
VALVE_AUDIO_MARKER="# Steamify: Valve's PipeWire and WirePlumber for the TV volume buttons (HDMI-CEC), refreshed weekly"
# The user's own WirePlumber config: /etc/wireplumber is a symlink to /run/wireplumber (steamdeck-dsp, which Valve's
# PipeWire pulls in), a directory that doesn't exist.
CECAUDIO_WP_CONF="$HOME/.config/wireplumber/wireplumber.conf.d/90-steamify-cec-volume.conf"
# The empty directories CachyOS's libpipewire owns; Valve's pipewire package has symlinks there (to /run/pipewire),
# and pacman doesn't turn a directory into a symlink.
CECAUDIO_PW_DIRS=(/etc/pipewire/client.conf.d /etc/pipewire/client-rt.conf.d)

cecaudio_available() { detect_valve_fremont; }

# On = the local repository is listed and the WirePlumber rule is there. A newer build in the repository than the
# installed one is a normal `pacman -Syu` away, so it doesn't turn this off.
cecaudio_status() {
    grep -q "^\[$VALVE_AUDIO_REPO\]" "$PACMAN_CONF" 2>/dev/null && [[ -f "$CECAUDIO_WP_CONF" ]]
}

cecaudio_conf_add() {
    grep -q "^\[$VALVE_AUDIO_REPO\]" "$PACMAN_CONF" && return 0
    backup_file "$PACMAN_CONF"
    local tmp; tmp="$(mktemp)"
    # Before the first repository: the first one that has a package decides which version pacman takes.
    awk -v marker="$VALVE_AUDIO_MARKER" -v repo="$VALVE_AUDIO_REPO" -v dir="$VALVE_AUDIO_DIR" '
        /^\[/ && $0 != "[options]" && !done {
            print marker; print "[" repo "]"; print "SigLevel = Optional TrustAll"; print "Server = file://" dir; print ""
            done = 1
        }
        { print }
        END { if (!done) { print ""; print marker; print "[" repo "]"; print "SigLevel = Optional TrustAll"; print "Server = file://" dir } }
    ' "$PACMAN_CONF" >"$tmp"
    sudo install -m644 "$tmp" "$PACMAN_CONF"
    rm -f "$tmp"
}

cecaudio_conf_remove() {
    grep -q "^\[$VALVE_AUDIO_REPO\]" "$PACMAN_CONF" 2>/dev/null || return 0
    local tmp; tmp="$(mktemp)"
    awk -v marker="$VALVE_AUDIO_MARKER" '
        $0 == marker { skip = 1; next }
        skip && /^\[/ && !seen { seen = 1; next }
        skip && /^(SigLevel|Server) *=/ { next }
        skip { skip = 0; if ($0 == "") next }
        { print }
    ' "$PACMAN_CONF" >"$tmp"
    sudo install -m644 "$tmp" "$PACMAN_CONF"
    rm -f "$tmp"
}

cecaudio_wp_conf_write() {
    # Matches the HDMI sound card (the Steam Machine's GPU) and gives its sink the property Valve's PipeWire reads,
    # the socket of cec-audio-control (socket-activated by the first request; it is enabled by HDMI-CEC).
    mkdir -p "$(dirname "$CECAUDIO_WP_CONF")"
    cat >"$CECAUDIO_WP_CONF" <<EOF
# Written by Steamify (HDMI-CEC volume): the TV's volume buttons in Steam's Audio settings.
context.properties = {
  support.varlink = true
}

monitor.alsa.rules = [
  {
    matches = [ { device.name = "~alsa_card.pci-.*", api.alsa.card.name = "~.*HDMI.*" } ]
    actions = {
      update-props = {
        device.description = "HDMI / DisplayPort"
        api.alsa.external-volume-control = "unix:/run/user/$(id -u)/cec-audio-control/org.pipewire.ExternalVolume"
        steamos.supports-hdmi-cec = true
      }
    }
  }
]

wireplumber.settings = {
  monitor.alsa.enable-external-volume-control = true
}
EOF
}

cecaudio_restart_audio() {
    user_systemctl restart pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null
    # Sunshine's virtual sound devices live in PipeWire: they come back with it.
    user_systemctl try-restart sunshine.service 2>/dev/null
}

cecaudio_enable() {
    local before after p pkgs=() extras=() known
    command -v repo-add >/dev/null 2>&1 || { err "repo-add (part of pacman) is missing."; return 1; }
    cec_installed || { err "HDMI-CEC has to be on first."; return 1; }
    sudo install -d "$(dirname "$VALVE_AUDIO_SCRIPT")"
    patch_file steamify-valve-audio.sh | sudo tee "$VALVE_AUDIO_SCRIPT" >/dev/null
    sudo chmod 755 "$VALVE_AUDIO_SCRIPT"
    info "Fetching Valve's PipeWire and WirePlumber (checksums from Valve's package index)..."
    sudo "$VALVE_AUDIO_SCRIPT" refresh || { err "Fetching Valve's audio packages failed."; return 1; }
    cecaudio_conf_add
    for p in "${CECAUDIO_PW_DIRS[@]}"; do
        [[ -d "$p" && ! -L "$p" ]] && sudo rmdir "$p" 2>/dev/null
    done
    mapfile -t pkgs < <(pacman -Sl "$VALVE_AUDIO_REPO" 2>/dev/null | awk '{ print $2 }')
    [[ ${#pkgs[@]} -gt 0 ]] || { cecaudio_conf_remove; err "Valve's audio repository is empty."; return 1; }
    before="$(pacman -Qq)"
    info "Replacing PipeWire and WirePlumber by Valve's build: ${pkgs[*]}"
    if ! sudo pacman -S --needed --noconfirm "${pkgs[@]}"; then
        err "Installing Valve's audio packages failed; CachyOS's stay."
        cecaudio_conf_remove
        return 1
    fi
    # Valve's packages pull in packages of their own (steamdeck-dsp, noisetorch): remember them to remove them again.
    after="$(pacman -Qq)"
    mapfile -t extras < <(comm -13 <(sort <<<"$before") <(sort <<<"$after"))
    known="$(state_get cecaudio pkgs)"
    for p in "${pkgs[@]}"; do [[ " $known " == *" $p "* ]] || known+="${known:+ }$p"; done
    state_set cecaudio pkgs "$known"
    if [[ ${#extras[@]} -gt 0 ]]; then
        local old_extras; old_extras="$(state_get cecaudio extra_pkgs)"
        for p in "${extras[@]}"; do [[ " $old_extras " == *" $p "* ]] || old_extras+="${old_extras:+ }$p"; done
        state_set cecaudio extra_pkgs "$old_extras"
    fi
    cecaudio_wp_conf_write
    service_file "$VALVE_AUDIO_UNIT.service" VALVE_AUDIO_SCRIPT="$VALVE_AUDIO_SCRIPT" | sudo tee "/etc/systemd/system/$VALVE_AUDIO_UNIT.service" >/dev/null
    service_file "$VALVE_AUDIO_UNIT.timer" | sudo tee "/etc/systemd/system/$VALVE_AUDIO_UNIT.timer" >/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$VALVE_AUDIO_UNIT.timer" >/dev/null 2>&1
    cecaudio_restart_audio
    ok "HDMI-CEC volume on: Steam shows the TV's volume buttons from its next start (restart gaming mode)."
    warn "PipeWire and WirePlumber are Valve's builds now, kept in step with SteamOS (not with CachyOS); audio behaviour may differ."
}

cecaudio_disable() {
    info "Removing HDMI-CEC volume (Valve's audio packages)..."
    local pkgs extras p
    pkgs="$(state_get cecaudio pkgs)"
    extras="$(state_get cecaudio extra_pkgs)"
    sudo systemctl disable --now "$VALVE_AUDIO_UNIT.timer" >/dev/null 2>&1
    sudo rm -f "/etc/systemd/system/$VALVE_AUDIO_UNIT.timer" "/etc/systemd/system/$VALVE_AUDIO_UNIT.service" "$VALVE_AUDIO_SCRIPT"
    sudo rmdir "$(dirname "$VALVE_AUDIO_SCRIPT")" 2>/dev/null
    sudo systemctl daemon-reload
    rm -f "$CECAUDIO_WP_CONF"
    rmdir "$(dirname "$CECAUDIO_WP_CONF")" "$(dirname "$(dirname "$CECAUDIO_WP_CONF")")" 2>/dev/null
    cecaudio_conf_remove
    sudo rm -f /var/lib/pacman/sync/"$VALVE_AUDIO_REPO".db*
    sudo rm -rf "$VALVE_AUDIO_DIR"
    sudo rmdir "$(dirname "$VALVE_AUDIO_DIR")" 2>/dev/null
    # CachyOS's repositories are the only ones left: the same packages come back from them.
    if [[ -n "$pkgs" ]]; then
        # shellcheck disable=SC2086
        sudo pacman -S --noconfirm $pkgs || warn "Putting CachyOS's audio packages back failed: run  sudo pacman -S $pkgs"
    fi
    for p in $extras; do sudo pacman -Rns --noconfirm "$p" >/dev/null 2>&1; done
    state_clear cecaudio
    cecaudio_restart_audio
    ok "HDMI-CEC volume removed: CachyOS's PipeWire and WirePlumber are back."
}
