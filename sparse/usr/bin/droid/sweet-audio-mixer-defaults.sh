#!/bin/sh
# sweet: mixer settings that Xiaomi keeps in /vendor/etc/mixer_paths_overlay_static.xml.
#
# Only Xiaomi's *32-bit* audio HAL - a prebuilt blob - knows how to read the
# overlay files:
#     strings /vendor/lib/hw/audio.primary.sm6150.so   | grep -ci overlay  -> 3
#     strings /vendor/lib64/hw/audio.primary.sm6150.so | grep -ci overlay  -> 0
# The 64-bit HAL that PulseAudio loads is a plain CAF source build with no
# overlay support at all, so it applies the generic paths from
# mixer_paths_idp.xml, which describe hardware this device does not have:
# WSA881x speaker amplifiers instead of the two Awinic AW882xx on PRI MI2S, and
# digital microphones instead of the analogue ones on the Soundwire ADCs.
#
# None of the controls set here belong to a path in mixer_paths_idp.xml, so
# audio_route never resets them and they hold for the life of the boot.

CARD=0

set_ctl() {
    amixer -q -c "$CARD" cset name="$1" "$2" 2>/dev/null \
        || echo "sweet-audio-mixer-defaults: could not set '$1'" >&2
}

# Wait for the codec to register its controls; the Awinic amplifiers and the
# bolero macros probe a few seconds into boot.
i=0
while [ $i -lt 60 ]; do
    amixer -c "$CARD" cget name="PRIM_MI2S_RX Format" >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 1
done

# Then wait for PulseAudio, and this ordering is not optional. PulseAudio opens
# and closes the droid input once at startup to probe it, and that teardown
# resets the capture wiring. Anything set beforehand is silently undone a few
# seconds later - the symptom is a capture stream that reaches RUNNING with
# hw_ptr stuck at 0 and clients timing out on an empty source.
i=0
while [ $i -lt 90 ]; do
    pidof pulseaudio >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 1
done
sleep 3

# ---- playback: the two AW882xx amplifiers -----------------------------------
# They hang off PRI MI2S and Xiaomi runs that link at 24 bit / 96 kHz. Left at
# the kernel default of S16_LE the amplifiers reproduce nothing at all - clock
# present, PLL locked, unmuted, silent.
set_ctl "PRIM_MI2S_RX Format" S24_LE
set_ctl "PRIM_MI2S_RX SampleRate" KHZ_96

# ---- capture: the analogue microphones --------------------------------------
# mixer_paths_idp.xml wires handset-mic to the digital mics (TX DMIC MUX0 =
# DMIC2). This device's mics are analogue, on the Soundwire ADCs, which only the
# overlay's handset-mic path describes.
set_ctl "TX DEC0 MUX" SWR_MIC
set_ctl "TX DEC1 MUX" SWR_MIC
set_ctl "TX SMIC MUX0" ADC2
set_ctl "TX SMIC MUX1" ADC0
set_ctl "TX_AIF1_CAP Mixer DEC0" 1
set_ctl "TX_AIF1_CAP Mixer DEC1" 1
set_ctl "ADC1_MIXER Switch" 1
set_ctl "ADC2_MIXER Switch" 1
set_ctl "ADC2 MUX" INP3
set_ctl "ADC1 Volume" 8
set_ctl "ADC2 Volume" 8
set_ctl "TX_CDC_DMA_TX_3 Channels" Two

# The front-end to back-end capture route. The HAL does set this itself when a
# capture usecase starts, and clears it again on teardown, so it is only primed
# here - the analogue wiring above is what actually makes the microphone work.
set_ctl "MultiMedia1 Mixer TX_CDC_DMA_TX_3" 1

exit 0
