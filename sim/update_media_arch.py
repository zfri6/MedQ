"""Append the reviewed media interface amendment, preserving prior contracts."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MARK='media_carousel_20261103'
UPDATES={
 'doc/arch/interface_contract.yaml': '''
media_carousel_20261103:
  specification: doc/spec/media_carousel_20261103.md
  board_ports_and_constraints: unchanged
  medq_media_control:
    clock_reset: clk_pix_25MHz_rst_n_pix
    parameters: {DEBOUNCE_CYCLES: 250000, HOLD_FRAMES: 238}
    inputs: "frame_start[1],keys_sync[4] active low,media_valid[3] held CDC from sys"
    outputs: "clinic_visible[1],clinic_enable[1],fb_base[22],media_show[1],photo_alpha[7] 0..64"
    protocol: "enter event consumed; frame-atomic page swap; debounced all-key release; fresh clinic frontend initialization; hidden three-frame base settle; frame-held smoothstep 0..64"
  medq_audio_wave:
    clock_reset: clk_pix_25MHz_rst_n_pix
    inputs: "frame_start,de,stb,enabled[1],x,y[10],sample[16] signed final HDMI aud_l"
    outputs: "rgb[24],alpha[8] registered one cycle"
    history: "signed 5-bit32 samples, decimate96 at48kHz; frame-held snapshot; four-pixel linear interpolation and antialiasing"
  asset_loader:
    parameter: "MEDIA_PROFILE=1 in production; default0 retains legacy scaler module profile"
    output: "media_valid[3] sys-domain sticky commit bits after final SDRAM write acknowledgement"
    protocol: "named image scan; load image0/1/2 before all PCM; no publication of partial images; reject non640x480/non24bit BMP; missing names stay invalid"
  fat32_reader:
    parameter: "NAMED_BMP=1 in media profile; default0 unchanged"
    names: "COVER.BMP->0,DOC01.BMP->1,DOC02.BMP->2; unrelated names ignored, duplicates rejected, no directory-order dependence"
  osd_renderer:
    parameter: "MEDIA_LAYOUT=1 production; default0 keeps legacy interface behavior"
    inputs: "cover_mode,media_show[1],photo_alpha[7] 0..64, all pix-domain/frame-held"
    latency: "two cycles; cover bypass or white photo-underlay alpha, preserving four-level glyph AA"
  medq_dual_ui_scene:
    parameter: "COMPACT_MAP=1 production; default0 preserves original page pixel tests"
  memory: "three native307200-word images at0x000000,0x04b000,0x096000; unchanged PCM pool0x0e1000..0x18efff"
  cdc: "media_valid W3 sys->pix, media_base W22 pix->mem held request/ack; clinic_enable pix->sys two-flop"
  signed_audio_mixer_repair: "sign-extend both16bit inputs; signed17xunsigned8 Q0.8 gain; arithmetic /256 then saturation; original output sign/clipping defect independently reproduced"
''',
 'doc/arch/clock_reset_cdc.md': '''
## media_carousel_20261103

The board/PLL/SDRAM clock profile is unchanged. `media_valid` uses W3 held-bus request/ack CDC from sys to pix; framebuffer base uses W22 held-bus CDC pix to mem. The base is held for every memory frame stream and changes only at zero photo alpha; three complete hidden frames cover handshake and FIFO lookahead. `clinic_enable` crosses to sys through the existing bit synchronizer only for remote parameter writes. The pix clinic input frontend is held in reset until frame-committed entry plus debounced all-key release; this forces a fresh switch baseline. Audio history, visible snapshot, opacity, both room state snapshots and wave rendering share clk_pix. No fabric clock or new timing exception is introduced.
''',
 'doc/arch/module_partition.md': '''
## media_carousel_20261103

`medq_media_control` owns cover key debounce/release, page/clinic arming, chosen portrait and fade state. `asset_loader MEDIA_PROFILE=1` owns named image metadata, native parser path, three SDRAM image commits and existing PCM preload. `medq_audio_wave` owns32-point signed audio history and frame snapshots; it consumes final HDMI samples and never controls audio. `osd_renderer MEDIA_LAYOUT=1` owns media transparency, `medq_dual_ui_scene COMPACT_MAP=1` owns the compressed map. The existing frame_reader, arbiter, physical SDRAM controller and HDMI pipeline are reused. The default legacy module profiles retain their historical tests.
''',
 'doc/arch/connection_matrix.md': '''
## media_carousel_20261103

KEY -> board two-flop synchronizer -> cover control -> frame-committed clinic visibility -> all-key release -> reset release of v03_inputs -> unchanged dual service. No cover key is forwarded as an enqueue. SW1..4 are freshly baselined by v03_inputs after entry.

SD SPI -> FAT named COVER/DOC01/DOC02 scan -> native BMP pixels -> existing asynchronous word FIFO -> SDRAM images0/1/2. Each image validity crosses sys->pix after acknowledged final write. Media control holds pix framebuffer base -> W22 coherent handshake -> frame_reader memory-domain frame boundary latch -> original two-register base pixel path. Photo alpha and cover flags take the same two-cycle OSD pipeline; audio wave one-cycle output takes existing extra alignment cycle. Final compositor/HDMI unchanged.
''',
 'doc/arch/risks.md': '''
## media_carousel_20261103

Three supplied photographs require the new SD files in the card root; JPEG/PNG originals are PC-side source only. Runtime media is24-bit native640x480 BMP, with3.6864MB reserved SDRAM before the unchanged audio pool. Missing media stays on a clean fallback and never blocks clinic entry; duplicate/corrupt required media reports a storage fallback. Native TD area and routed setup/hold must be remeasured after the signed mixer repair. No board photos, HDMI sink behavior, TF-card speed measurement or physical acceptance is claimed.
''',
 'doc/arch/handoff_packet.md': '''
## media_carousel_20261103

Media/cover architecture and protocol are frozen in `doc/spec/media_carousel_20261103.md` and the corresponding interface amendment. Supplied originals plus conversion hashes live in `assets/media_source` and `assets/media_manifest.json`. Preserve previous sealed releases and the pre-media snapshot. Remaining gates are full source-bound simulation, encrypted-controller media/top/audio/no-card tests, native dual-corner routed STA, fresh bitgen and extraction/hash sealing. Board tests remain separate.
''',
 'doc/spec/behavior_spec.md': '''
## media_carousel_20261103

Authoritative additional requirements, timings, fallback rules and acceptance gates: `doc/spec/media_carousel_20261103.md`. All existing room, queue, switch, patient, speech and seamless subtitle behavior remains in force after clinic entry. Cover entry is a separately consumed action. Additional audio correction: both16bit tone/PCM inputs are sign-extended, mixed in17bits, multiplied by unsigned Q0.8 volume, shifted arithmetically8bits, saturated to signed16bit. Independent integer reference must cover silence, both signs, saturation, volume0/1/128/255 and strobe holds. PCM files and phrase order are unchanged.
''',
 'doc/intake/summary.md': '''
## media_carousel_20261103

User supplied cover and male/female doctor photographs. Implement SD-based cover startup and isolated any-key clinic entry, compressed right map, one-photo smooth fade carousel, final-audio waveform and a new reproducible delivery package. Larger PNG male selected; both male originals preserved. All four hardware key/room switch meanings after entry remain unchanged. User authorizes local implementation/simulation/TD/package, not board download.
''',
 'tb/scenario_matrix.md': '''
## media_carousel_20261103

| Test | Stimulus and independent acceptance |
|---|---|
| tb_cover_isolation | Four entry keys, boot-held/bounce/multi-key cases, cover switch changes, release baseline, fresh clinic events, frame-only fade/hidden base swap, missing media |
| tb_named_bmp | Shuffled named images, unrelated BMP, duplicate rejection and sparse stable IDs |
| tb_media_invalid | Named2x2 cover rejected by native profile, no partial valid publication |
| tb_media_assets | Actual SD BMP bytes, multi-cluster files, asynchronous/backpressured writes,921600 exact RGB beats, all54 PCM metadata/payloads |
| tb_media_pixels | Actual BMP reference, exact cover,18 independent fade raster cases, clinic/subtitle preservation,19 actual RTL full frames |
| tb_audio_wave | Signed audio/saturation/silence, per-frame history, exact interpolation/AA and cover suppression |
| tb_audio_mixer_signed |4105 integer signed gain/saturation/strobe checks, independently reproduced original defect |
| tb_media_top | Actual board pins + full delivered image fixture, early cover, consumed return-entry key, full preload, concurrent A/B audio and display, exact final framebuffer pixels; run behavioral and encrypted physical-controller profiles |
''',
}

def main():
    for name,addition in UPDATES.items():
        p=ROOT/name
        current=p.read_text(encoding='utf-8')
        if MARK not in current:p.write_text(current.rstrip()+'\n'+addition,encoding='utf-8')
    # Keep the existing skeleton an authority for board ports; append concrete
    # media module/interface notes rather than duplicating application logic.
    p=ROOT/'rtl/top_skeleton.v'
    current=p.read_text(encoding='utf-8')
    if MARK not in current:
        p.write_text(current+'\n// media_carousel_20261103: board ports remain unchanged.\n// Concrete media/control/CDC instances are in top.v and interface_contract.yaml.\n',encoding='utf-8')
    print('Media architecture amendments written:',len(UPDATES))

if __name__=='__main__':main()
