// Based on badger/tests/hw_test_sim.cpp
#include <verilated.h>

// Include model header, generated from Verilating "marble_zest_frame.v"
#include "Vmarble_zest_frame.h"
#include <verilated_fst_c.h>
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
	char uart_buf0[100];
	char *uart_bufp = uart_buf0;
	int send_q = 0;

	// Tracing (vcd, really FST)
	VerilatedFstC* tfp = NULL;
	const char* flag = Verilated::commandArgsPlusMatch("trace");
	if (flag && 0==strcmp(flag, "+trace")) {
		Verilated::traceEverOn(true);
		// VL_PRINTF("Enabling waves into logs/vlt_dump.vcd...\n");
		tfp = new VerilatedFstC;
		top->trace(tfp, 9);  // Trace 9 levels of hierarchy
		// Verilated::mkdir("logs");
		tfp->open("topsim.vcd");  // Open the dump file
	}
	const char* lazys = Verilated::commandArgsPlusMatch("lazy");
	const int lazy = lazys && 0==strcmp(lazys, "+lazy");

	// Set some inputs
	top->gmii_rx_clk = 0;
	top->gmii_rxd_p= 0;
	top->gmii_rx_dv_p = 0;
	top->gmii_rx_er_p = 0;
	top->gmii_tx_clk = 0;
	top->FPGA_SCK = 0;
	top->FPGA_CSB = 0;
	top->FPGA_PICO = 0;
	top->BOOT_MISO = 0;
	top->b_we = 0;
	top->b_di = 0;

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
				!lazy || top->in_use );
			if (r==1) {  // Should never happen
				VL_PRINTF("Ethernet is dead\n");
				exit(1);
			}
			top->gmii_rxd_p = eth_in_hold;
			top->gmii_rx_dv_p = eth_in_s_hold;
		}

		// UART Tx handling
		if (top->gmii_rx_clk==1) {
			if (send_q) {
				top->b_we = 1;
				top->b_di = 'q';
				send_q = 0;
			} else {
				top->b_we = 0;
				top->b_di = 0;
			}
		}

		// Evaluate model
		top->eval();

		// UART Rx handling
		if (top->b_dv && top->gmii_rx_clk==0) {
			// printf("UART Rx: 0x%2x\n", top->b_do);
			int emit=0;
			*uart_bufp++ = top->b_do;
			if (uart_bufp >= (uart_buf0 + 80)) {
				*uart_bufp++ = 0x0a;
				emit = 1;
			}
			if (emit || top->b_do == 0x0a) {
				*uart_bufp++ = 0;
				fputs(uart_buf0, stdout);
				if (strcmp(uart_buf0, "ook\n") == 0) {
					printf("boot request detected!\n");
					send_q = 1;
				}
				uart_bufp = uart_buf0;
				// Truly a special case
			}
		}

		// Dump trace data for this cycle
		if (tfp) tfp->dump (main_time);
	}

	// Final model cleanup
	top->final();
	if (tfp) { tfp->close(); tfp = NULL; }

	// Coverage analysis (since test passed)
#if VM_COVERAGE
	Verilated::mkdir("logs");
	VerilatedCov::write("logs/coverage.dat");
#endif

	// Destroy model
	delete top;

	// Fin
	exit(0);
}
