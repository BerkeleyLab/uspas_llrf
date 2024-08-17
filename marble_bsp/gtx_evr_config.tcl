set fset [lindex $argv 1]
puts "Building for $fset"

set MGT_CONFIG_DIR "../../submodules/bedrock/fpga_family/mgt"
source $MGT_CONFIG_DIR/mgt_gen.tcl

set config_dict [source ../../marble_bsp/gtx_config/gtx_config_$fset.tcl]

gen_ip "gtwizard" gtx_config $config_dict
