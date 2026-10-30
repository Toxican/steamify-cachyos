# Troubleshooting

See [TECHNICAL.md](TECHNICAL.md) for how each part works.

## Gaming mode shows a black screen or keeps restarting

Press **Ctrl+Alt+F3**, log in with your username and password, and run:

```bash
sudo /usr/lib/steamos/steam-set-session plasma.desktop && sudo systemctl restart display-manager
```

That takes you back to the desktop. Gamescope sessions that fail to start are
restarted right away (`Relogin=true`), which is why it can loop.

## Something is set up wrong

Run the wizard again and press `a` in the menu to re-apply everything that's
on (also useful after a CachyOS update). To undo a part, untick it.

## "Target OS name ... not found in /boot/limine.conf"

limine-snapper-sync finds the boot entries by the OS name. Steamify never
changes that name (it only adds version keys to `/etc/os-release`), and pins
`TARGET_OS_NAME="CachyOS"` in `/etc/default/limine`. If you see this message,
check that `PRETTY_NAME` in `/etc/os-release` still says `CachyOS`, or set
`TARGET_OS_NAME` in `/etc/default/limine` to the name your boot entries use.

## The LED bar on the Steam Machine stays dark

Restart once more; a freshly installed driver often needs a reboot. The menu
shows per kernel whether the LED driver is built, and whether it's loaded.
Still dark:

```bash
dkms status
ls -l /sys/class/leds/valve-leds*/
sudo dmesg | grep -i valve
cat /var/lib/dkms/leds-valve-dkms/0.1/build/make.log
journalctl --user -b | grep -i led
```

## The TV remote does nothing (HDMI-CEC)

- Turn on CEC in the TV's settings (Sony: BRAVIA Sync, Samsung: Anynet+, LG:
  SimpLink) and, if it has one, allow the PC to control it.
- Check that the PC has a CEC device, and that `cecd` runs:

```bash
ls /dev/cec*
systemctl --user status cecd
journalctl --user -u cecd -b
cec-ctl -d /dev/cec0 -S        # the devices on the TV's CEC bus (v4l-utils)
```

No `/dev/cec*`: your PC has no CEC; a USB CEC adapter (e.g. Pulse-Eight)
works. See [CEC.md](CEC.md). The Steam Machine wakes up again right after going
to sleep, or other devices lose CEC? That happens on SteamOS too; turn
HDMI-CEC off in the wizard.

## Fan control / monitoring doesn't seem to work (Steam Machine)

Turning it on installs the drivers and `jupiter-fan-control`, but nothing changes until the restart Steamify asks for: the modules are never loaded while the
PC runs. After the restart:

```bash
dkms status | grep steamify-fancontrol                 # installed for every kernel
lsmod | grep steamdeck                                 # steamdeck and steamdeck_hwmon
readlink /sys/bus/acpi/devices/VLV0100:00/physical_node/driver
for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name)" = steamdeck_hwmon ] && cat $h/fan1_input $h/fan1_target; done
systemctl status jupiter-fan-control.service
```

- No `steamdeck` modules after the restart: you booted a kernel Steamify has no build for. `dkms status` shows which kernels have it; a build that failed says why
  in `/var/lib/dkms/steamify-fancontrol/1/build/make.log` (most often missing kernel headers: `ensure-kernel-headers.service` installs them at boot). A
  `linux-neptune` or Deckify kernel has both modules itself and Steamify builds nothing for it.
- Steam's own switch chooses: OS fan control means `jupiter-fan-control` is active and the target is above 0; firmware control means it is inactive and the
  target is 0 (the firmware runs the fan).
- `fan1_fault` shows 1: that attribute comes from the Steam Deck and isn't meaningful on the Steam Machine. The RPM and the control work.
- Turning it off removes the package, the drivers and the autoload file, but the loaded modules stay until the next restart. Don't `modprobe -r` them or remove
  the DKMS entry by hand.

## The Steam Machine still reboots when I shut it down

Check that the pinned kernel is installed and running:

```bash
uname -r                                   # should be 7.1.6-1-cachyos
pacman -Q linux-cachyos linux-cachyos-headers
grep '^IgnorePkg' /etc/pacman.conf         # should list both packages
```

Not running it yet? Restart. Not installed? Run the wizard and make sure
**Pin the kernel** under Steam Machine support is ticked. If you have more
kernels installed (e.g. the LTS kernel), pick `linux-cachyos` in the boot menu.

## The Steam Machine wakes up again right after going to sleep

With Wake-on-WLAN on (`iw phy phyN wowlan show`), CachyOS's Wi-Fi firmware makes the Steam Machine wake at once.
Tick **Wi-Fi firmware from SteamOS** under Steam Machine support (Wake-on-WLAN ticks it for you) and restart. Check
which build loads:

