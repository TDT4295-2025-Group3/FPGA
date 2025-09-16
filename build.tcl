# create build folder
file mkdir build
cd build

# recursively get SV files
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

# read all SystemVerilog files
foreach file [get_sv_files ../src] {
    puts "Reading $file"
    read_verilog -sv $file
}

# read constraints
if {[file exists ../constraints/arty.xdc]} {
    read_xdc ../constraints/arty.xdc
} else {
    puts "WARNING: Constraints file not found!"
}

# synthesize design
synth_design -top "top" -part "xc7a35ticsg324-1L"
report_timing_summary
report_utilization

# optimize, place & route
opt_design
place_design
route_design

# write bitstream
write_bitstream -force "vga-rasterizer.bit"
puts "Bitstream build complete!"
