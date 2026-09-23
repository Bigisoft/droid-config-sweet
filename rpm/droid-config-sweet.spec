# These and other macros are documented in ../droid-configs-device/droid-configs.inc
# Feel free to cleanup this file by removing comments, once you have memorised them ;)

%define device sweet
%define vendor xiaomi

# Selects droid-configs-device/sparse-16, the Android-16 overlay. Without this
# the %if 0%{?android_version_major:1} guard in droid-configs.inc is false and
# NONE of the upstream Android-version overlay is installed, so the standard
# stub-out of Android daemons that hybris replaces (netd, vold, lmkd, storaged,
# wificond, surfaceflinger, bootanim, cameraserver, audioserver, gpuservice,
# bpfloader...) never reaches the image and they all run and crash.
# droid-configs.inc accepts 8|9|10|11|13|14|15|16; our base is LineageOS 23.2 =
# Android 16.
%define android_version_major 16

%define vendor_pretty Xiaomi
%define device_pretty Redmi Note 10 Pro

# Community HW adaptations need this
%define community_adaptation 1

# Pixel ratio 1.0 was originally jolla phone with 245ppi, and the devices
# should roughly have their ppi compared to that. Large displays can use
# bigger ratio if seen fit. Values are with 0.25 increments.
%define pixel_ratio 1.5

# droid-configs-device ships /etc/ofono/binder.conf in its sparse tree, which
# collides with the stock ofono-configs-binder package already installed in the
# SDK target. zypper then aborts the whole build-dependency install:
#   Detected 1 file conflict: /etc/ofono/binder.conf
#   Continue? [yes/no] (no): no
# and rpmbuild reports every BuildRequires as missing, which is misleading.
# droid-configs.inc documents the fix as adding a Provides for the package being
# replaced. Obsoletes is needed too, so the already-installed one is removed
# rather than merely satisfied. Safe here: ofono-configs-binder ships only
# /etc/ofono/binder.conf, and we ship that plus /etc/ofono/binder.d/dual-sim.conf.
Provides: ofono-configs-binder
Obsoletes: ofono-configs-binder
# Same story for /etc/ofono/ril_subscription.conf, which appeared once
# %android_version_major was set to 16: droid-configs-device/sparse-16 ships an
# Android-16 version of it (binder transport, slot1/slot2) and it collides with
# ofono-configs-mer, whose only file that is. droid-configs.inc documents the
# fix at the top of the file - "add Provides: PACKAGE to your
# droid-config-$DEVICE.spec". Obsoletes as well so the generic package is
# removed rather than merely satisfied, and Provides: ofono-configs so ofono's
# own dependency on the virtual name is still met.
Provides: ofono-configs-mer
Obsoletes: ofono-configs-mer
Provides: ofono-configs

# The 64-bit ACDB blobs shipped under %{_libexecdir}/droid-hybris/vendor/lib64
# are Android ELFs. Their DT_NEEDED entries name Android libraries (libc++.so,
# libcutils.so, libion.so ...) that no RPM provides, and their sonames are not
# things any RPM should provide either, so keep rpm's dependency generator out
# of that tree. droid-hal-device.inc does the same for its own droid-hybris
# payload.
# Also the mesa libraries shipped into /var/lib/waydroid/overlay: those are
# *Android* binaries for the container, so rpm must not read their ELF NEEDED
# entries and generate unsatisfiable deps on libnativewindow.so, libsync.so,
# libm.so(LIBC) and friends - the package then cannot be installed at all.
%define __requires_exclude_from ^(%{_libexecdir}/droid-hybris|/var/lib/waydroid/overlay)/.*$
%define __provides_exclude_from ^(%{_libexecdir}/droid-hybris|/var/lib/waydroid/overlay)/.*$

%include droid-configs-device/droid-configs.inc
%include patterns/patterns-sailfish-device-adaptation-sweet.inc
%include patterns/patterns-sailfish-device-configuration-sweet.inc

# IMPORTANT if you want to comment out any macros in your .spec, delete the %
# sign, otherwise they will remain defined! E.g.:
#define some_macro "I'll not be defined because I don't have % in front"

