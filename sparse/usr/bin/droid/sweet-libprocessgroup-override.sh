#!/bin/sh
# Overlay droid-hal-s patched libprocessgroup.so onto the stock LineageOS one.
#
# hybris-patches/system/core/0044 makes libprocessgroup a no-op when cgroups are
# unavailable. Without it every Android daemon that calls SetTaskProfiles()
# aborts on this device -- logd first, which then hides every later failure.
#
# droid-hal installs the patched build under /usr/libexec/droid-hybris/system/,
# but that is only a *permitted* path in the generated linker config: the system
# namespace search paths are /system/${LIB} and /system_ext/${LIB} only
# (system/linkerconfig/contents/namespace/systemdefault.cc:92). A DT_NEEDED of
# libprocessgroup.so therefore still resolves to the stock copy on the read-only
# /system dynamic partition, which no RPM of ours can replace. Bind-mount over
# it instead, before droid-hal-startup.sh brings the Android daemons up.
for lib in lib lib64; do
    src="/usr/libexec/droid-hybris/system/$lib/libprocessgroup.so"
    dst="/system/$lib/libprocessgroup.so"
    [ -f "$src" ] || continue
    [ -f "$dst" ] || continue
    if grep -q " $dst " /proc/self/mountinfo 2>/dev/null; then
        continue
    fi
    mount -o bind "$src" "$dst" || echo "sweet: bind mount of $dst failed" >&2
done
exit 0
