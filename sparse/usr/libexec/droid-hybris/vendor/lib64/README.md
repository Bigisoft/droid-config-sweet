# Missing on purpose: five 64-bit ACDB libraries

`droid-vendor-lib64-overlay.service` layers this directory in front of
`/vendor/lib64`, to supply libraries LineageOS does not extract. They are
proprietary Qualcomm/Xiaomi binaries and are not redistributed here. Without
them **the device has no audio at all** - see below for why, then extract them
from your own handset.

## Why they are needed

PulseAudio is 64-bit and loads `/vendor/lib64/hw/audio.primary.sm6150.so`. That
HAL dlopens `libacdbloader.so`, which pushes the audio calibration into the ADSP
through `/dev/msm_audio_cal`. LineageOS ships only the 32-bit copies, because on
Android this device runs a 32-bit audio HAL:

    $ head -c 5 /vendor/bin/hw/android.hardware.audio.service | od -An -c
    177   E   L   F 001            <- ELFCLASS32

so the 64-bit dlopen fails, no calibration ever reaches the DSP, and every AFE
port either refuses to start or plays silence:

    afe_get_cal_topology_id: cal_type 8 not initialized for this port 45104
    afe_apr_send_pkt: DSP returned error[ADSP_EBADPARAM]
    __afe_port_start: AFE enable for port 0xb030 failed -22

## Extracting them from your own device

The 64-bit copies do exist - in the stock MIUI firmware, whose audio HAL is
64-bit. From the MIUI fastboot package for your region (this was checked against
`V14.0.9.0.TKFEUXM`):

```sh
tar -xzf sweet_*_images_*.tgz --wildcards --no-anchored 'images/super.img'
simg2img super.img super.raw          # the shipped super.img is sparse

# find the vendor partition: scan 64 KiB-aligned offsets for an ext4
# superblock (magic 0x53EF at +0x38 from the superblock) whose volume label
# at +0x78 reads "vendor". On V14.0.9.0.TKFEUXM it is at 0x18F600000.

LO=$(sudo losetup -f --show -o $((0x18F600000)) --sizelimit 1472577536 super.raw)
for f in libacdbloader.so libacdb-fts.so libacdbrtac.so libadiertac.so libaudcal.so; do
    sudo debugfs -R "dump /lib64/$f ./$f" "$LO"
done
sudo losetup -d "$LO"
```

Drop the five files in this directory and rebuild `droid-config-sweet`.

Reference checksums from `V14.0.9.0.TKFEUXM` (sha256, first 16 hex digits):

| file | sha256 prefix |
|---|---|
| `libacdbloader.so` | `39ad26484a41fe0d` |
| `libacdb-fts.so`   | `3e6354fbb232f1f6` |
| `libacdbrtac.so`   | `11ebe5435cbecdf0` |
| `libadiertac.so`   | `9b70b5cb73621186` |
| `libaudcal.so`     | `5ced0fbe4a774f6b` |

Offsets and the partition size differ between firmware versions; the scan
described above is the reliable way to locate it.
