# gpu-vacate

Move the GNOME desktop off your discrete GPU and onto the integrated one, so the dGPU's
VRAM and compute are all yours for AI, rendering or other compute work. Move it back
when you're done.

```console
$ gpu-vacate on      # desktop → iGPU (log out/in); the discrete GPU(s) sit idle
$ gpu-vacate off     # desktop → dGPU again
$ gpu-vacate on --keep   # same as on, but stays vacated across reboots until off
```

It's for **desktop PCs** with one monitor cabled to both GPUs: for example DisplayPort
from the graphics card and HDMI from the motherboard. Switching takes a log out and back
in, with no reboot, and the monitor's input follows along over DDC/CI.

## Why

A GNOME session on the dGPU holds a few hundred MiB of VRAM (about 400 MiB on a 5120x1440
desktop) and keeps the card's clocks up. With the desktop on the iGPU, the dGPU drops to
~50 MiB and a few watts, and every byte of VRAM goes to your model.

Laptop GPU switchers (system76-power's compute mode, supergfxctl, envycontrol,
optimus-manager) cover laptops, need a reboot, and don't deal with a monitor wired to
both GPUs. The compositor settings (mutter's udev tag, `KWIN_DRM_DEVICES`,
`AQ_DRM_DEVICES`) pick a GPU once and leave it. gpu-vacate makes it a toggle.

## What it does

- Tells mutter to render on the iGPU, with its `mutter-device-preferred-primary` udev
  tag, toggled live (no reboot).
- Turns off the output on the other GPU with `gdctl` and saves that layout, so GNOME
  doesn't keep drawing on a monitor you can't see, or come back from suspend on the
  wrong input.
- Switches the monitor's input over DDC/CI (optional, needs `ddcutil`).
- Puts the monitor on the boot GPU's input at boot and shutdown, so the firmware setup,
  the boot loader and other operating systems are visible.
- Starts every boot in normal mode (the flag lives in `/run`), unless you vacated with
  `gpu-vacate on --keep`: then every boot comes up on the iGPU, monitor on its input,
  until you run `gpu-vacate off`.

## Requirements

- GNOME 48 or newer on Wayland (for `gdctl`), systemd and udev
- An integrated GPU enabled in the BIOS, plus one or more discrete GPUs
- One monitor connected to both: one cable to the dGPU, one to the motherboard
- Optional: `ddcutil` and a monitor with DDC/CI turned on, for input switching

Tested on Debian 13 (GNOME 48.7, kernel 6.12) with a Ryzen 9 7950X3D (Raphael iGPU), two
RX 7900 XTX and a Samsung Odyssey G9 (G91SD). Intel iGPUs and NVIDIA dGPUs should work,
since mutter's tag is driver-independent, but they haven't been tested.

## Install

```console
$ git clone https://github.com/matthewlenz/gpu-vacate.git
$ cd gpu-vacate
$ sudo make install
```

This installs to `/usr/local`, creates the `gpu-vacate` group and adds you to it. **Log
out and back in** once so the group membership takes effect. Bash completion and a
man page (`man gpu-vacate`) are installed too.

Then set the monitor's input codes in `/etc/gpu-vacate.conf` (see
[Monitor input](#monitor-input)) and try it:

```console
$ gpu-vacate status
$ gpu-vacate on
```

Packagers: `make install DESTDIR=… PREFIX=/usr UDEVRULESDIR=/usr/lib/udev/rules.d
UNITDIR=/usr/lib/systemd/system BASHCOMPDIR=/usr/share/bash-completion/completions MANDIR=/usr/share/man`
installs the files only; enable
`gpu-vacate-trigger.path`, `gpu-vacate-restore.service` and
`gpu-vacate-firmware-input.service` in the package scripts.

## Usage

| Command | |
|---|---|
| `gpu-vacate status` | mode, the GPU the session renders on, each GPU's VRAM use and outputs |
| `gpu-vacate on` | render the desktop on the iGPU, until the next reboot |
| `gpu-vacate on --keep` | the same, and keep it on the iGPU across reboots until `off` |
| `gpu-vacate off` | render the desktop on the dGPU |
| `gpu-vacate inputs` | show the monitor's current input code on each connected output |
| `gpu-vacate sync` | re-apply outputs and input for the current mode (runs at login) |

`on` and `off` turn on the target GPU's output and point the monitor at it. GNOME then
asks **"Keep these display settings?"**: click *Keep Changes* (it only saves the layout
once confirmed), press Enter in the terminal, and log out when it offers to. After you
log back in, `gpu-vacate status` should show the session on the new GPU.

With `--keep`, `on` also leaves a mark in `/var/lib/gpu-vacate`. At each boot,
`gpu-vacate-restore.service` then re-vacates before the login screen starts, and the
monitor is switched to the iGPU's input (the firmware and boot loader still show on the
boot GPU's input, as usual). `gpu-vacate off` clears it; running `gpu-vacate on` again (without
`--keep`) makes it last only until the next reboot.

