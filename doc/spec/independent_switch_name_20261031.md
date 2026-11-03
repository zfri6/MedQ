# Per-room calling control and name placeholder amendment

User-requested revision, 2026-10-31. This supersedes the former global SW1 gate and SW2/SW3 doctor mapping.

- SW1=SW[0]: A calling enabled at 0, stopped at 1. SW2=SW[1]: B calling enabled at 0, stopped at 1. Preserve the established electrical polarity.
- SW3=SW[2]: A doctor both-edge event. SW4=SW[3]: B doctor both-edge event. WAIT_CALL -> IN_VISIT (cancel this patient speech), IN_VISIT -> IDLE (complete this patient), IDLE does nothing. Startup levels never generate events.
- Keys keep the four queues live while either or both calling gates are off. Doctors, status, frames, and both marquees keep updating. Each room calling timer/grants freeze only while that room is off.
- Shared HDMI audio must not let a stopped A room block enabled B, or vice versa. Stop mutes and safely drains an active clip; remember the same room/ticket/class. On re-enable restart its interrupted sentence without a new grant/call count. Drop this replay if the doctor/current patient changes. The other room remains fairly arbitrated.
- QSTATE stays 128 bits: bit64=any calling enabled (legacy summary), bit65=inputs ready, bit66=A enabled, bit67=B enabled; existing room fields unchanged.
- Preserve independent A/B ordinary and C/D return sequences. C routes to A; D routes to B.
- Calling marquee examples: 请A01***到A诊室就诊; 请B01***到B诊室就诊; returns 请C01***到A诊室就诊 / 请D01***到B诊室就诊. Three literal ASCII asterisks stand in for a name. This is a subtitle change; the existing spoken number-to-room phrase and 21 PCM assets remain compatible.
- Keep the existing two-bit coverage font quality, screen geometry, clocks, board pins, SDRAM/HDMI pipelines, and timing constraint contracts.
- Verify all 16 switch startup combinations, contact bounce/held contacts, independent enable/doctor routing, audio stop/replay/cancel/fairness under real SDRAM, text pixels, full regression, fresh routed STA, fresh bitstream, and sealed archive. Board status stays not_tested until actual board evidence.
