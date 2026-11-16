# Build info: droid-config-sweet mobile data RPMs

Device: Xiaomi Redmi Note 10 Pro (sweet), community port, LineageOS 23.2 / Android 16 base, Sailfish OS 5.1.0.11.
Built: 2026-11-16 (UTC), in the Sailfish OS Platform SDK under qemu-aarch64 binfmt.

## IMPORTANT: android-headers is a stand-in

`android-headers-sweet-16.0.0-1.aarch64.rpm` is a HEADERS-ONLY STAND-IN. It is NOT droid-hal-sweet-devel
and it contains no output of a device Android build. It was made only so that the
`BuildRequires: pkgconfig(android-headers)` in droid-configs-device/droid-configs.inc resolves.
droid-configs.inc does not read any header from it; the requirement is a build-time gate only.
Do not install it on a device and do not use it to build anything that needs real
droid-hal-sweet-devel (libhybris, droidmedia, audioflingerglue, etc.).

## SDK

| Component | Version / source |
|---|---|
| Platform SDK chroot | Jolla-latest-SailfishOS_Platform_SDK_Chroot-i486.tar.bz2 (https://releases.sailfishos.org/sdk/installers/latest/), reports Sailfish OS 5.1.0.11 (Pispala) |
| mb2 | 1.4.94 |
| Tooling | SailfishOS-5.1.0.11 from Sailfish_OS-5.1.0.11-Sailfish_SDK_Tooling-i486.tar.7z, md5 2516f8cd3be63ea23b75496b2a153510 (verified) |
| Target | SailfishOS-5.1.0.11-aarch64 from Sailfish_OS-5.1.0.11-Sailfish_SDK_Target-aarch64.tar.7z, md5 24b40e5e6c1366996dc5a4a69a46e3b3 (verified) |

Proxy CA appended to etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem in the chroot, the tooling,
the target and the target .default copy. TLS verification was not disabled.

## Source commits

| Source | Commit |
|---|---|
| Bigisoft/droid-config-sweet, branch fix/ofono-auto-data-sim | 72982d0 (on top of main 0a85f8f: e3fce91 sparse/etc/ofono/main.conf, 72982d0 Requires: dummy_netd + sparse/etc/sysconfig/dummy_netd) |
| Bigisoft/droid-hal-configs, master (copied into droid-configs-device/ of the build copy) | ffddf7f |
| sailfishos-mirror/libhybris (utils/extract-headers.sh) | 02f9f62 |
| LineageOS/android manifest, lineage-23.2 (AOSP base tag android-16.0.0_r4) | 84e40f4b7f32360505019b1fc468392766e5003c |
| bionic (LineageOS/android_bionic lineage-23.2) | ff9fe01e7e1e81febaf32b15fa561aec480a112c |
| system/core (LineageOS/android_system_core lineage-23.2) | eb2de7321317226bbc1951382b3171fa59bb4d1d |
| hardware/libhardware (LineageOS/android_hardware_libhardware lineage-23.2) | 0c3e9e0fe76d30d32282c7e8fcdbddc393dc297b |
| hardware/libhardware_legacy (AOSP platform/hardware/libhardware_legacy tag android-16.0.0_r4, as in the Lineage 23.2 manifest; LineageOS has no lineage-23.x branch of it) | 3e1bd41dcb66b0ee75ada6e2167a3d7fecd7fce9 |
| frameworks/native (LineageOS/android_frameworks_native lineage-23.2) | 26f530caefb3217766469d9731ee602c83f48e84 |
| system/media (LineageOS/android_system_media lineage-23.2) | d00e4bb7148a13b1fc66c34f8161a3622b1905d2 |
| system/logging (LineageOS/android_system_logging lineage-23.2) | e63321648d4f2cb7c437bd615366e8f8765ad2bc |

All Android repos were full shallow (depth 1) checkouts, so in-tree symlinks such as
system/core/include/{cutils,system,utils} resolve.

## Header extraction

Command: `sh extract-headers.sh -v 16.0.0 -p /usr/include/android <ANDROID_ROOT> <HEADER_PATH>`
(`-p` sets the Cflags include path written into android-headers.pc.) Result: 184 files, exit 0.

Adaptations (full diff in headers/extract-headers-android16.patch), every one because Android 16 moved the header:

1. `log`: system/core/include/log (gone) -> system/logging/liblog/include/log
2. `android`: system/core/include/android (gone) -> system/logging/liblog/include/android (log.h, log_macros.h)
3. `private`: system/core/include/private/android_filesystem_config.h (gone) -> system/core/libcutils/include/private/android_filesystem_config.h

Not adapted (optional in the script, skipped because absent in Android 16): hardware_legacy/vibrator.h and
hardware_legacy/wifi.h, frameworks/opt/net/wifi (not checked out), external/libnfc-nxp (not checked out).
Script notes: `cp: -r not specified; omitting directory .../system/media/audio/include/system/audio_effects`
(unchanged upstream behaviour) and `Can't extract Git info: missing 'repo'` (so no git-revisions.txt inside
the package; commits are listed above instead).

## android-headers-sweet RPM (stand-in)

Spec: headers/android-headers-sweet.spec. Built in the SDK with
`mb2 -t SailfishOS-5.1.0.11-aarch64 -s rpm/android-headers-sweet.spec build` (exit 0).
Installs headers to /usr/include/android and /usr/lib64/pkgconfig/android-headers.pc (Version 16.0.0,
Cflags -I/usr/include/android). Provides android-headers = 16.0.0 and pkgconfig(android-headers) = 16.0.0.
Installed into the target with
`sb2 -t SailfishOS-5.1.0.11-aarch64 -m sdk-install -R rpm -U --replacepkgs android-headers-sweet-16.0.0-1.aarch64.rpm`;
`pkg-config --modversion android-headers` in the target then printed 16.0.0.
rpmlint (treated as warnings by mb2): E: useless-provides pkgconfig(android-headers), E: no-changelogname-tag,
W: files-duplicate private/android_filesystem_config.h cutils/android_filesystem_config.h.

## community-adaptation

```
sb2 -t SailfishOS-5.1.0.11-aarch64 -m sdk-install -R zypper ar -f https://repo.sailfishos.org/obs/nemo:/devel:/hw:/common/sailfish_latest_aarch64/ hw-common
sb2 -t SailfishOS-5.1.0.11-aarch64 -m sdk-install -R zypper mr -G hw-common
sb2 -t SailfishOS-5.1.0.11-aarch64 -m sdk-install -R zypper --non-interactive in community-adaptation
```
Installed: community-adaptation-devel 0.0.4-1.10.1.bso (noarch), which provides community-adaptation.
Same version as on the device image.
Note: the first refresh failed with `File 'repomd.xml' from repository 'hw-common' is unsigned`
(OBS repos are unsigned), so GPG checking was turned off for that one repo (`zypper mr -G`). HTTPS with
certificate verification stayed on. Installing the package also made ssu add the
adaptation-community-common repo to the target.

## Build

From the build copy root (droid-config-sweet at 72982d0 with droid-hal-configs ffddf7f in droid-configs-device/):
`mb2 -t SailfishOS-5.1.0.11-aarch64 -s rpm/droid-config-sweet.spec build`

rpmbuild finished with `+ exit 0` and wrote all 12 RPMs below. mb2 itself then exited 1 in its post-build
check (rpmlint) stage, verbatim:
```
NOTICE: No packages found and none specified explicitly
Fatal: None of the selected test suites operate on the selected test levels. Nothing to do.
```
`mb2 check -l package` run on its own gives the same output. So rpmlint did not run on these RPMs; the packages
themselves were produced normally by rpmbuild inside the SDK.

Build warnings (summary):
- unversioned Obsoletes: ofono-configs-binder, ofono-configs-mer, usb-moded-pc-suite-mode-android,
  usb-moded-mtp-mode-android-ffs, ohm-configs-default, bluez5-configs-mer, gmp-droid
- Macro expanded in comment (spec lines 8, 41, 52 and droid-configs.inc line 224)
- 20 x absolute symlink (/etc/* -> /system/etc/*, preinit is_total_erase_supported -> /bin/false)
- File listed twice: /etc/sysconfig/dummy_netd, /usr/bin/droid/wait_for_keymint,
  /usr/lib/systemd/system/droid-hal-init.service (device sparse overrides droid-configs-device sparse-16; content checked below)
- NOKEY signature warnings for jolla repo build deps (qt5-qttools-kmap2qmap, ssu-ks, ssu-kickstart-configuration-jolla)
- `Warning: Unset flavour in release mode.`

## Verification

- droid-config-sweet-1-202611161342.aarch64.rpm contains /etc/ofono/main.conf with `AutoSelectDataSim=always` (line 9).
- It contains /etc/sysconfig/dummy_netd with `DUMMY_NETD_ARGS=--device=/dev/hwbinder`.
- patterns-sailfish-device-adaptation-sweet-1-202611161342.aarch64.rpm Requires `dummy_netd`.
- `rpm -qlp` and `rpm -qpR` output for every RPM: lists/<rpm>.files.txt and lists/<rpm>.requires.txt.

## RPMs

| RPM | size (bytes) | sha256 |
|---|---|---|
| android-headers-sweet-16.0.0-1.aarch64.rpm | 336378 | a88b55954c678d58619fe46206641ee9459435e08b0a1bf18782f70fd614049a |
| droid-config-sweet-1-202611161342.aarch64.rpm | 63754 | dcc15bf508c94efa9c8ef4123e9845a9ba2bf29c4ea7b595cc53ba168f30b970 |
| droid-config-sweet-bluez5-1-202611161342.aarch64.rpm | 14568 | 686dab8bfab81c1f70e7e1058826a75fa33f1c3d6e9d079ec338fc435a887ce7 |
| droid-config-sweet-flashing-1-202611161342.aarch64.rpm | 9256 | f04d403c18d3ea11d534d2cf9cf839804dde87830b0cdc1b75285c8e45f312d9 |
| droid-config-sweet-kickstart-configuration-1-202611161342.aarch64.rpm | 7483 | d6e21c11b28daaee596ec2c7b2f3054d9d270d20545b4446abb2e6bb4415ccf0 |
| droid-config-sweet-policy-settings-1-202611161342.aarch64.rpm | 8646 | 7ab497f6a80af1609db19bff2bd6a3dc17a8bffdf02de78a5e91bbc4e52a34d1 |
| droid-config-sweet-preinit-plugin-1-202611161342.aarch64.rpm | 8577 | f6a8e1997c389295ecd341e9db05243a54355ff446a3df6394ad50623d449185 |
| droid-config-sweet-pulseaudio-settings-1-202611161342.aarch64.rpm | 17339 | 26197694c4c46f452210f0ba63c5f4e5eea03d67f9e39e501fc79c305ac2d8c5 |
| droid-config-sweet-sailfish-1-202611161342.noarch.rpm | 9196 | 6f38fdaaa5e3f6ba646795256d8e30bde0dd2881af93cb8f095b278f517ea5f9 |
| droid-config-sweet-ssu-kickstarts-1-202611161342.aarch64.rpm | 8849 | 2b50d05645105ccaf33e1a481232717a4f653586159dd7124d4f6095da930d02 |
| patterns-sailfish-device-adaptation-sweet-1-202611161342.aarch64.rpm | 7165 | b0147257c88466170262658ed46fd5a79e3e64c2db845269e50f1fee9da2d219 |
| patterns-sailfish-device-configuration-common-sweet-1-202611161342.aarch64.rpm | 6109 | 2bf2204d203094d51a1c3a9215bea549a647ff319fe559b781a4719eb42c7648 |
| patterns-sailfish-device-configuration-sweet-1-202611161342.aarch64.rpm | 6297 | 059f618b468c344fc017f5620ab1bbbbabe28fe24318f149a86fad9455c6f1c8 |

No file was over 95 MB; nothing was skipped.
