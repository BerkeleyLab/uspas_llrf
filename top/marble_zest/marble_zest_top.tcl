set outputDir ./_xilinx
file mkdir $outputDir


# Read in dependencies file
set flist [lindex $argv 0]
puts "Obtaining dependencies from $flist"

# Read in FSET identifier
set fset [lindex $argv 1]
puts "Building for $fset"

# Read in defines such as frequency
set verilog_defines [lindex $argv 2]
puts "Obtaining $verilog_defines"

set clean_str [string map {"-D" ""} $verilog_defines]
set verilog_defines_list [regexp -all -inline {\S+} $clean_str]
set verilog_defines_list [linsert $verilog_defines_list 0 "REVC_1W"]
puts "verilog_defines_list: $verilog_defines_list"

# extract REFCLK_FREQ from verilog_defines
set match [lsearch -inline -glob $verilog_defines_list "EVR_GT_REF_FREQ_MHZ=*"]
set REFCLK_FREQ [lindex [split $match "="] 1]

# Marble
set part "xc7k160tffg676-2"
puts "Synthesizing for part $part"

create_project marble_zest_top_$fset $outputDir -part $part -force

if {[llength $argv] >= 5} {
    set gitid_tcl [lindex $argv 3]
    puts "Sourcing $gitid_tcl"
    source $gitid_tcl

    set gt_tcl [lindex $argv 4]
    puts "Sourcing $gt_tcl with REFCLK_FREQ=$REFCLK_FREQ"
    source $gt_tcl
}
# git context information
array set git_status [get_git_context]

# this old_commit value matches that in build_rom.py --placeholder_rev
set old_commit [string toupper "da39a3ee5e6b4b0d3255bfef95601890afd80709"]
set new_commit $git_status(full_id)
git_id_print $new_commit

# Read in sources
set fp [open $flist r]
set file_data [read -nonewline $fp]
set f_lines [split $file_data "\n"]
close $fp

set flist_work ""
set flist_lib ""
# Filter out VHDL sources that need adding to libraries
foreach l $f_lines {
   if { [string match "*-library*" $l] } {
      lappend flist_lib $l
   } else {
      lappend flist_work $l
   }
}

puts "Adding VHDL files to libraries"
foreach l $flist_lib {
   set cmd "read_vhdl $l"
   puts $cmd
   eval $cmd
}

puts "Adding all other sources"
puts $flist_work
add_files $flist_work

# Set design-top
set_property  top "marble_zest_top" [current_fileset]
set gitid_for_filename $git_status(short_id)$git_status(suffix)

set_property verilog_define $verilog_defines_list [current_fileset]
puts "DEFINES:"
puts [get_property verilog_define [current_fileset]]

launch_runs synth_1 -verbose
wait_on_run synth_1
open_run synth_1
# Compress image
set_property BITSTREAM.GENERAL.COMPRESS  TRUE  [current_design]

set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
launch_runs impl_1 -to_step route_design -verbose
wait_on_run impl_1
puts "Implementation done!"

open_run impl_1

set UID 32'hFEED0001
set_property BITSTREAM.CONFIG.USERID $UID [current_design]
set_property BITSTREAM.CONFIG.USR_ACCESS NONE [current_design]

proc project_rpt {dest_dir} {
    # Generate implementation timing & power report
    report_power -file $dest_dir/imp_power.rpt
    report_datasheet -v -file $dest_dir/imp_datasheet.rpt
    report_cdc -v -details -file $dest_dir/cdc_report.rpt
    report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -input_pins -file $dest_dir/imp_timing.rpt
    # http://xillybus.com/tutorials/vivado-timing-constraints-error
    if {! [string match -nocase {*timing constraints are met*} [report_timing_summary -no_header -no_detailed_paths -return_string]]} {
        puts "Timing constraints weren't met. Please check your design."
        exit 2
    }
}

# Report error on failed timing
set dest_dir "$outputDir/marble_zest_top_$fset.runs"
project_rpt $dest_dir

# See bedrock for explanation
swap_gitid $old_commit $new_commit 16 0
swap_gitid $old_commit $new_commit 8 0

write_bitstream -force -bin_file marble_zest_top_$fset.$gitid_for_filename.bit
write_bitstream -force marble_zest_top_$fset.$gitid_for_filename.x.bit

apply_bit_stamp_mod marble_zest_top_$fset.$gitid_for_filename $git_status(dirty) $git_status(time)
