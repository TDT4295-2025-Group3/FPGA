# ===================================================
# Vivado Non-Project Build Script
# ===================================================

# Create build directory
file mkdir build
cd build

# ---------------------------------------------------
# Function to collect SystemVerilog files recursively
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

# ---------------------------------------------------
# Read filelist.f (preferred source list)
set filelist_path "../filelist.f"
if {[file exists $filelist_path]} {
    set fp [open $filelist_path r]
    set files [split [read $fp] "\n"]
    close $fp
    foreach file $files {
        if {[string trim $file] eq ""} { continue }
        puts "Reading file: ../$file"
        read_verilog -sv ../$file
    }
} else {
    puts "ERROR: filelist.f not found at $filelist_path"
    exit 1
}

# ---------------------------------------------------
# Add Xilinx XPM memory library
read_verilog -library xpm $::env(XILINX_VIVADO)/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv

# ---------------------------------------------------
# Handle divider IP (if present)
if {[file exists ../src/renderer/rasterizer/div_rasterizer/div_rasterizer.xci]} {
    puts "Adding IP: div_rasterizer"
    read_ip ../src/renderer/rasterizer/div_rasterizer/div_rasterizer.xci
    upgrade_ip [get_ips div_rasterizer]
    generate_target all [get_ips div_rasterizer]
    synth_ip [get_ips div_rasterizer]
    export_ip_user_files -of_objects [get_ips div_rasterizer] -no_script -force -sync
    export_simulation   -of_objects [get_ips div_rasterizer] -directory ./sim -force
} else {
    puts "WARNING: div_rasterizer.xci not found!"
}

# ---------------------------------------------------
# Add tris.mem
if {[file exists ../src/tris.mem]} {
    puts "Reading memory file: ../src/tris.mem"
    read_mem ../src/tris.mem
} else {
    puts "WARNING: tris.mem not found!"
}

# ---------------------------------------------------
# Add constraints
if {[file exists ../constraints/arty.xdc]} {
    puts "Reading constraints: ../constraints/arty.xdc"
    read_xdc ../constraints/arty.xdc
} else {
    puts "WARNING: Constraints file not found!"
}

# ---------------------------------------------------
# Full Flow
puts "Starting synthesis..."
synth_design -top "top" -part "xc7a35ticsg324-1L"

report_timing_summary -file post_synth_timing_summary.rpt
report_utilization     -file post_synth_utilization.rpt

puts "Running implementation..."
opt_design
place_design
route_design

report_timing_summary -file timing_summary.rpt
report_timing -max_paths 10 -delay_type max -file timing_critical_paths.rpt
report_timing -max_paths 10 -delay_type min -file timing_hold_paths.rpt
report_utilization -file utilization.rpt

puts "Writing bitstream..."
write_bitstream -force "vga-rasterizer.bit"

puts "Bitstream build complete!"
