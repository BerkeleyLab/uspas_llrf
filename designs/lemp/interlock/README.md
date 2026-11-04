# Interlocks for LEMP LCLS-I



    1 - import the interlock_mon.v from LCLS-II PRC/RFS design, and change the interlocks to:
        //   bit 0:  Internal PLL lock fault
        //   bit 1:  EPICS timeout
        //   bit 2:  Local oscillator out-of-range fault
        //   bit 3:  Klystron reverse amplitude
        //   bit 4:  beam over-voltage
        //   bit 5:  beam over-current
        //   bit 6:  Admin timeout (NOT YET USED)
        //   bit 7:  BAD Status from Modulator

        we had also imported the /python/interlock.py but is not fixed (it use FEED) so need further review later on!!
        A enable mask bitwise has been added to enable the BYPASS functionality on the specific interlock
        the mask is available to EPICs as a reg (defined in the interlock_wrapper.v as a localparam intlk_en_mask)

    2 - create a wrapper to organize all the requested interlocks functionality, instantiate it in
        marble_zest_mid.vh

    3 - remove all the interlocks related blocks of code that are actually in llrf_shell.v, move them to
        the wrapper and redefine the port between the wrapper and llrf_shell to keep the functionality as it is now.

    4 - import from LCLS-II all the required code to perform the interlock as is

    5 - create TB for the wrapper, and fix the one for interlock_mon block

    6 - using newad context define the register page for the interlocks block
## On main (plan step 9d)

Moved from the LEMP branch (2e25cd9) as-is (plan D23): newad, localbus segment 2, register map unchanged (`interlock_wrapper.json` is byte-identical). The top level (`top/lemp/`, step 9e) instantiates `interlock_wrapper` and merges its JSON into the config ROM.

- `make`: builds and runs `interlock_wrapper_tb` (self-checking, "Validation: PASS"). CI job `lemp_interlock_test`.
- `make interlock_wrapper_cdc.txt`: CDC check of `interlock_wrapper_skin.v` with all modules, from `interlock_wrapper_cdc_expand.v`. CI job `lemp_interlock_cdc_test`.
- `make interlock_wrapper_expand.v interlock_wrapper.json`: for the top level. The expand leaves out the modules `llrf_shell_expand.v` already has (`EXCLUDE` in `build.mk`).
- `interlock_mon_tb.v` is a waveform-only TB that does not compile against the current `interlock_mon` (as on the LEMP branch); it is not built.

Changes from the LEMP branch:

- **De-duplicated:** the stale `ddc.v`, `noniq_ddc.v` and `triggers.v` copies are gone. `adc_to_amp_phs` uses `llrf_dsp/ddc.v` and `noniq_ddc.v`, which the LEMP hardware build already used (the copies only ran in simulation, with the old Q sign and one clock less); the TB's PMOD trigger glue (the shell's job, tested in `designs/lemp/tb`) is dropped.
- **CDC fix:** the EPICS and admin watchdog faults (`ttlive` on `lb_clk`) are synchronized to `clk` (`reg_tech_cdc`) before they are ORed with the `clk`-domain `test_*_wdog_ok` bits. Before, interlock bits 1 and 6 mixed both domains into one flop (the two BAD crossings of the CDC check). The timeouts now reach `interlock_mon` two `clk` cycles later.
- **Build:** paths for main's layout (`DESIGN = lemp` sets `FSET`), the CDC rule reads the full netlist (on the LEMP branch it read the expand, which lacks `jit_rad_gateway`, and failed), and `cordicg_b22.v` is generated before the dependency scan of `interlock_wrapper.v`.
