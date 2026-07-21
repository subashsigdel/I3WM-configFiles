# Boot hang + NVIDIA GPU issue — EndeavourOS on Acer (Core 5 210H / RTX 3050)

## Hardware / software
- Acer laptop, Intel Core 5 210H (Raptor Lake-P iGPU), Nvidia RTX 3050 6GB (GA107, Optimus/hybrid), NVMe SSD, Insyde UEFI.
- EndeavourOS, GRUB bootloader, classic `/boot` layout (not systemd-boot), dracut initramfs.
- Kernels: `linux 7.1.4-arch1-1`, `linux-lts 6.18.39-1`.
- `nvidia-open-dkms 610.43.03-3` (the only officially supported driver for this GPU — Arch dropped proprietary `nvidia`/`nvidia-dkms` from repos as of the 590 driver release; legacy proprietary only exists as `nvidia-580xx-dkms` in the AUR).

## Problem 1 (fixed): boot hangs forever at "A start job is running for /dev/disk/by-uuid/... (no limit)"
**Cause**: EndeavourOS's dracut drop-ins (`/etc/dracut.conf.d/eos_intel_i915.conf`, `eos_nvidia_open.conf`) had `force_drivers+=" i915 "` / `force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "`. This makes dracut's `pre-udev` hook run `modprobe` on these synchronously, **before** `systemd-udevd` starts. One of these calls could block forever, so `systemd-udevd` never started, `/dev/disk/by-uuid/` was never populated, and boot hung indefinitely.

**Fix**: commented out `force_drivers` in both files.

