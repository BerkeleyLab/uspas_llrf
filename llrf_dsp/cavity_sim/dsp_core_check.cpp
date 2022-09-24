#include <fstream>
#include <sstream>
#include <iostream>
#include <iomanip>
#include <cmath>
#include <complex>

#include <verilated.h>
#include <verilated_vcd_c.h>
#include <assert.h>

#include "Vdsp_core_wrapper.h"

using namespace std;

#define CORDIC_GAIN    1.64676
#define LO_AMP         74840                    // < 2^17 / 1.64676
#define CLOSED_AMP_GAIN    2.9337 * CORDIC_GAIN     // Measured
#define CLOSED_PHS_GAIN    0                        // Measured, deg
#define OPEN_AMP_GAIN  1 << 19 / (int32_t)(CORDIC_GAIN * LO_AMP * CORDIC_GAIN)
#define OPEN_PHS_GAIN  0       // Measured, deg

#define OPEN_LOOP   0
#define CLOSED_LOOP 1

#define tick_tock top->clk = !top->clk;
#define DELAY_MEM_SIZE 2000
const complex<double> I(0.0,1.0);

// Current simulation time (64-bit unsigned)
vluint64_t main_time = 0;

class Cavity411
{
    public:

        Cavity411(double fmo, double Q_0, int delay)
        {
            //  Cavity parameters:
            //   cavity Q_0 = 35900 * 0.9, R=3.4 MOhm, Q_L = Q_0/2
            //   Baseband differential eq.:
            //   dVc/dt - (-\alpha + j\omega_d)Vc = 2\alpha * Vd
            //   where
            //   Vc:      drive voltage
            //   Vd:      cavity voltage
            //   \alpha:    half bandwidth = \omega_0 / (2*Q_L) = 1 / \tau
            //   \omega_d:  damping freq   = \omega_0 - \sqrt(\omega_0^2 - \alpha^2)
            //   \omega_0:  2 * \pi * 500.39 MHz
            //   Simplying:
            //   dVc/dt = 2\alpha * Vd - \alpha * Vc + j\omega_d * Vc
            //   dVc/dt = (j\omega_d - \alpha)Vc + 2\alpha* Vd ---> dVc/dt = a*Vc + b*K
            //   a = (j\omega_d - \alpha) --> a_i = -\alpha , a_q = omega_d
            //   b = 2\alpha --> b_i = 2\alpha , b_q = 0
            this->Q_L = Q_0/2.0;
            this->omega_0 = 2.0 * M_PI * fmo;
            this->alpha = omega_0 / (2.0 * Q_L);
            this->omega_d = omega_0 - sqrt(pow(omega_0, 2.0) - pow(alpha, 2.0));
            this->a_i = -alpha;
            this->a_q = omega_d;
            this->b_i = 2.0 * alpha;
            this->b_q = 0;
            this->a = a_i + a_q * I;
            this->b = b_i + b_q * I;
            this->time = 0;
            this->delay = delay;
            assert(delay < DELAY_MEM_SIZE);
        }

        ~Cavity411(){}

