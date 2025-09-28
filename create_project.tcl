# ===================================================
# Vivado Project Creation Script
# ===================================================

# Create build directory if it doesn't exist
file mkdir build
cd build

# Project name and top module
set proj_name "vga_rasterizer"
set top_name "top"
set part_name "xc7a35ticsg324-1L"

# Create project
create_project $proj_name . -part $part_name -force

# Enable SystemVerilog
set_property target_language Verilog [current_project]
set_property default_lib work [current_project]

# ---------------------------------------------------
# Collect sources from filelist.f
set filelist_path "../filelist.f"
if {[file exists $filelist_path]} {
    set fp [open $filelist_path r]
    set files [split [read $fp] "\n"]
    close $fp
    foreach file $files {
        if {[string trim $file] eq ""} { continue }
        puts "Adding file from filelist: ../$file"
        add_files ../$file
    }
} else {
    puts "ERROR: filelist.f not found at $filelist_path"
    exit 1
}

# Add XPM library
read_verilog -library xpm $::env(XILINX_VIVADO)/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv

# ---------------------------------------------------
# Add generated IPs
if {[file exists ../src/rasterizer/div_rasterizer/div_rasterizer.xci]} {
    puts "Adding IP: div_rasterizer"
    read_ip ../src/rasterizer/div_rasterizer/div_rasterizer.xci
    upgrade_ip [get_ips div_rasterizer]
    generate_target {synthesis implementation simulation} [get_ips div_rasterizer]
} else {
    puts "WARNING: div_rasterizer.xci not found!"
}

# ---------------------------------------------------
# Constraints
if {[file exists ../constraints/arty.xdc]} {
    puts "Adding constraints: ../constraints/arty.xdc"
    add_files ../constraints/arty.xdc
} else {
    puts "WARNING: Constraints file not found!"
}

# ---------------------------------------------------
# Set top module
set_property top $top_name [current_fileset]

# ---------------------------------------------------
# Launch runs
puts "Starting synthesis..."
launch_runs synth_1 -jobs 8
wait_on_run synth_1

open_run synth_1
report_timing_summary -file ${proj_name}_timing_synth.rpt
report_utilization    -file ${proj_name}_util_synth.rpt

puts "Running implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

open_run impl_1
report_timing_summary -file ${proj_name}_timing_impl.rpt
report_utilization    -file ${proj_name}_util_impl.rpt

# ---------------------------------------------------