## Configuration

`/etc/gpu-vacate.conf`:

| Setting | |
|---|---|
| `DESKTOP_GPU` | the GPU the desktop moves to. Empty: the integrated GPU, found automatically. Or a PCI ID (`1002:164e`) or address (`0000:5c:00.0`) from `gpu-vacate status` |
| `INPUT_DGPU`, `INPUT_IGPU` | the monitor's DDC/CI input codes (VCP 0x60) for each cable. Empty: switch by hand |
| `FIRMWARE_INPUT` | `yes`: switch to the boot GPU's input at boot and shutdown |

### Monitor input

Input codes vary between monitors. Find yours:

1. With the monitor showing the dGPU's input, run `gpu-vacate inputs` and note the code.
2. Switch the monitor to the iGPU's input from its own menu and run it again.
3. Put the two codes in `INPUT_DGPU` and `INPUT_IGPU`.

The MCCS standard says DisplayPort-1 is `0x0f` and HDMI-1 is `0x11`, but monitors differ:
the Samsung Odyssey G9 uses `0x05` for its HDMI 2.1 port and ignores `0x11`. You need
read/write access to `/dev/i2c-*`: Debian's ddcutil package grants it to the logged-in
user. Elsewhere, join the `i2c` group.

## How it works

- `/run/gpu-vacate/cardN` existing means "vacated, render on cardN". A udev rule tags
  that card `mutter-device-preferred-primary`, and `gpu-vacate-trigger.path` re-runs udev
  on the DRM cards whenever the flag directory changes.
- Mutter reads that tag from udev's *current* tags when GNOME starts, so the next login
  renders on the tagged GPU. (`mutter-device-ignore` would hide the dGPU completely, but
  mutter reads it from udev's sticky tag list, so it can't be removed again until a
  reboot. gpu-vacate doesn't use it.)
- `gdctl set --persistent` enables only the active GPU's output and saves it to
  `~/.config/monitors.xml`. A login autostart entry (`gpu-vacate sync`) fixes the layout
  temporarily if it doesn't match the mode, e.g. after rebooting while vacated.
- `/var/lib/gpu-vacate/keep` (from `on --keep`) makes `gpu-vacate-restore.service`
  recreate the flag at boot, before the login screen. It finds the iGPU again, since
  card numbers can change between boots.
- With the desktop on the iGPU, the dGPU only runs your compute jobs; a dGPU with nothing
  on it can runtime-suspend.

## Troubleshooting

**The iGPU's HDMI doesn't offer the panel's full resolution.** Some monitors only list
their native mode in the DisplayPort EDID. If the HDMI link can carry it, add a kernel
parameter like `video=HDMI-A-3:5120x1440MR@60` (the `M` makes it a CVT mode and `R`
reduced blanking; without `M`, the kernel uses GTF and ignores `R`). Use the iGPU's
connector name from `ls /sys/class/drm`. It changes when you add or remove a GPU.

**The login screen is grey on one input.** GDM uses its own monitor config and extends
the desktop across both outputs, so the login box may be on the other one. Put a
`monitors.xml` that mirrors both outputs in GDM's config directory
(`/var/lib/gdm3/.config/` on Debian).

**Scaling reset to 100% after a GPU change.** Adding or removing a GPU renames the
connectors, which GNOME treats as a new monitor setup. Set the scale once in Settings;
gpu-vacate carries the current scale over on each switch.

**"udev didn't pick up the change".** Check `systemctl status gpu-vacate-trigger.path`
and `udevadm info /dev/dri/cardN | grep CURRENT_TAGS`.

**Several GPUs match / no integrated GPU found.** Set `DESKTOP_GPU` to the iGPU's PCI ID
from `gpu-vacate status`.

## Uninstall

Run `gpu-vacate off` and log out/in first, then:

```console
$ sudo make uninstall
```

`/etc/gpu-vacate.conf` and the `gpu-vacate` group are kept.

## License

MIT
