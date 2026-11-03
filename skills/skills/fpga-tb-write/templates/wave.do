# ModelSim waveform setup. Copy to sim/modelsim/wave.do; in the GUI run "do wave.do" after "do run.do".
# Adapt signal paths to the actual TB / DUT hierarchy (tb_top.dut.<signal>).

onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {Clock / Reset}
add wave -noupdate /tb_top/clk
add wave -noupdate /tb_top/rst_n

add wave -noupdate -divider {DUT ports}
add wave -noupdate -radix unsigned /tb_top/dut/*

add wave -noupdate -divider {TB status}
add wave -noupdate -radix unsigned /tb_top/cycle_count
add wave -noupdate -radix unsigned /tb_top/error_count

TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 220
configure wave -valuecolwidth 90
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {2 us}
