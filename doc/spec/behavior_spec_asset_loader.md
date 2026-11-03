> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# asset_loader Behavior Specification

## Requirement Summary

Asset loader orchestrator. On power-up: mount FAT32 → enumerate *.BMP → enumerate *.PCM → preload all PCM to SDRAM AUDIO_POOL → decode and scale first BMP to FB0 → set assets_ok. After ready, respond to load_req for loading any BMP to any frame buffer.

## Public Interface

| Port             | Direction | Width | Description |
|------------------|-----------|-------|-------------|
| clk_sys          | in        | 1     | System clock, 50 MHz |
| rst_n_sys        | in        | 1     | System reset, active low |
| clk_mem          | in        | 1     | SDRAM clock, 100 MHz |
| rst_n_mem        | in        | 1     | SDRAM reset, active low |
| load_req         | in        | 1     | Request to load BMP to frame buffer |
| img_sel          | in        | 5     | Which BMP to load (0..31) |
| fb_sel           | in        | 2     | Target FB: 0=FB0 1=FB1 2=FB2 |
| load_busy        | out       | 1     | Loading in progress |
| load_done        | out       | 1     | Load complete, single-cycle pulse |
| load_err         | out       | 1     | Load error, single-cycle pulse |
| img_count        | out       | 6     | Number of BMP files found |
| pcm_count        | out       | 6     | Number of PCM files found |
| assets_ok        | out       | 1     | All assets loaded successfully |
| progress         | out       | 4     | Load progress 0..15 for OSD |
| clip_sel         | in        | 5     | Query: which audio clip |
| clip_base        | out       | 22    | Word address in AUDIO_POOL |
| clip_samples     | out       | 22    | Sample count (16 kHz) |
| sd_spi_sclk      | out       | 1     | To TF card |
| sd_spi_mosi      | out       | 1     | To TF card |
| sd_spi_miso      | in        | 1     | From TF card |
| sd_spi_cs_n      | out       | 1     | Card select |
| wr_req_valid     | out       | 1     | SDRAM write request |
| wr_req_ready     | in        | 1     | SDRAM arbiter accept |
| wr_req_addr      | out       | 22    | Word address |
| wr_req_we        | out       | 1     | Write enable |
| wr_req_len       | out       | 9     | Burst length in words |
| wr_wr_valid      | out       | 1     | Write data valid |
| wr_wr_ready      | in        | 1     | Write data accepted |
| wr_wr_data       | out       | 32    | Write data |
| wr_rd_valid      | in        | 1     | Read data valid |
| wr_rd_ready      | out       | 1     | Read data accepted |
| wr_rd_data       | in        | 32    | Read data |

## Clocking and Reset

- Dual clock: clk_sys (50 MHz) and clk_mem (100 MHz)
- Reset: rst_n_sys and rst_n_mem, both active low
- CDC: async FIFO (afifo_8i_32o_1024) bridges byte stream from clk_sys to SDRAM write port on clk_mem

## Functional Behavior

### Initialization Flow

```
IDLE → MOUNT → SCAN_BMP → SCAN_PCM → LOAD_PCM → LOAD_FIRST_BMP → READY
                                                          ↓
                                              LOAD_BMP ← (on load_req)
```

### Phase 0: MOUNT
- Assert fat32_reader.mount_req.
- Wait for fat32_reader.mount_done (single-cycle pulse) or mount_err.
- If mount_err: assets_ok=0, stay in MOUNT.

### Phase 1: SCAN_BMP
- Assert fat32_reader.scan_req=1, scan_ext="BMP"=0x424D50.
- For each fat32_reader.file_valid pulse: store file_size[file_index], file_cluster[file_index] in img_table[32].
- Stop when scan_done=1 or file_index=31.
- Update img_count.
- Update progress=2.

### Phase 2: SCAN_PCM
- Assert fat32_reader.scan_req=1, scan_ext="PCM"=0x50434D.
- For each fat32_reader.file_valid pulse: store file_size, file_cluster in aud_table[32].
- Stop when scan_done=1 or file_index=31.
- Update pcm_count.
- Update progress=4.

