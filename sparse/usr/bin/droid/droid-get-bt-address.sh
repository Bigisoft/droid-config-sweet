#!/bin/sh
# sweet: supply a Bluetooth address for bluebinder.
#
# bluebinder_post.sh looks for this script first, and falls back to
# ro.bt.bdaddr_path, ro.vendor.bt.bdaddr_path and
# persist.vendor.service.bdroid.bdaddr. On this device all three are empty and
# there is no factory address to read: nothing under /mnt/vendor/persist holds
# one (the partition has no bluetooth directory at all) and /vendor/etc has no
# bdaddr file. Without an address the post script exits 1, systemd tears the
# unit down, and Bluetooth dies even though the adapter has already appeared.
#
# So derive one instead, and derive it deterministically, because a Bluetooth
# address that changes between boots would make the phone a new device to every
# peer it has ever paired with.
#
# androidboot.serialno is the handset's own serial, stable across reflashes.
# The first octet is 0x02: bit 1 set marks the address locally administered,
# bit 0 clear keeps it a unicast address - the correct encoding for an address
# that is not from an IEEE-assigned OUI, which this one is not.

ADDR_FILE=/var/lib/bluetooth/board-address

# Already provided by something else, or by a previous run - leave it alone.
[ -f "$ADDR_FILE" ] && exit 0

serial=$(tr ' ' '\n' < /proc/cmdline | sed -n 's/^androidboot\.serialno=//p')
if [ -z "$serial" ]; then
    echo "droid-get-bt-address: no androidboot.serialno on the kernel command line" >&2
    exit 1
fi

hash=$(printf '%s' "$serial" | md5sum | cut -c1-10)
addr=$(printf '02:%s:%s:%s:%s:%s' \
    "$(echo "$hash" | cut -c1-2)" \
    "$(echo "$hash" | cut -c3-4)" \
    "$(echo "$hash" | cut -c5-6)" \
    "$(echo "$hash" | cut -c7-8)" \
    "$(echo "$hash" | cut -c9-10)" | tr 'a-f' 'A-F')

mkdir -p /var/lib/bluetooth
printf '%s\n' "$addr" > "$ADDR_FILE" || exit 1
chown root:root "$ADDR_FILE"
chmod 644 "$ADDR_FILE"
exit 0