        void tick(int16_t drive, int16_t *fwd, int16_t *rev, int16_t *cav, int16_t *phr)
        {
            this->lo_phase = this->lo_phase > 10 ? 0 : this->lo_phase + 1;
            double th = this->lo_phase * 4.0 / 11.0 * 2.0 * M_PI;
            double cth = cos(th);
            double sth = sin(th);
            unsigned ix = this->lo_phase % 6;
            this->drv_i_hist[ix] = drive * cth;
            this->drv_q_hist[ix] = drive * sth;
            // Mixer output should be dominated by baseband and 2*f,
            // and averaging six values should fully reject 2*f.
            double drv_i=0.0, drv_q=0.0;
            for (unsigned jx=0; jx<6; jx++) {
                drv_i += this->drv_i_hist[jx];
                drv_q += this->drv_q_hist[jx];
            }
            drv_i = drv_i / 3.0;
            drv_q = drv_q / 3.0;
            this->drv_i_mem[(this->time + this->delay) % DELAY_MEM_SIZE] = drv_i;
            this->drv_q_mem[(this->time + this->delay) % DELAY_MEM_SIZE] = drv_q;
            complex<double> drv_v = this->drv_i_mem[(this->time) % DELAY_MEM_SIZE] + this->drv_q_mem[(this->time) % DELAY_MEM_SIZE] * I;

            // Done converting llrf_dsp drive output to a complex vector.
            // Ignore delays, scaling, and amplifier saturation
            complex<double> fwd_v = drv_v;

            // Now simulate cavity physics.  At it's simplest,
            // dV/dt = a*V + b*K
            // Depend on double-precision arithmetic, because cav_v changes very little each cycle
            complex<double> cav_v = this->cav_v;
            cav_v = cav_v + (this->a * cav_v + this->b * fwd_v);
            this->cav_v = cav_v;

            // Oversimplify this step, too: ignore delays, phase shifts, circulator
            complex<double> rev_v = cav_v - fwd_v;

            // Wouldn't be hard to add DC offset and white noise to these results
            if (fwd) *fwd = real(fwd_v) * cth + imag(fwd_v) * sth;
            if (rev) *rev = real(rev_v) * cth + imag(rev_v) * sth;
            if (cav) *cav = real(cav_v) * cth + imag(cav_v) * sth;
            if (phr) *phr = 10000.0 * cth;

            // Tick-tock
            this->time++;
        }

    private:
        double Q_L;
        double omega_0, omega_d;
        double alpha;
        double a_i, a_q;
        double b_i, b_q;
        int lo_phase;  // 0 to 10
        double drv_i_hist[6];
        double drv_q_hist[6];
        complex<double> cav_v;
        // dV/dt = a*V + b*K
        complex<double> a, b;
        // Memory
        double drv_i_mem[DELAY_MEM_SIZE];
        double drv_q_mem[DELAY_MEM_SIZE];
        unsigned int time;
        // Keep it cool
        unsigned int delay;
};

// Called by $time in Verilog
double sc_time_stamp() {
    return main_time;  // Note does conversion to real, to match SystemC
}

inline bool rising_edge(int c)
{
    return c == 1;
}

inline bool falling_edge(int c)
{
    return c == 0;
}

void polar2rect(int32_t amp, int32_t phase, int32_t *xv, int32_t *yv)
{
    double aa = phase * M_PI / pow(2, 18);
    *xv = (int32_t) (amp * cos(aa) * 1.64676);
    *yv = (int32_t) (amp * sin(aa) * 1.64676);
}

void rect2polar(int32_t x, int32_t y, int32_t *amp, int32_t *phase)
{
    double a2 = atan2((double)y, (double)x) *  pow(2, 18) / M_PI;
    if (a2 < 0.0) {
        a2 = a2 + 2.0 * 1.64676;
    }
    double r = sqrt(pow(x, 2.0) + pow(y, 2.0));
    *amp   = (int32_t) r;
    *phase = (int32_t) a2;
}

void reset(Vdsp_core_wrapper *top)
{
    int32_t a, p, x, y;
    rect2polar(1, 1, &a, &p);
    //polar2rect(a, p, &x, &y);

   //cout << "x= " << x << " y= " << y << " a= " << a << " p= " << p << endl;

    //Init clk
    top->clk = 1;
    top->reset = 1;

    //RF ADC inputs, after downconverted to IF
    top->cav_field = 0x0000; //[15:0]

    //Amp/phs setpoints
    top->amp_setpoint = 0x0; //[17:0]
    top->phs_setpoint = 0x0; //[17:0]

    //dds parameters
    top->dds_phase_step = 1561806288; //[19:0]
    top->dds_phase_shift = 0x0; //[18:0]
    top->dds_modulo = 0x4; //[11:0]

    //PI Loop
    top->Kp_amp = 0;
    top->Kp_phs = 0;
    top->Ki_amp = 0;
    top->Ki_phs = 0;
    top->loop_control = 0;
    top->loop_reset = 0;

    top->eval();
}