### Phase 3: LOAD_PCM
- For each entry in aud_table (0..pcm_count-1):
  - Assert fat32_reader.read_req with file_cluster and file_size.
  - Stream bytes from fat32_reader.out_* into afifo_8i_32o_1024 (write clk=clk_sys).
  - afifo_8i_32o_1024 read side (clk_mem) → wr_wr_data → SDRAM AUDIO_POOL.
  - Track audio pool write pointer: clip_base[n] = current_pool_word, clip_samples[n] = file_size/2.
  - Pool word address advances by ceil(file_size/4) words.
- Update progress=8 after all PCM loaded.

### Phase 4: LOAD_FIRST_BMP
- Read first BMP (img_table[0]) using fat32_reader → bmp_parser → bilinear_scaler → SDRAM FB0.
- On bmp_parser.hdr_valid: record img_width/height/bpp.
- Stream pixels through bilinear_scaler (bypass if 640×480).
- Convert scaler output RGB to {8'h00, R, G, B} 32-bit word.
- Write to FB0: base=0x000000.
- Address = FB0_base + out_y*640 + out_x.
- Update progress=14.

### Phase 5: READY
- assets_ok=1, progress=15.
- State machine loops in READY.

### Load BMP on Request
- When load_req=1 in READY:
  - Read img_table[img_sel] (bounds-checked to img_count).
  - Read the BMP file from TF card.
  - Decode pixels → scale → write to target FB (FB0=0x000000, FB1=0x04B000, FB2=0x096000).
  - load_busy=1 during load, load_done pulse on completion.

### SDRAM Write Protocol
- Burst length: 256 words (maximum).
- Wait for wr_req_ready before starting each burst.
- Each word: {8'h00, R, G, B}.
- PCM burst: AUDIO_POOL base + clip_base[n].
- BMP burst: FBx base + linear address from scaler coordinates.

### Audio Pool Organization
- Base: 0x0E1000 (SDRAM word address).
- Each PCM clip is contiguous.
- clip_base is word offset from AUDIO_POOL base.
- clip_samples = file_bytes / 2 (16-bit samples).

### ERAM Tables (distributed RAM)
- img_table: 32 entries × {file_size[31:0], file_cluster[31:0]} = 64 bits/entry.
- aud_table: 32 entries × {file_size[31:0], file_cluster[31:0]} = 64 bits/entry.
- Implemented as two 64-bit-wide × 32-deep registers (or 32×64 distributed RAM).

## Timing, Latency, and Throughput

- Init sequence: mount (1 sector) + scan (few sectors) + PCM load (~seconds depending on card).
- Progress 0..15 updates roughly every 1/15th of total load time.
- PCM loading: 2 bytes per word, AUDIO_POOL writes at SDRAM rate.

## Assumptions and Chosen Defaults

- TF card always present and FAT32 formatted.
- First BMP always exists.
- PCM files are 16-bit mono, file_size is even.
- Scaler output 640×480 fits all frame buffers.

## Edge Cases and Error Handling

- Mount failure: assets_ok=0.
- No BMP files: img_count=0, skip LOAD_FIRST_BMP.
- load_req for img_sel ≥ img_count: ignored.
- PCM load failure: load_err=1.
- BMP decode failure: load_err=1.

## Synthesis Notes

- Target: EG4S20.
- Instantiates: fat32_reader, sd_card_ctrl, bmp_parser, bilinear_scaler, afifo_8i_32o_1024.
- ERAM tables: 32×64 bits each = 2 Kbit per table.
- Estimated LUT4: ~800–1200.

## Verification Plan

1. Mount with known FAT32 image.
2. Verify img_table and aud_table populated correctly.
3. Verify AUDIO_POOL receives PCM data.
4. Verify FB0 receives decoded/scaled BMP data.
5. Assert load_req for img_sel=0..N-1, verify correct FB written.
6. Assert load_req for img_sel≥img_count → ignored.
7. Simulate mount failure → assets_ok=0.
