set outputDir ./_xilinx
file mkdir $outputDir

# only source swap_gitid.tcl
if {[llength $argv] >= 5} {
    set aux_tcl [lindex $argv 4]
    puts "Sourcing $aux_tcl"
    source $aux_tcl
}

# git context information
array set git_status [get_git_context]

# this old_commit value matches that in build_rom.py --placeholder_rev
set old_commit [string toupper "da39a3ee5e6b4b0d3255bfef95601890afd80709"]
set new_commit $git_status(full_id)
git_id_print $new_commit

# Read in dependencies file
set flist [lindex $argv 0]
puts "Obtaining dependencies from $flist"

# Read in FSET identifier
set fset [lindex $argv 1]
puts "Building for $fset"

# Read in build identifier
# but unused
set build_id [lindex $argv 2]
puts "Building for $build_id"

# Read in defines such as frequency
set verilog_defines [lindex $argv 3]
puts "Obtaining $verilog_defines"

# Marble
set part "xc7k160tffg676-2"
puts "Synthesizing for part $part"

create_project marble_zest_top_$fset $outputDir -part $part -force

# now source gtx_config.tcl
if {[llength $argv] >= 5} {
    set aux_tcl [lindex $argv 5]
    puts "Sourcing $aux_tcl"
    source $aux_tcl
}

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

# Get shorter git commit ID for bitfile filename
set gitid_for_filename $git_status(short_id)$git_status(suffix)
# Disabled at least for now
# set gitid_v 32'h$gitid
# set new_defs [list "GIT_32BIT_ID=$gitid_v" "REVC_1W"]
set new_defs [list "REVC_1W"]

set baz [string map {"-D" ""} $verilog_defines]
set picorv_list [regexp -all -inline {\S+} $baz]
# Append to existing defines, if any
set cur_list [get_property verilog_define [current_fileset]]
set args [list {*}$new_defs {*}$picorv_list {*}$cur_list]

set_property verilog_define $args [current_fileset]
puts "DEFINES:"
puts [get_property verilog_define [current_fileset]]

launch_runs synth_1 -verbose
wait_on_run synth_1
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

write_bitstream -force -bin_file marble_zest_top_$fset.$gitid_for_filename.bit
write_bitstream -force marble_zest_top_$fset.$gitid_for_filename.x.bit

apply_bit_stamp_mod marble_zest_top_$fset.$gitid_for_filename $git_status(dirty) $git_status(time)
