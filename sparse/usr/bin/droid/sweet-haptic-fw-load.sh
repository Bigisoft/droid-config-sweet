#!/bin/sh
# sweet: load the aw8624 haptic waveform firmware, which loses a boot race.
#
# The aw8624 LRA driver keeps its haptic waveforms in on-chip RAM and fills it
# from /vendor/firmware/aw8624_haptic.bin. It asks for that file about 5 s after
# probe (AWINIC_RAM_UPDATE_DELAY) and gives up 2 s later:
#
#     [ 7.926651] firmware aw8624_haptic.bin: _request_firmware_load:
#                 firmware state wait timeout: rc = -2
#     [ 7.926774] aw8624_ram_loaded: failed to read aw8624_haptic.bin
#
# but on this port vendor.mount only becomes active at 8.607 s. The kernel is
# pointed at the right place (firmware_class.path = /vendor/firmware), it is
# simply asked 0.7 s before that path exists, so the request fails on every
# single boot and the waveform RAM is left uninitialised.
#
# Nothing reports an error afterwards. The driver happily "plays" effect ids out
# of that uninitialised RAM, which is what made every short haptic feel wrong -
# audibly buzzy, far too fast, and weaker rather than stronger, because the LRA
# was being driven nowhere near its 207.6 Hz resonance. It looked for all the
# world like a gain or waveform-choice problem.
#
# Writing ram_update re-runs the same request_firmware() path. By the time this
# unit runs /vendor is mounted, so the load succeeds:
#
#     aw8624_ram_loaded: loaded aw8624_haptic.bin - size: 5414
#     aw8624_ram_loaded: check sum pass : 0xe490
#     aw8624_container_update: exit
#     aw8624_ram_loaded: fw update complete
#
# The i2c address is matched by glob rather than hardcoded as 2-005a, so a bus
# renumber does not silently turn haptics off again.

set -e

FOUND=0
for dev in /sys/bus/i2c/drivers/aw8624_haptic/*-*/ram_update; do
    [ -e "$dev" ] || continue
    echo 1 > "$dev" || continue
    FOUND=1
    echo "sweet-haptic-fw: triggered RAM reload via $dev"
done

if [ "$FOUND" = 0 ]; then
    echo "sweet-haptic-fw: no aw8624_haptic ram_update node found" >&2
    exit 1
fi
