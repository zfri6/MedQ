# ModelSim batch/GUI script. Copy to sim/modelsim/run.do and launch from that directory:
#   cd sim/modelsim ; vsim -c -do run.do          (batch)
#   cd sim/modelsim ; vsim -gui -do run.do        (GUI, then "do wave.do")
# Paths are relative to sim/modelsim/. Replace <TD_HOME> with the td_home value from doc/hw/toolchain.json
# only when the design instantiates Anlogic IP from rtl/al_ip/.

vlib work
vmap work work

# Design under test (Verilog-2001 subset that TD can synthesize)
vlog -work work +define+SIMULATION +incdir+../../rtl ../../rtl/*.v

# Anlogic IP wrappers and primitive models -- uncomment when rtl/al_ip/ is used
# vlog -work work +define+SIMULATION ../../rtl/al_ip/*.v
# vlog -work work -incr <TD_HOME>/sim_release/al/*.v
# vlog -work work -incr <TD_HOME>/sim_release/eg/*.v

# TestBench (SystemVerilog allowed here; never in rtl/)
vlog -work work -sv +define+SIMULATION +incdir+../../tb ../../tb/*.v

# Add +define+DUMP_VARS to the tb vlog line above to enable $dumpfile/$dumpvars in tb_top.v

vsim -voptargs=+acc work.tb_top
run -all
quit -f
