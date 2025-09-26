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
# Recursively collect SystemVerilog files
proc get_sv_files {dir} {
    set files {}
    foreach f [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $f]} {
            lappend files {*}[get_sv_files $f]
        } elseif {[string match *.sv [file tail $f]]} {
            lappend files $f
        }
    }
    return $files
}

# Get SV files from ../src
set all_sv_files [get_sv_files ../src]

# Split into *_pkg.sv and others
set pkg_files {}
set other_files {}
foreach f $all_sv_files {
    if {[string match "*_pkg.sv" $f]} {
        lappend pkg_files $f
    } else {
        lappend other_files $f
    }
}

# ---------------------------------------------------
# Read files from filelist.f
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

# Add Xilinx XPM library
read_verilog -library xpm $::env(XILINX_VIVADO)/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv

# Add SystemVerilog files (packages first, then modules)
if {[llength $pkg_files] > 0} {
    puts "Adding package files..."
    add_files $pkg_files
}
if {[llength $other_files] > 0} {
    puts "Adding other SV files..."
    add_files $other_files
}

# ---------------------------------------------------
# Collect SystemVerilog testbenches in ../tb
set tb_sv_files [get_sv_files ../tb]

if {[llength $tb_sv_files] > 0} {
    puts "Adding testbench files from ../tb..."
    add_files -fileset sim_1 $tb_sv_files
}

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
set_property top tb_top [get_filesets sim_1]

# ---------------------------------------------------
# Run Synthesis
puts "Starting synthesis..."
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Open synthesized design for reports
open_run synth_1
report_timing_summary -file ${proj_name}_timing_synth.rpt -append
report_utilization    -file ${proj_name}_util_synth.rpt   -append

# ---------------------------------------------------
# Run Implementation
puts "Running implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Open implemented design for reports and bitstream
open_run impl_1
report_timing_summary -file ${proj_name}_timing_impl.rpt -append
report_utilization    -file ${proj_name}_util_impl.rpt   -append

# ---------------------------------------------------
# Write bitstream
puts "Writing bitstream..."
write_bitstream -force "vga-rasterizer.bit"

puts "✅ Bitstream build complete!"
