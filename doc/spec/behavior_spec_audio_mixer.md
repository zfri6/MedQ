# audio_mixer Behavior Specification

## Requirement Summary

Mix the tone generator output with the PCM player output, apply volume scaling, saturate to signed 16-bit, and output stereo (both channels identical). The mix runs on every 48 kHz `stb` cycle in `clk_pix` domain.

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | Pixel clock, 25.000 MHz |
| `rst_n` | in | 1 | Async reset, low-active |
| `stb` | in | 1 | 48 kHz sample gate |
| `tone_in` | in | 16 | Signed 16-bit from audio_tone_gen |
| `pcm_in` | in | 16 | Signed 16-bit from audio_pcm_player |
| `volume` | in | 8 | Volume 0..255 from param_bus |
| `aud_l` | out | 16 | Left output, signed |
| `aud_r` | out | 16 | Right output, signed (=aud_l) |

## Parameters

None.

## Clocking and Reset

- Clock: `clk_pix` @ 25.000 MHz
- Reset: async assert / sync release, `rst_n` low-active
- All output changes are synchronous to `stb` rising edge within `clk_pix`

## Functional Behavior

### 1. Mix Stage
`mixed_17 = tone_in + pcm_in`, 17-bit signed to prevent overflow on addition.
Range: [-65536, +65535].

### 2. Volume Scaling
`mixed_q8 = mixed_17 << 8` (Q8 format: multiply by 256)
`scaled = mixed_q8 * volume`
`scaled = scaled >> 8`

Net: `output = (tone_in + pcm_in) * volume / 256`

At `volume = 255` (max), gain ≈ 0.996 (−0.035 dB, near unity).
At `volume = 128` (neutral), gain ≈ 0.5 (−6 dB).
At `volume = 0`, output = 0 (mute).

### 3. Saturation
Clamp to signed 16-bit range:
- If `scaled > 32767` → output 32767
- If `scaled < −32768` → output −32768
- Otherwise → output `scaled[15:0]`

### 4. Stereo Output
`aud_l = aud_r = mixed_out`. Both channels carry identical mono content.

## Latency and Throughput

- Combinational path: tone_in → mixed_17 → mixed_q8 → scaled → saturation → `mixed_out`
- Registered output on `stb`: 1 `clk_pix` cycle latency
- Throughput: one sample per `stb` (48 kS/s per channel)

## Assumptions and Chosen Defaults

- `volume` is stable for the duration of `stb`. Rapid changes produce audible stepping (acceptable for slider controls).
- The `<<8` and `>>8` pair are exact inverses; no rounding is needed since the volume multiply naturally divides.

## Edge Cases and Error Handling

- `tone_in = 0`, `pcm_in = 0`: output = 0 (silence).
- `volume = 0`: output = 0 regardless of inputs.
- `tone_in = 32767`, `pcm_in = 32767` (max): mixed_17 = 65534; at volume=255: output ≈ 65534 × 255/256 ≈ 65502, clamped to 32767.
- No error flags — clipping is handled silently by saturation.

## Synthesis Notes

- **Resources**: ~80 LUT4 (adder + shifter + multiplier + saturation).
- **Multiplier**: one 25×8 → 32-bit signed multiplier → maps to 1 DSP.
- **Pipeline**: no deep pipeline needed at 48 kHz × 25 MHz clock ratio.
- No BRAM.

## Verification Plan

1. **Volume = 255, max tone**: assert output = 32767 (clamped).
2. **Volume = 128**: assert output = (tone+pcm)/2 ± 1.
3. **Volume = 0**: assert output = 0.
4. **Saturation**: inject tone_in=30000, pcm_in=30000, volume=255; assert output=32767.
5. **Reset**: assert aud_l=aud_r=0 after reset.
6. **Stereo identity**: assert aud_l == aud_r always.

## Acceptance Criteria

- [ ] Correct mix: `aud_l = (tone_in + pcm_in) * volume / 256` with saturation.
- [ ] `aud_l == aud_r` at all times.
- [ ] Reset clears both outputs to zero.
- [ ] RTL compiles with iverilog and ModelSim with zero errors.
