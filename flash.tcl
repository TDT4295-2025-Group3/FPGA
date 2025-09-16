# Open and configure hardware
puts "Opening hardware manager..."
open_hw_manager
connect_hw_server
open_hw_target

# Detect FPGA device
set devices [get_hw_devices]
if {[llength $devices] == 0} {
    puts "ERROR: No FPGA devices found!"
    exit 1
}
set dev [lindex $devices 0]
puts "Using device: $dev"

# Make sure Vivado focuses on this device
current_hw_device $dev

# Program the FPGA
set bitstream [file normalize "build/vga-rasterizer.bit"]
puts "Programming bitstream: $bitstream"
set_property PROGRAM.FILE $bitstream $dev
program_hw_devices $dev -force -verbose

# Refresh device to make sure it's initialized
refresh_hw_device $dev

puts "Programming complete."

# Close hardware manager
close_hw_manager
puts "Hardware manager closed."
