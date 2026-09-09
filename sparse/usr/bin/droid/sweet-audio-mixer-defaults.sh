#!/bin/sh
# sweet: the two AW882xx smart-PA amplifiers hang off PRI MI2S, and Xiaomi runs
# that link at 24 bit / 96 kHz. That setting lives in
# /vendor/etc/mixer_paths_overlay_static.xml, and only Xiaomi's *32-bit* audio
# HAL - a prebuilt blob - knows how to read the overlay files. The 64-bit HAL
# PulseAudio loads is a plain CAF source build with no overlay support at all
# (compare: `strings audio.primary.sm6150.so | grep overlay` finds three hits in
# /vendor/lib and none in /vendor/lib64), so the link is left at the kernel
# default of S16_LE and the amplifiers put out nothing at all.
#
# Set it before PulseAudio starts. audio_route captures the mixer state as it
# finds it at audio_route_init() and restores exactly that on every path reset,
# so a value set here survives every later device switch. Setting it after
# PulseAudio has started does not: the first reset puts S16_LE back.
CARD=0
CTL="PRIM_MI2S_RX Format"

i=0
while [ $i -lt 60 ]; do
    amixer -c "$CARD" cget name="$CTL" >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 1
done

amixer -q -c "$CARD" cset name="$CTL" S24_LE || exit 1
amixer -q -c "$CARD" cset name="PRIM_MI2S_RX SampleRate" KHZ_96 || exit 1
exit 0
