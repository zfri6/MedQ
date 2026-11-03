# SD media, independent cover and doctor carousel

## Requirements and chosen defaults

- Power-up shows the supplied cover. Any of K1..K4 enters the clinic page. The entry press is consumed; all keys must be released and debounced before clinic key functions arm. SW1..SW4 retain their room meanings only after entry. A switch change on the cover is not a doctor event. Boot-held keys require release and a fresh press.
- Clinic page preserves A/B cards, queues, masked names, full-name speech and the independent centered seamless subtitles. The right hand map is compressed into y186..286. One doctor photo occupies x456..607/y298..425. Male and female portraits alternate automatically, with a four-second hold and smooth fade-out/fade-in at VGA frame boundaries. Default first portrait is the larger PNG male source. No unsupported identities, departments or qualifications are invented.
- Right bottom waveform follows the final signed HDMI audio samples after volume control. Silence is a quiet baseline. Frame snapshots prevent tearing.
- JPEG/PNG originals are transformed offline with Lanczos scaling into standard uncompressed 24-bit 640x480 BMP runtime assets, read from SD. They are not synthesized into FPGA ROM. Cover preserves its 4:3 source composition; portrait canvases place crops in the exact photo viewport. The source originals and conversion manifest are retained.

## Frozen architecture and timing contract

- Board ports, PLL profiles, pins, SDRAM primitive, arbitration and PCM protocol are unchanged. Pixel25MHz, system/memory50MHz, SDRAM phase+8ns. No generated fabric clocks.
- FAT filename matching is explicit: COVER.BMP, DOC01.BMP, DOC02.BMP, independent of directory order. Existing CLIP00..53.PCM IDs and payloads remain unchanged.
- A parameterized production native-image profile avoids the general scaler: all delivered images are already640x480, invalid dimensions are rejected. The legacy default module profile retains scaler behavior for existing module tests and compatibility.
- The asset loader preloads cover, both portraits and all PCM into SDRAM. Image0 at word0; image1 at0x04b000; image2 at0x096000; audio pool at0x0e1000, existing bounds unchanged. Initial image writes complete before exposing media readiness. Loading/fault fallback is deterministic and never deadlocks clinic entry.
- One existing sequential frame reader is reused. Its framebuffer base is held for each307200-word memory stream. Base changes occur while portrait opacity is zero, and a minimum three-frame hidden settle covers FIFO lookahead and base-domain synchronization. Cover entry similarly blanks the media layer before switching; the clinic itself appears at a frame boundary. No second full-frame read stream is required for fade-to-background transitions.
- Photo opacity is frame-held, with64 fade levels over~0.54s each direction. Covers use full opacity once valid. All scene/OSD/media coordinates and pixel pipeline latencies are aligned explicitly. Portrait missing/loading fallback remains a clean card, not stale SDRAM.
- Cover mode inhibits enqueue, doctors, calling, audio and remote parameter writes. After entry, physical switches are freshly baselined before doctor events arm; cover key presses and UART commands cannot leak into clinic operations.

## Verification and delivery gates

1. Self-checking entry isolation: each entry key, boot held key, bounce, simultaneous keys, SW doctor toggles on cover, release barrier and fresh clinic press.
2. Named image scan: shuffled FAT directory, unrelated BMP, missing/duplicate names, exact dimensions and full SRAM writes/readback with backpressure.
3. Actual RTL pixels: cover, compact map, male/female endpoints and fade intermediates, waveform silence/speech; frame identity and no tearing.
4. Preserve existing business, speech, subtitle and hardware regressions. Full top with real encrypted SDRAM and physical model, simultaneous media/audio, no underrun.
5. Native synthesis/resource report, routed slow/fast setup and hold, fresh bitgen, source-bound package hashes and protected prior-release checks.
6. Deliver new bitstream, FAT32 SD_ROOT and explicit programming/copy instructions. Physical board status remains not_tested until direct board evidence exists.
