# droid-config-sweet

Sailfish OS device configuration for the Xiaomi Redmi Note 10 Pro
(`sweet`, Snapdragon 732G / sm6150, aarch64).

Base: `hybris-23.2` on LineageOS 23.2 (Android 16). A from-scratch community
port.

## The whole port

| repo | branch | what |
|---|---|---|
| [droid-config-sweet](https://github.com/Bigisoft/droid-config-sweet) | `main` | this repo - the device adaptation |
| [droid-hal-version-sweet](https://github.com/Bigisoft/droid-hal-version-sweet) | `main` | version package |
| [droid-hal-sweet](https://github.com/Bigisoft/droid-hal-sweet) | `main` | tree-root `rpm/` spec and the `repo` local manifest |
| [hybris-patches](https://github.com/Bigisoft/hybris-patches/tree/sweet-hybris-23.2) | `sweet-hybris-23.2` | fork of `mer-hybris/hybris-patches` - six patches an Android 16 base needs |
| [droidmedia](https://github.com/Bigisoft/droidmedia/tree/sweet-android16) | `sweet-android16` | fork of `sailfishos/droidmedia` - builds against Android 16 |
| [droid-hal-device](https://github.com/Bigisoft/droid-hal-device/tree/sweet) | `sweet` | fork of `mer-hybris/droid-hal-device` |
| [android_kernel_xiaomi_sm6150](https://github.com/Bigisoft/android_kernel_xiaomi_sm6150/tree/sweet-sailfish) | `sweet-sailfish` | fork of `LineageOS/...` - defconfig |

Start at `droid-hal-sweet` for the manifest and build order.

## Device-specific pieces worth knowing about

- `sparse/usr/libexec/droid-hybris/vendor/lib64/` - **empty on purpose**, see the
  README there. There is no audio at all without it: LineageOS extracts only the
  32-bit ACDB libraries, because this device's Android audio HAL is 32-bit,
  while PulseAudio is 64-bit.
- `sparse/usr/lib/systemd/system/droid-vendor-lib64-overlay.service` - layers the
  above in front of `/vendor/lib64` with a read-only overlay mount.
- `sparse/usr/bin/droid/sweet-audio-mixer-defaults.sh` - puts the PRI MI2S link
  into 24-bit/96 kHz before PulseAudio starts, which the two Awinic AW882xx
  speaker amplifiers require. Xiaomi sets this from a mixer-path overlay that
  only their 32-bit audio HAL knows how to read; the 64-bit HAL has no overlay
  support at all, so the link would otherwise stay at S16_LE and the speakers
  stay silent. It has to happen before PulseAudio starts, because `audio_route`
  snapshots the mixer at init and restores that snapshot on every device change.
- `sparse/usr/lib/systemd/system/qcacld-wlan-enable.service` - writes `ON` to
  `/dev/wlan`. qcacld-3.0 registers only a control node and creates no netdev
  until userspace asks; on Android the Wi-Fi HAL does this, and connman does not.
- `sparse/etc/dconf/db/vendor.d/50-sweet-display-cutout.txt` - punch-hole
  geometry for Silica, converted from LineageOS's own `config_mainBuiltInDisplayCutout`.
- `sparse/etc/{cgroups,task_profiles}.json` - symlinks into `/system/etc`. The
  patched libprocessgroup looks in `/etc` first, which on a hybris port is
  Sailfish's `/etc`, not Android's.
- `sparse/usr/share/csd/settings.d/hw-settings.ini` - without it there is no
  battery indicator in the UI.
- `sparse/usr/lib/systemd/system/*.mount` - LineageOS 23.2 uses dynamic
  partitions, so `/system`, `/vendor`, `/product`, `/odm` and `/system_ext` have
  no device nodes and are mapped out of `super` by `dmsetup.service`.

## Status

Working: display, touch, Wi-Fi, sensors, modem and both SIM slots, battery,
app sandboxing, audio (speakers, headphones with jack detection, earpiece,
ringtones, media).

Built but unverified: camera and hardware video decode, via droidmedia and
`gstreamer1.0-droid`.
