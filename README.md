# droid-config-sweet

Sailfish OS device configuration for the Xiaomi Redmi Note 10 Pro
(`sweet`, Snapdragon 732G / sm6150, aarch64).

Base: `hybris-23.2` on LineageOS 23.2 (Android 16).

Built as part of a from-scratch community port. Companion repositories:

| repo | what |
|---|---|
| `droid-hal-version-sweet` | version package |
| `droid-hal-sweet` | tree-root `rpm/` spec and the `repo` local manifest |
| `hybris-patches` (fork) | patches to the Android tree this port needs |
| `droidmedia` (fork) | droidmedia built against an Android 16 base |
| `droid-hal-device` (fork) | one addition to `droid-hal-device.inc` |
| `android_kernel_xiaomi_sm6150` (fork) | defconfig changes |

## Device-specific pieces worth knowing about

- `sparse/usr/libexec/droid-hybris/vendor/lib64/` - **empty on purpose**, see the
  README there. Audio does not work without it.
- `sparse/usr/lib/systemd/system/droid-vendor-lib64-overlay.service` - layers the
  above in front of `/vendor/lib64` with a read-only overlay mount.
- `sparse/usr/bin/droid/sweet-audio-mixer-defaults.sh` - puts the PRI MI2S link
  into 24-bit/96 kHz before PulseAudio starts, which the two Awinic AW882xx
  speaker amplifiers require. Xiaomi sets this from a mixer-path overlay that
  only their 32-bit audio HAL can read.
- `sparse/usr/lib/systemd/system/qcacld-wlan-enable.service` - writes `ON` to
  `/dev/wlan`; qcacld-3.0 creates no netdev until userspace asks.
- `sparse/etc/dconf/db/vendor.d/50-sweet-display-cutout.txt` - punch-hole
  geometry for Silica, derived from LineageOS's own `config.xml`.
- `sparse/etc/{cgroups,task_profiles}.json` - symlinks into `/system/etc`;
  the patched libprocessgroup looks in `/etc` first.
- `sparse/usr/lib/systemd/system/*.mount` - LineageOS 23.2 uses dynamic
  partitions, so `/system`, `/vendor`, `/product`, `/odm` and `/system_ext` are
  mapped out of `super` by `dmsetup.service`.
