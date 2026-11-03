# V0.3 architecture

Hardware SW silk numbers unverified; default user map used. No board run. Tight BRAM/DSP budget requires TD measurement. Playback abort must drain in-flight memory. 99 finite tickets per reset deliberate. Missing reference image: textual layout controls. Native TD temp ASCII staging is runtime-only; evidence copied back within V0.3.

原生资源修订：生产字体显式4K窗口（virtual3584..7679），避免推断完整16K ROM；历史完整font_rom.hex仅供兼容单元回归，不增加生产第二字库。生产只实例化一个font_rom ADDR_W12，字模和两拍OSD延迟不变。

## media_carousel_20261103

Three supplied photographs require the new SD files in the card root; JPEG/PNG originals are PC-side source only. Runtime media is24-bit native640x480 BMP, with3.6864MB reserved SDRAM before the unchanged audio pool. Missing media stays on a clean fallback and never blocks clinic entry; duplicate/corrupt required media reports a storage fallback. Native TD area and routed setup/hold must be remeasured after the signed mixer repair. No board photos, HDMI sink behavior, TF-card speed measurement or physical acceptance is claimed.
