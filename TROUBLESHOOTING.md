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
ls -l /usr/lib/systemd/system-sleep/steamify-wowlan   # Wi-Fi: the hook that enables it before every sleep
```

Wired not `g`? Restart, or reconnect the network. Wi-Fi: `iw phy phy0 wowlan show` says "disabled" while the machine is
awake; the hook turns it on right before it sleeps, so look at it from a second ssh session during a sleep, or test with a
magic packet for the Wi-Fi adapter's MAC address. Wired wake from power-off also needs wake-on-LAN in the BIOS (and not an
energy-saving mode that cuts the network card's power). Wi-Fi wakes from sleep only, never from power-off. The magic
packet must go to the MAC address of the device that is connected.

## The kernel pin can't download or verify the kernel

The wizard tries this repo's `kernel-7.1.6-1` release, then the CachyOS
archive and mirror. A file that fails its checksum or CachyOS signature is
deleted, so running the wizard again downloads it once more. Offline? Put
the four files from the
[kernel-7.1.6-1 release](https://github.com/theupriser/steamify-cachyos/releases/tag/kernel-7.1.6-1)
in `/var/cache/steamify/kernel` and run it again.

