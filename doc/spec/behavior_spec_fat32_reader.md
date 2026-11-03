> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# fat32_reader Behavior Specification

## Requirement Summary

Read-only FAT32 filesystem reader. Reads MBR/BPB → locates partition → parses FAT → scans root directory for 8.3 files → follows cluster chains to stream file bytes. No long filename support, no subdirectory support.

## Public Interface

| Port            | Direction | Width | Description |
|-----------------|-----------|-------|-------------|
| clk             | in        | 1     | System clock, 50 MHz |
| rst_n           | in        | 1     | Async reset, active low |
| mount_req       | in        | 1     | Start filesystem mount |
| mount_done      | out       | 1     | Mount completed |
| mount_err       | out       | 1     | Mount failed |
| scan_req        | in        | 1     | Start root directory scan |
| scan_ext        | in        | 24    | Extension to match, e.g. "BMP"=0x424D50 |
| file_valid      | out       | 1     | One file found, single-cycle pulse |
| file_index      | out       | 5     | 0..31, which file |
| file_size       | out       | 32    | File size in bytes |
| file_cluster    | out       | 32    | First cluster number |
| scan_done       | out       | 1     | Scan finished |
| file_count      | out       | 6     | Total files matched |
| read_req        | in        | 1     | Start sequential read of a file |
| read_cluster    | in        | 32    | First cluster of file |
| read_len        | in        | 32    | Bytes to read |
| read_busy       | out       | 1     | Reading in progress |
| read_done       | out       | 1     | Read completed |
| read_err        | out       | 1     | Read error |
| out_valid       | out       | 1     | File byte valid |
| out_data        | out       | 8     | File byte |
| sd_rd_req       | out       | 1     | To sd_card_ctrl |
| sd_rd_lba       | out       | 32    | LBA for sd_card_ctrl |
| sd_rd_done      | in        | 1     | Sector read done |
| sd_rd_err       | in        | 1     | Sector read error |
| sd_byte_valid   | in        | 1     | Byte from sd_card_ctrl |
| sd_byte_data    | in        | 8     | Byte value |

## Clocking and Reset

- Domain: clk_sys (50 MHz)
- Reset: rst_n active low

## Functional Behavior

### Mount Flow

```
MOUNT_IDLE → READ_MBR → READ_BPB → READ_FAT → MOUNT_DONE / MOUNT_ERR
```

1. **READ_MBR**: Read LBA 0 (1 sector).
   - Verify byte 510=0x55, byte 511=0xAA.
   - Read partition entry at offset 0x1BE: byte 4 = partition type.
   - If type=0x0B/0x0C (FAT32), read bytes 8..11 as partition_lba (32-bit).
   - If no valid FAT32 partition, mount_err.

2. **READ_BPB**: Read first sector of FAT32 partition.
   - Parse BPB at offset 0x00:
     - `bytes_per_sec` [15:0] @0x0B → must be 512.
     - `sec_per_clus`  [7:0]  @0x0D.
     - `reserved_sec`  [15:0] @0x0E → RsvdSecCnt.
     - `num_fats`      [7:0]  @0x10 → NumFATs, must be 2.
     - `hidd_sec`      [31:0] @0x1C → partition_lba (already known).
     - `tot_sec32`     [31:0] @0x20 → TotalSectors.
     - `fat_len32`     [31:0] @0x24 → FATSz32 (sectors per FAT).
     - `root_clus`     [31:0] @0x2C → FirstClusterOfRootDirectory.
   - Compute: `fat_start = partition_lba + reserved_sec`.
   - Compute: `data_start = fat_start + num_fats * fat_len32`.
   - Cluster 2 = first data cluster.

3. **MOUNT_DONE**: Set mount_done=1. Store all BPB parameters in registers.

### Scan Flow

```
SCAN_IDLE → READ_DIR_CLUSTER → PARSE_DIR → (more clusters?) → SCAN_DONE
```

- Read root directory cluster (`root_clus` from BPB).
- For each 32-byte directory entry:
  - Byte 0 = 0x00 or 0xE5 → empty slot, skip.
  - Byte 11: attribute byte:
    - Bit 4 = volume label → skip.
    - Bit 3 = LFN (long filename) → skip entire LFN chain.
    - Bits 2,1,0 = 0 → regular file.
  - Bytes 8..10: 3-char extension. Compare against `scan_ext[23:0]` (already upper-case).
  - If match: output file_valid, file_index++, file_size (bytes 28..31 little-endian), file_cluster (bytes 20..21 << 16 | bytes 26..27 little-endian).
  - Move to next entry.
- Each cluster: read cluster → parse entries → read FAT entry for next cluster → repeat.
- End of cluster chain: next cluster = 0x0FFFFFF8..0x0FFFFFFF or 0.
- Stop after 32 files or end of directory.

### FAT Traversal

- FAT entry is 32 bits. Each entry = 4 bytes.
- FAT entry N is at FAT[4*N+3 .. 4*N] (little-endian).
- Read FAT in 512-byte sectors: entry N is at sector `fat_start + (N*4)/512`, offset `(N*4)%512`.
- Cache one FAT sector at a time.
- Special values: 0x0FFFFFF8..0x0FFFFFFF = EOF; 0x0FFFFFF7 = bad cluster; 0 = free.

### File Read Flow

```
READ_IDLE → READ_FIRST_CLUSTER → READ_CLUSTER_DATA → CHECK_FAT → READ_NEXT / READ_DONE
```

- Latch read_len and read_cluster.
- For each cluster:
  - Compute first sector = `data_start + (cluster-2) * sec_per_clus`.
  - Read all sectors in cluster sequentially.
  - After cluster data, check FAT for next cluster.
  - If next_cluster is EOF or 0 → read_done.
  - If next_cluster is valid → repeat.

### Byte Output

- out_valid pulses for each byte.
- out_data is the byte value.
- The caller consumes bytes; this module just streams them.

## Timing, Latency, and Throughput

- Each FAT32 filesystem operation requires one or more sector reads via sd_card_ctrl.
- out_valid rate limited by sd_card_ctrl throughput.
- No internal buffering beyond one sector.

## Assumptions and Chosen Defaults

- Sector size always 512 bytes.
- FAT sectors fit within one or two sector reads (FAT size ≤ 128 sectors typically).
- Cluster chains fit in available internal storage.
- File count capped at 32 to limit internal table size.

## Edge Cases and Error Handling

- Invalid BPB: mount_err.
- No FAT32 partition in MBR: mount_err.
- Read error from sd_card_ctrl: read_err.
- Cluster chain hits bad cluster (0x0FFFFFF7): read_err.
- File count exceeds 32: stop scanning, scan_done.
- Directory entry stream ends without EOF marker: treat as scan_done.

## Synthesis Notes

- Target: EG4S20.
- FSM uses ~20 states.
- Small buffer for one FAT sector (512 bytes) using distributed RAM.
- Estimated LUT4: ~400–500.

## Verification Plan

1. Mount with valid FAT32 image.
2. Scan for *.BMP → verify all BMP entries found.
3. Scan for *.PCM → verify all PCM entries found.
4. Read a file and verify byte sequence.
5. Simulate mount_err with invalid BPB.
6. Simulate read_err with bad cluster.
7. Verify no long-filename entries leak into scan results.
