// Based on badger/tests/hw_test_sim.cpp
#include <verilated.h>

// Include model header, generated from Verilating "marble_zest_frame.v"
#include "Vmarble_zest_frame.h"
#include <verilated_vcd_c.h>
#include "ethernet_model.h"

// Current simulation time (64-bit unsigned)
vluint64_t main_time = 0;
// Called by $time in Verilog
double sc_time_stamp() {
	return main_time;  // Note does conversion to real, to match SystemC
}

int main(int argc, char** argv, char** env) {

	Verilated::commandArgs(argc, argv);
	Verilated::debug(0);

	Vmarble_zest_frame* top = new Vmarble_zest_frame;

	// Tracing (vcd)
	VerilatedVcdC* tfp = NULL;
	const char* flag = Verilated::commandArgsPlusMatch("trace");
	if (flag && 0==strcmp(flag, "+trace")) {
		Verilated::traceEverOn(true);
		// VL_PRINTF("Enabling waves into logs/vlt_dump.vcd...\n");
		tfp = new VerilatedVcdC;
		top->trace(tfp, 9);  // Trace 9 levels of hierarchy
		// Verilated::mkdir("logs");
		tfp->open("topsim.vcd");  // Open the dump file
	}

	// Set some inputs
	top->gmii_rx_clk = 0;
	top->gmii_rxd= 0;
	top->gmii_rx_dv = 0;
	top->gmii_rx_er = 0;
	top->gmii_tx_clk = 0;
	top->FPGA_SCK = 0;
	top->FPGA_CSB = 0;
	top->FPGA_PICO = 0;
	top->UART_CTS = 0;
	top->UART_RX = 0;

	while (/* main_time < 1100 && */ !Verilated::gotFinish()) {
		main_time += 4;  // Time passes in ticks of 8ns
		// Toggle clocks and such
		top->gmii_rx_clk = !top->gmii_rx_clk;
		top->gmii_tx_clk = top->gmii_rx_clk;

		// Run Ethernet at falling edge of rx_clk
		if (top->gmii_rx_clk==0) {
			int eth_in_hold, eth_in_s_hold;
			int r = ethernet_model(
				top->gmii_txd, top->gmii_tx_en,
				&eth_in_hold, &eth_in_s_hold,
				top->in_use);
			if (r==1) {  // Should never happen
				VL_PRINTF("Ethernet is dead\n");
				exit(1);
			}
			top->gmii_rxd = eth_in_hold;
			top->gmii_rx_dv = eth_in_s_hold;
		}

		// Evaluate model
		top->eval();

		// Dump trace data for this cycle
		if (tfp) tfp->dump (main_time);
	}

	// Final model cleanup
	top->final();
	if (tfp) { tfp->close(); tfp = NULL; }

    //  Coverage analysis (since test passed)
#if VM_COVERAGE
	Verilated::mkdir("logs");
	VerilatedCov::write("logs/coverage.dat");
#endif

	// Destroy model
	delete top;

	// Fin
	exit(0);
}
