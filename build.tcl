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

# Read package files first (always -sv)
foreach file [lsort $pkg_files] {
    puts "Reading package file (SystemVerilog): $file"
    read_verilog -sv $file
}

# Then read other design files (always -sv)
foreach file [lsort $other_files] {
    puts "Reading design file (SystemVerilog): $file"
    read_verilog -sv $file
}

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
report_timing_summary
report_utilization

# Optimize, place, and route
puts "Running implementation..."
opt_design
place_design
route_design

# Write bitstream
puts "Writing bitstream..."
write_bitstream -force "vga-rasterizer.bit"

puts "✅ Bitstream build complete!"
