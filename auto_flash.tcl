# ================================
# auto_flash.tcl
#
# Usage:
#   vivado -mode tcl -source auto_flash.tcl -tclargs path/to/file.bit
#
# Automatically connects to hardware server and flashes a given bitfile.
# Retries indefinitely until success.
# ================================

# Read bitfile path from command line args
if { $argc < 1 } {
    puts "ERROR: No bitfile provided."
    puts "Usage: vivado -mode tcl -source auto_flash.tcl -tclargs <bitfile>"
    exit 1
}

set bitfile [lindex $argv 0]
puts "Using bitfile: $bitfile"

# Open hardware manager
open_hw_manager

# Connect to hw_server (local by default)
puts "Connecting to hardware server..."
connect_hw_server

# Open a target device
puts "Opening hardware target..."
current_hw_target [lindex [get_hw_targets] 0]
open_hw_target

# Get the first device
set device [lindex [get_hw_devices] 0]

if {$device eq ""} {
    puts "ERROR: No hardware devices found!"
    exit 1
}

puts "Found device: $device"


# Loop until programming succeeds
set success 0
while {!$success} {
    puts "Attempting to program device..."

    # Try programming
    set result [catch {
        current_hw_device $device
        set_property PROGRAM.FILE $bitfile $device
        program_hw_devices $device
    } errMsg]

    if {$result == 0} {
        puts "======================================="
        puts "SUCCESS: Device programmed correctly!"
        puts "======================================="
        set success 1
    } else {
        puts "---------------------------------------"
        puts "ERROR: Programming failed:"
        puts $errMsg
        puts "Retrying in 1 second..."
        puts "---------------------------------------"
        after 1000
    }
}