```bash
sudo dmesg | grep fw_build_timestamp       # 2025-07-16 10:46 is SteamOS's build, 10:33 is CachyOS's
```

Still waking? Find out what wakes it, with the kernel's own wake messages: turn them on, suspend once, and read them.

```bash
echo 1 | sudo tee /sys/power/pm_debug_messages
systemctl suspend                          # let it wake by itself, then:
sudo journalctl -b -g 'Triggering wakeup|Wakeup unrelated|non-EC GPE' | tail
cat /proc/acpi/wakeup                      # what may wake the machine at all
```

`IRQ 40` with "Wakeup unrelated to ACPI SCI" is the Wi-Fi adapter itself (the firmware problem above). `IRQ 1` (the keyboard
controller) together with `IRQ 9` and "ACPI non-EC GPE wakeup" a few seconds after suspending is an input device or something
else on the machine: a controller or its Puck, a keyboard, a remote session sending input, the TV over HDMI-CEC. Those
wake the machine with Wake-on-WLAN off as well, so test with it off (untick it, restart) to tell the two apart. Tested on a
Steam Machine: a Wi-Fi magic packet woke it 10 times out of 10; in about 60 suspends without a packet one woke through the Wi-Fi
adapter (IRQ 40), and a stretch with more going on (remote sessions, controllers) had several of the keyboard-controller wakes,
also with Wake-on-WLAN off.

## Wake-on-LAN or Wake-on-WLAN does nothing

Check what the network device is set to (`g` means magic packet):

```bash
sudo ethtool enp5s0 | grep Wake-on         # wired: should say g
ls -l /etc/NetworkManager/dispatcher.d/90-steamify-wowlan   # Wi-Fi: enables it when the Wi-Fi connects
ls -l /usr/lib/systemd/system-sleep/steamify-wowlan         # and again right before every sleep
```

Wired not `g`? Restart, or reconnect the network. Wi-Fi: `iw phy phy0 wowlan show` should say "enabled" once the Wi-Fi is
connected (the dispatcher script turns it on then; with only the 2.14.0 or 2.14.1 hook it said "disabled" until the first sleep,
and that first sleep did not wake on a packet: update Steamify). Test with a magic packet for the Wi-Fi adapter's MAC address. Both wake the machine from **sleep** only. A power-off doesn't work on the
Steam Machine (tried with the BIOS's "S4/S5 WoL" on: the machine stayed off), so after a shutdown it is started with the power button. The
magic packet must go to the MAC address of the device that is connected.

## `pacman -Syu` (or every `pacman -S`) fails and mentions `steamify-...`

Steamify lists its own package repository (`[steamify-znver4]`, `[steamify-v3]`, ... at the end of `/etc/pacman.conf`) so the patched gamescope and the Steam
Machine's drivers update with the system. Like any extra repository, when it can't be used pacman stops for the whole system:

- `error: failed retrieving file 'steamify-....db' ... failed to synchronize all databases`: GitHub (where the repository is hosted) is unreachable or the file is
  missing. Usually gone by itself in minutes; try again later.
- `key "767F317A..." is unknown` / `database 'steamify-...' is not valid (invalid or corrupted database (PGP signature))`: the PC doesn't trust the repository's
  signing key. The `steamify-keyring` package normally keeps that current; it can fall behind when the PC missed an update of it.

Steamify repairs this by itself: every run first checks the repository (what the next `pacman -Syu` would do), and when it doesn't verify it puts the pinned key
back, installs the newest `steamify-keyring` and fetches the database again (`steamify.sh --repair-repo` does just that). Only when the repository can be reached but
still can't be used, it takes the repository out of `pacman.conf` so pacman keeps working. With no connection it changes nothing.

To get pacman working again at once, take the repository out (what it installed stays installed, it just stops updating):

    steamify.sh --remove-repo

or, without Steamify, `sudo sed -i '/^# Steamify: packages from steamify-pacman-repo/,+3d' /etc/pacman.conf`. To list it again later: `steamify.sh --add-repo`
(it also comes back by itself the next time an option that uses it is applied). If the key was the problem, a newer Steamify has the new one.

## The kernel pin can't download or verify the kernel

The wizard tries this repo's `kernel-7.1.6-1` release, then the CachyOS
archive and mirror. A file that fails its checksum or CachyOS signature is
deleted, so running the wizard again downloads it once more. Offline? Put
the four files from the
[kernel-7.1.6-1 release](https://github.com/theupriser/steamify-cachyos/releases/tag/kernel-7.1.6-1)
in `/var/cache/steamify/kernel` and run it again.

