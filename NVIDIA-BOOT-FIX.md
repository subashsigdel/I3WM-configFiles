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

## TODO / not yet verified
1. **Check whether routine system updates will silently break the initramfs fix.** Need to inspect the actual pacman hook that rebuilds initramfs on kernel/nvidia updates:
   ```bash
   pacman -Qlq linux-lts | grep -i hook
   cat /etc/kernel/install.conf 2>/dev/null
   find /usr/lib/kernel/install.d/ -type f 2>/dev/null
   ```
   If it has the same "writes to BLS path, not classic /boot" bug as manual `--regenerate-all`, every future kernel/nvidia update needs a manual re-run of the explicit `--kver` rebuild command above, followed by the `lsinitrd` verification.

2. **Suspend/resume untested.** Sleep re-initializes hardware similarly to boot and could plausibly re-trigger the same ACPI NVPCF race, since NVIDIA is deferred-load, not blacklisted. Test deliberately: `systemctl suspend`, then wake and confirm clean resume.

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