void sweep(Vdsp_core_wrapper *top, VerilatedVcdC *tfp, IData *sweep_var, uint64_t sweep_stop, std::string fname)
{
    vluint64_t max_run_time = 2*sweep_stop*8 + 8*50; //ticks
    int16_t fwd, rev, cav, phr;
    Cavity411 *cav_sim = new Cavity411(500.39e6, 35900 * 0.9, 100);

    main_time = 0;

    // We always give a output file
    ofstream wave_out(fname);
    wave_out << right  << "#" \
        << setw(16) << "main_time" \
        << setw(16) << "dac_out" \
        << setw(16) << "phs_setp" \
        << setw(16) << "meas_phs" \
        << setw(16) << "amp_setp" \
        << setw(16) << "meas_amp" \
        << setw(16) << "cav_field" \
        << endl;


    // Main loop
    while (main_time < max_run_time && !Verilated::gotFinish()) {
        // Do something on when clk == 1
        if (rising_edge(top->clk)) {
            cav_sim->tick((int16_t)top->dac_out, &fwd, &rev, &cav, &phr);
            //top->cav_field = cav;  // XXX bypass cavity model
            top->cav_field = (int16_t)top->dac_out;
            top->cav_fwd = fwd;
            top->cav_rev = rev;
            top->cav_phr = phr;
            top->reset = 0;

            if (main_time >= 8*50) {
                top->Kp_amp = 40000; // 18 bits
                top->Kp_phs = 80000; // 18 bits
                top->Ki_amp = 1500;
                top->Ki_phs = 3000;
                if (*sweep_var < sweep_stop) {
                    (*sweep_var)++;
                }
            }
        }

        // Evaluate dut
        top->eval();

        // Dump trace data for this cycle
        if (tfp) tfp->dump(main_time);

        // Write out wave file
        if (rising_edge(top->clk)) {
            wave_out << right \
                << setw(16) << main_time \
                << setw(16) << (int16_t)top->dac_out \
                << setw(16) << (int32_t)top->phs_setpoint \
                << setw(16) << (int32_t)top->phs_measured_debug \
                << setw(16) << (int32_t)top->amp_setpoint \
                << setw(16) << (int32_t)top->amp_measured_debug \
                << setw(16) << (int16_t)top->cav_field \
                << endl;

            if (*sweep_var == sweep_stop) {
                break;
            }
        }

        // Tick-tock!
        main_time += 4; // ticks
        tick_tock;
    }

    wave_out.close();
}


int main(int argc, char** argv, char** env)
{
    VerilatedVcdC *tfp = NULL;
    Verilated::commandArgs(argc, argv);
    Verilated::debug(0);

    // Get if we have a vcd flag
    const char *flag = Verilated::commandArgsPlusMatch("vcd");

    Vdsp_core_wrapper *top = new Vdsp_core_wrapper;

    // VCD file via +vcd argument
    if (flag && 0 == strcmp(flag, "+vcd")) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 9);  // Trace 9 levels of hierarchy
        tfp->open("dsp_core_wrapper.vcd");  // Open the vcd file
    }

    // closed Loop
    // Sweep phase: 1 to 2**17-1
    reset(top);
    top->loop_control = CLOSED_LOOP;
    top->phs_setpoint = 1;
    top->amp_setpoint = 10000;
    sweep(top, tfp, &top->phs_setpoint, (1 << 17), "dsp_core_sweep_phs_closed.dat");

    // Sweep amp: 1 to 2**17-1
    reset(top);
    top->loop_control = CLOSED_LOOP;
    top->phs_setpoint = 10000;
    top->amp_setpoint = 1;
    sweep(top, tfp, &top->amp_setpoint, (15000 * CLOSED_AMP_GAIN), "dsp_core_sweep_amp_closed.dat");

    // Open Loop
    // Sweep phase: 1 to 2**17-1
    reset(top);
    top->loop_control = OPEN_LOOP;
    top->phs_setpoint = 1;
    top->amp_setpoint = 10000;
    sweep(top, tfp, &top->phs_setpoint, (1 << 17), "dsp_core_sweep_phs_open.dat");

    // Sweep amp: 1 to 2**17-1
    reset(top);
    top->loop_control = OPEN_LOOP;
    top->phs_setpoint = 10000;
    top->amp_setpoint = 1;
    sweep(top, tfp, &top->amp_setpoint, (15000 * OPEN_AMP_GAIN), "dsp_core_sweep_amp_open.dat");

    // Final model cleanup
    top->final();
    if (tfp) { tfp->close(); tfp = NULL; }

    // Destroy model
    delete top;

    return 0;
}
