# V0.3 SW1/C-D release integrity (2026-10-31)

Current authority: deliverables/latest_v03.json plus the ZIP's DELIVERY_MANIFEST.json. Each package uses a fresh non-overwriting timestamp. Every archived file is actually extracted and SHA256 checked. seal_timing_release.py repeats current simulation/source, baseline, archive and working-copy identity checks.

41 ModelSim tests, 28 release-tool positive/negative controls, actual-controller integration profiles, original routed database, native final slow/fast setup/hold reports, fresh imported-DB STA and new bitstream are preserved. Original pre-fix route QoR is retained and explicitly distinguished from final post-fix timing; no report or endpoint count is overwritten.

V0.2's 891 files, protected root artifacts, previous visual ZIP and bitstream are retained. Baseline snapshots are in baseline/v03_pre_sw1_queue_fix_20261031. Current functional amendment, C/D RTL previews, 12 real full-top frames, 21 PCM assets, source audit and integration notes are included.

Archive manifest is not self-hashed. ZIP SHA256 sidecar and latest_v03.json stay outside ZIP to avoid circular hashes. Internal status snapshot may be ready_to_package; completed packaging is evidenced by the final outer pointer and verified archive.

board_test: not_tested. No board download, electrical validation or acoustic listening was performed.
