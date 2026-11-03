# MedQ V0.3 completed local workflow

Specification R01..R14 frozen; independent V0.2 baseline891 files protected.

Implementation: dual independent clinic FIFOs/state/timers, strict return priority, fair serial audio, safe PCM pause/abort, frame-atomic dual UI, compact production font.

Functional: final39/39 ModelSim and real encrypted SDRAM system/audio/basic, independent AC/refresh/bandwidth model, vendor PLL/serializer PASS. Resume boundary assertion rejects prior RTL and passes final RTL.

Resource repair: first native attempt84/64 BRAM rejected; one 4K font window reduces to42/64, all4096 words and12 RTL frames unchanged.

Final routed native STA: setup+0.692ns, hold+0.023ns, TNS0, slow/fast max/min all checked, no internal exclusions. Source-bound new bitstream generated and fresh STA rechecked.

Final release verification: see deliverables/latest_v03.json and ZIP DELIVERY_MANIFEST.json. All prior attempts/candidates are historical only, including pre-resume bitgen; final bit is source-bound via latest_timing_bitstream.json.

board_test: not_tested. No programming performed.
