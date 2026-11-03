# V0.3 architecture

Business/input/announcer/UI in clk_pix25MHz, reset rst_n_pix. Existing sys50MHz and mem50MHz/+8ns clocks unchanged. qstate_pix->sys uses held cdc_bus_handshake. service_status_sys->pix existing held CDC. PCM descriptor and abort use independent toggles with stable metadata and drain acknowledgement. All hardware clocks free-running while paused.

## media_carousel_20261103

The board/PLL/SDRAM clock profile is unchanged. `media_valid` uses W3 held-bus request/ack CDC from sys to pix; framebuffer base uses W22 held-bus CDC pix to mem. The base is held for every memory frame stream and changes only at zero photo alpha; three complete hidden frames cover handshake and FIFO lookahead. `clinic_enable` crosses to sys through the existing bit synchronizer only for remote parameter writes. The pix clinic input frontend is held in reset until frame-committed entry plus debounced all-key release; this forces a fresh switch baseline. Audio history, visible snapshot, opacity, both room state snapshots and wave rendering share clk_pix. No fabric clock or new timing exception is introduced.
