#!/bin/sh
# LineageOS 23.2 uses dynamic partitions: system, system_ext, vendor, product
# and odm are logical volumes inside "super" (sda25 on sweet). Android's
# first-stage init maps them; that never runs under Sailfish.
SUPER=/dev/block/sda25

# Runs before local-fs.target with DefaultDependencies=no, which can be earlier
# than the block device node appears. Wait up to 10s.
i=0
while [ ! -b "$SUPER" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
done
[ -b "$SUPER" ] || { echo "dmsetup.sh: $SUPER never appeared" >&2; exit 1; }

TABLE=$(/usr/bin/parse-android-dynparts "$SUPER") || {
    echo "dmsetup.sh: parse-android-dynparts failed" >&2; exit 1; }
[ -n "$TABLE" ] || { echo "dmsetup.sh: empty table" >&2; exit 1; }

exec dmsetup create --concise "$TABLE"