## Problem 2 (fixed): after fixing #1, boot still hung later at "dracut initqueue hook"
**Cause**: even without forcing early load, NVIDIA still auto-loaded during the initramfs stage via normal udev coldplug (modalias match). This hit a genuine **NVIDIA driver bug**: `rm_acpi_nvpcf_notify` (NVIDIA's ACPI NVPCF/Dynamic-Boost power-sharing handler) deadlocks against `kgspInitRm` (GSP firmware init) via a kernel rw-semaphore lock inversion — confirmed via `dmesg`/kernel hung-task detector:
```
kernel: INFO: task (udev-worker):343 blocked for more than 245 seconds.
task:(udev-worker) state:D ... blocked on an rw-semaphore likely owned by task kworker/9:0
```
Stuck call stack: `rm_acpi_nvpcf_notify → ... → kgspInitRm_IMPL → RmInitAdapter → ... → nv_drm_probe_devices`.

This is a known, unfixed upstream bug (see NVIDIA/open-gpu-kernel-modules Discussion #677, Issue #860) — not specific to this hardware, though Insyde firmware + very new laptop ACPI tables seem to correlate with reports.

**Fix**: `omit_drivers+=" nvidia nvidia_drm nvidia_modeset nvidia_uvm "` added to `/etc/dracut.conf.d/eos_nvidia_open.conf`. This keeps NVIDIA out of the initramfs entirely — it loads later, in normal userspace after switch-root, outside the boot-critical `dracut-initqueue` wait. Confirmed via `lsinitrd /boot/initramfs-*.img | grep nvidia` after every rebuild.

Also set (belt-and-suspenders, does not fully prevent the bug on its own): `/etc/modprobe.d/nvidia-power.conf` → `options nvidia NVreg_DynamicPowerManagement=0x00`.

**Not applied (available as emergency rescue only)**: a full `/etc/modprobe.d/blacklist-nvidia.conf` blacklisting `nvidia`/`nvidia_drm`/`nvidia_modeset`/`nvidia_uvm` — this guarantees no hang ever, at the cost of the GPU never being usable at all. Kept as a documented fallback, not currently active. The deferred-load approach (`omit_drivers`) was chosen instead so the GPU stays usable via PRIME offload.

## Important gotcha: `dracut --force --regenerate-all` writes to the WRONG path on this system
Running the "normal" full regenerate command:
```
sudo dracut --force --regenerate-all
```
silently succeeds but writes into the ESP's BLS-style folder (`/boot/efi/<machine-id>/<kernel-version>/`), **not** the classic `/boot/initramfs-linux.img` / `/boot/initramfs-linux-lts.img` that GRUB's `grub.cfg` actually boots (confirmed by comparing file timestamps — the classic images stayed stale after a "successful" regenerate-all run).

**Always rebuild explicitly instead**, targeting the real files:
```bash
sudo dracut --force --kver 6.18.39-1-lts /boot/initramfs-linux-lts.img
sudo dracut --force --kver 7.1.4-arch1-1 /boot/initramfs-linux.img
```
Then verify:
```bash
lsinitrd /boot/initramfs-linux.img | grep -iE "nvidia\.ko|i915\.ko"
ls -la /boot/*.img   # timestamps should be fresh
```
**This needs to be double-checked after every future kernel/nvidia package update** — if the automatic pacman hook has the same bug, routine `pacman -Syu` could silently leave a stale initramfs. Not yet verified — see TODO.

## Problem 3 (fixed): black screen after login (lightdm/X crash)
Two separate causes stacked here:

1. **`/usr/share/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf`** (auto-installed by `nvidia-utils`) has `MatchDriver "nvidia-drm"` + `Option "AllowEmptyInitialConfiguration"`, which adds the NVIDIA GPU as an X screen any time `nvidia_drm` is loaded — even with zero connected displays (both `DFP-0`/`DFP-1` show `disconnected`, since the panel is wired to Intel only). This produced a dead 640x480 virtual screen.
   **Fix**: masked with an empty override at `/etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf` (same filename, `/etc` takes precedence over `/usr/share`).

2. **X's default `AutoAddGPU` behavior** still auto-probed the second (NVIDIA) DRM device even with an explicit Intel-only `Device`/`Screen` config, and this probe failing was fatal (`Fatal server error: failed to create screen resources`), crash-looping lightdm into `start-limit-hit`.
   **Fix**: `/etc/X11/xorg.conf.d/10-intel-only.conf` — explicit `Device "IntelGPU"` (`Driver "modesetting"`, `BusID "PCI:0:2:0"`), `Screen "Screen0"`, and `ServerLayout` with `Option "AutoAddGPU" "false"`.

PCI bus IDs on this hardware (for reference): Intel iGPU `0000:00:02.0` → `PCI:0:2:0`; NVIDIA RTX 3050 `0000:01:00.0` → `PCI:1:0:0`.

## Current state (as of last verified reboot)
- Boot: fast, no hang.
- Shutdown: clean, no stuck `udev-worker`.
- Desktop: comes up automatically on lightdm, Intel graphics only, no manual intervention.
- NVIDIA GPU: not blacklisted, loads normally post-boot, available for CUDA / PRIME render offload:
  ```bash
  nvidia-smi
  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only <app>
  ```

## Recovery runbook: if a boot hang happens again

The underlying driver bug is still unpatched upstream — it can theoretically fire on any boot. Two different scenarios, depending on how bad it is:

### Scenario A — Desktop boots fine, but NVIDIA didn't load (the expected failure mode post-fix)
Symptoms: you're logged in, i3/polybar is working, but `nvidia-smi` fails or the GPU polybar widget shows nothing.

```bash
# 1. Confirm this is actually what's happening
nvidia-smi
# error like "NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver" confirms it

# 2. Check if the driver hung trying to load
journalctl -k -b 0 --no-pager | grep -iE "blocked for more than|kgspInitRm|rm_acpi_nvpcf_notify"

# 3. Try reloading the driver stack cleanly
sudo rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null
sudo modprobe nvidia_drm modeset=1

# 4. Verify it's back
nvidia-smi
```
If step 3 itself hangs (rare — rmmod/modprobe just sit there with no output for over a minute), don't fight it: skip to a normal reboot. This scenario doesn't require touching any config — nothing was reverted, the driver just needs a fresh load attempt.

### Scenario B — Full boot hang (the old-style symptom, screen frozen, no progress)
Symptoms: stuck at a boot message (e.g. `A start job is running for /dev/disk/by-uuid/...` or `dracut initqueue hook`) for over 2–3 minutes with zero progress.

```bash
# 1. Wait it out first — genuinely confirm it's hung, not just slow
#    (default hung_task_timeout is 120s; give it a clean 3 minutes before acting)

# 2. Hard power off: hold the power button ~10 seconds. Then power back on.

# 3. At the GRUB menu, do NOT just press Enter on the normal entry.
#    Press 'e' to edit it first (one-time edit, not saved).

# 4. Find the line starting with "linux" (the kernel command line).
#    Go to the end of that line and append:
module_blacklist=nvidia,nvidia_drm,nvidia_modeset,nvidia_uvm

# 5. Press Ctrl+X (or F10) to boot with this one-time edit.
#    This boots Intel-only, guaranteed — NVIDIA never loads, so it can't hang.
```
This gets you back to a working desktop with zero NVIDIA (no GPU acceleration, no PRIME offload) until you're ready to investigate further. It's non-persistent — next normal boot goes back to trying NVIDIA as usual, so you don't need to undo anything.

### After recovering from either scenario — verify nothing got reverted
```bash
grep omit_drivers /etc/dracut.conf.d/eos_nvidia_open.conf
cat /etc/modprobe.d/nvidia-power.conf
cat /etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf   # should be empty
cat /etc/X11/xorg.conf.d/10-intel-only.conf
ls -la /boot/initramfs-linux*.img                          # timestamps, sanity check
```
If any of these are missing or different from what's documented above under "Config files touched," that's your actual root cause — restore from this doc's documented content, not from guessing.

### If Scenario B keeps recurring
A single Scenario-B hang could be a fluke; if it happens more than once, that's a sign the current workaround (deferred-load) is no longer sufficient and it's time to move to one of the two permanent-fix paths already identified in TODO #3 below (ACPI table override, or legacy `nvidia-580xx-dkms` with `NVreg_EnableGpuFirmware=0`), rather than continuing to rely on the boot-order workaround.

## TODO / not yet verified
1. **Verified safe (2026-07-21): routine system updates will NOT silently break the initramfs fix.** Inspected the actual pacman hook that fires on kernel/nvidia updates — `/usr/share/libalpm/hooks/90-dracut-install.hook`, triggered on `usr/lib/modules/*/vmlinuz` and `usr/src/*/dkms.conf` (covers both `linux`/`linux-lts` and `nvidia-open-dkms` updates). It runs EndeavourOS's own `/usr/share/libalpm/scripts/dracut-install` script, **not** the generic `dracut --regenerate-all` — that script explicitly targets the real classic path:
   ```bash
   dracut --force --hostonly --no-hostonly-cmdline /boot/initramfs-${pkgbase}.img "${kver}"
   dracut --force --no-hostonly /boot/initramfs-${pkgbase}-fallback.img "${kver}"
   ```
   This is the same explicit `--kver`-targeted form recommended above for manual rebuilds, not the buggy BLS/ESP path. Since `dracut` always reads `/etc/dracut.conf.d/*.conf` regardless of invocation, `omit_drivers` is respected automatically on every future kernel/nvidia update — no manual intervention needed for this specific concern. (Still not a bad idea to spot-check `lsinitrd /boot/initramfs-linux.img | grep nvidia` once after a big kernel jump, just as a sanity check — but it's no longer a required step.)

2. **Suspend/resume: tested once (2026-07-21), passed.** Lid close (`HandleLidSwitch=suspend`, systemd default, no override needed) triggered a full `systemctl suspend` → clean `S3` resume in ~13s, confirmed via `journalctl -k`:
   ```
   PM: suspend entry (deep) → ACPI: PM: Waking up from system sleep state S3 → PM: suspend exit
   ```
   wifi reassociated automatically afterward, `xss-lock` correctly showed the lock screen on wake (expected — not a bug). Same boot session throughout (`uptime`/`who -b` confirmed no reboot).

   **One non-fatal anomaly seen during that resume, worth watching**: `NVRM: rm_power_source_change_event: Failed to handle Power Source change event, status=0x11` — the NVIDIA driver failed to process an AC/battery power-source-change event right at resume. Didn't block or delay the resume this time, but it's in the same power-management codepath (NVPCF-adjacent) as the original boot deadlock. Not urgent, but if a hang is ever seen on resume in the future, check for this line first.

   Single successful test isn't full confidence — if you suspend/resume often, worth repeating a few more times (including resuming on battery vs. AC, since the failed event was a power-*source* event) before fully trusting it unattended.

3. **Not a real fix yet, just a stable workaround.** The root NVIDIA driver bug (`rm_acpi_nvpcf_notify` lock inversion) is still present upstream. Two paths to a permanent fix if the current workaround ever proves insufficient:
   - ACPI table override to neutralize the `NPCF` device's `Notify(NPCF, 0xC0/0xC1)` calls (documented, manual, fragile — must be redone after BIOS updates).
   - Legacy proprietary `nvidia-580xx-dkms` (AUR) + `NVreg_EnableGpuFirmware=0` (skips GSP init entirely, sidesteps the deadlock at the cost of an older/unsupported driver branch).

4. **`i915` early-KMS** (`force_drivers+=" i915 "` in a dracut conf, safe since the bug is NVIDIA-specific) was discussed as a polish item for more consistent display bring-up but never applied — optional, not required for stability.

## Config files touched (full list — this is your safety net; if any of these get reverted, symptoms may return)
- `/etc/dracut.conf.d/eos_intel_i915.conf` — `force_drivers` commented out
- `/etc/dracut.conf.d/eos_nvidia_open.conf` — `force_drivers` commented out, `omit_drivers` added
- `/etc/modprobe.d/nvidia-power.conf` — `NVreg_DynamicPowerManagement=0x00`
- `/etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf` — empty (masks `/usr/share` version)
- `/etc/X11/xorg.conf.d/10-intel-only.conf` — Intel-only pin, `AutoAddGPU=false`
- `/boot/initramfs-linux.img`, `/boot/initramfs-linux-lts.img` — manually rebuilt with explicit `--kver`
