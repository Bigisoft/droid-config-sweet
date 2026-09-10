# Feel free to disable non-critical HA parts during devel by commenting lines out
# Generated in hadk by executing: rpm/dhd/helpers/add_new_device.sh

%package -n patterns-sailfish-device-adaptation-sweet
Summary: Jolla HW Adaptation sweet
Requires: droid-hal-sweet
Requires: droid-hal-sweet-img-boot
Requires: droid-hal-sweet-kernel-modules
Requires: droid-config-sweet-sailfish
Requires: droid-config-sweet-pulseaudio-settings
Requires: droid-config-sweet-policy-settings
Requires: droid-config-sweet-preinit-plugin
Requires: droid-config-sweet-flashing
Requires: droid-config-sweet-bluez5
Requires: droid-hal-version-sweet

# Cellular. ofono talks to Android's RIL over binder, and without the binder
# plugin it has no RIL driver at all: org.ofono.Manager.GetModems() returns an
# empty array, so there is no IMEI, no SIM, no calls and no mobile data, while
# qcrild sits there logging "radioStateChangedInd: mRadioIndication == NULL".
# The -ext-qti extension adds the Qualcomm-specific bits and is what other QTI
# ports use.
Requires: ofono-binder-plugin
Requires: ofono-binder-plugin-ext-qti

# Hybris packages
Requires: libhybris-libEGL
Requires: libhybris-libGLESv2
Requires: libhybris-libwayland-egl

# Sensors
Requires: hybris-libsensorfw-qt5

# Vibra
Requires: ngfd-plugin-native-vibrator
Requires: libngf-qt5-qtfeedback

# Needed for /dev/touchscreen symlink
Requires: qt5-plugin-generic-evdev

Requires: pulseaudio-modules-droid
Requires: pulseaudio-modules-droid-hidl

# The -dummy-af is needed for newer devices that run the main
# audiosystem-passthrough in qti mode (e.g. >=Android 9 Qualcomm),
# to fix non-responding Camera app and/or voice during a phone call:
#Requires: audiosystem-passthrough-dummy-af

# for audio recording to work:
Requires: qt5-qtmultimedia-plugin-mediaservice-gstmediacapture

# These need to be per-device due to differing backends (fbdev, eglfs, hwc, ..?)
Requires: qt5-qtwayland-wayland_egl
Requires: qt5-qpa-hwcomposer-plugin
Requires: qtscenegraph-adaptation

# For hybris devices with droidmedia, see HADK pdf for more information
# Re-enabled 2026-09-09: droidmedia now builds against the Android 16 base.
# It was disabled on 2026-09-08 because the mini services included
# processinfo/IProcessInfoService.h (a header AOSP moved to AIDL) and their fake
# services no longer matched the interfaces they override. Fixed in-tree; see
# FIX 14 in sailfish-sweet-port.md for the full list of changes.
Requires: gstreamer1.0-droid
Obsoletes: gmp-droid

# Maps the logical partitions inside "super". LineageOS 23.2 uses dynamic
# partitions, so /system, /vendor, /product, /odm and /system_ext do not exist
# as real partitions. Used by /usr/bin/droid/dmsetup.sh via dmsetup.service.
Requires: parse-android-dynparts

# This is needed for notification LEDs
Requires: mce-plugin-libhybris

# USB mode controller
Requires: usb-moded

# hammerhead, grouper, and maguro use this in scripts, so include for all
Requires: rfkill

# Device lock, and with it the fingerprint.
#
# The default here is jolla-devicelock-daemon-encsfa, whose plugin has no
# fingerprint support at all: nemo-devicelock then never registers the
# /fingerprint/sensor object, Fingerprint.Sensor.hasSensor stays false, and
# jolla-settings hides the whole Fingerprint section - which is what happened
# on this port and looked like a broken sensor rather than a missing plugin.
#
# sailfish-devicelock-fpd is the variant upstream names for exactly this ("can
# be used with sailfish-devicelock-fpd to add fingerprint support to community
# ports"). It ships the encsfa-fpd plugin, which drives sailfish-fpd over
# /org/sailfishos/fingerprint1, and it Provides jolla-devicelock-plugin-encsfa,
# so it is a drop-in for the plugin half. It does *not* provide the -daemon-
# package name, which is why this line has to change rather than just adding
# one: requiring the old daemon by name is what kept the two apart.
Requires: sailfish-devicelock-fpd

# Fingerprint daemon and its Android backend. sailfish-fpd-community carries
# this port's AIDL client (the vendor HAL is AIDL V4, HIDL is absent); it
# Provides sailfish-fpd, which is what sailfish-devicelock-fpd and mce's
# fingerprint.so both talk to.
Requires: sailfish-fpd-community
Requires: droid-biometry-fp

# Enable home encryption
#Requires: sailfish-device-encryption

# For GPS
Requires: geoclue-provider-hybris

# For FM radio on some QCOM devices
#Requires: qt5-qtmultimedia-plugin-mediaservice-irisradio
#Requires: jolla-mediaplayer-radio

# NFC support
# 1. binder plugin requires Android 8 or a newer base
# 2. pn54x plugin talks directly to pn54x driver
# These plugins are mutually exclusive, you need to pick one:
#Requires: nfcd-binder-plugin
#Requires: nfcd-pn54x-plugin


# sweet: amixer, used by sweet-audio-mixer-defaults.service to put the PRI MI2S
# link into 24 bit / 96 kHz before PulseAudio starts. Without it the Awinic
# speaker amplifiers are silent - see sweet-audio-mixer-defaults.sh.
Requires: alsa-utils


# Bluetooth. bluebinder proxies BlueZ to the Android Bluetooth HAL over a
# virtual HCI adapter; without it there is no adapter at all, only an
# rfkill-blocked bt_power switch. It needs CONFIG_BT_HCIVHCI in the kernel for
# /dev/vhci, and a Bluetooth address, which this device has nowhere to read -
# see sparse/usr/bin/droid/droid-get-bt-address.sh.
Requires: bluebinder


# Flashlight. The shortcut needs both halves: the settings entry that draws it,
# and a backend that can actually light the LED. droidmedia-flashlight calls
# droid_media_camera_set_torch_mode(), so it only became installable once
# droidmedia built against this Android 16 base. Without them the top menu has
# no torch at all, even with Feature_BackCameraFlashlight declared.
Requires: jolla-settings-system-flashlight
Requires: droidmedia-flashlight

%description -n patterns-sailfish-device-adaptation-sweet
Pattern with packages for sweet HW Adaptation

%files -n patterns-sailfish-device-adaptation-sweet
