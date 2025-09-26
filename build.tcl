# ============================
# Vivado Build Script (Tcl)
# ============================

# Create build directory
file mkdir build
cd build

# Recursively collect SystemVerilog files
proc get_sv_files {dir} {
    set files {}
    foreach f [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $f]} {
            # Recursively search subdirectories
            lappend files {*}[get_sv_files $f]
        } elseif {[string match *.sv [file tail $f]]} {
            lappend files $f
        }
    }
    return $files
}

# Get all SV files
set all_sv_files [get_sv_files ../src]

# Split into package files and other modules
set pkg_files {}
set other_files {}
foreach f $all_sv_files {
    if {[string match "*_pkg.sv" $f]} {
        lappend pkg_files $f
    } else {
        lappend other_files $f
    }
}

# Read files from filelist.f (one file per line)
set filelist_path "../filelist.f"
if {[file exists $filelist_path]} {
    set fp [open $filelist_path r]
    set files [split [read $fp] "\n"]
    close $fp
    foreach file $files {
        if {[string trim $file] eq ""} { continue }
        puts "Reading file (SystemVerilog): ../$file"
        read_verilog -sv ../$file
    }
} else {
    puts "ERROR: filelist.f not found at $filelist_path"
    exit 1
}

# Read Xilinx XPM library
read_verilog -library xpm $::env(XILINX_VIVADO)/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv

# Read constraint file (if exists)
if {[file exists ../constraints/arty.xdc]} {
    puts "Reading constraints: ../constraints/arty.xdc"
    read_xdc ../constraints/arty.xdc
} else {
    puts "WARNING: Constraints file not found!"
}

# Synthesize design
puts "Starting synthesis..."
synth_design -top "top" -part "xc7a35ticsg324-1L"

# Basic reports after synthesis
report_timing_summary -file post_synth_timing_summary.rpt
report_utilization     -file post_synth_utilization.rpt

# Optimize, place, and route
puts "Running implementation..."
opt_design
place_design
route_design

# Reports after implementation
puts "Generating timing and utilization reports..."
report_timing_summary -file timing_summary.rpt
report_timing -max_paths 10 -delay_type max -file timing_critical_paths.rpt
report_timing -max_paths 10 -delay_type min -file timing_hold_paths.rpt
report_utilization -file utilization.rpt

# Write bitstream
puts "Writing bitstream..."
write_bitstream -force "vga-rasterizer.bit"

puts "✅ Bitstream build complete!"
