# Default use ALS-U frequency settings
# set FREQ_SETTING_SIRIUS = 1 for SIRIUS settings
# details see README.md
FREQ_SETTING_SIRIUS = 1

ifneq ($(FREQ_SETTING_SIRIUS),1)
# ALSU   ADV: 500 * 11 / 11 / 4 / 200 / 2 * (1<<14) = 4693
# FCNT_EXP = 500 * 11 / 12 * (1<<16) / 4 / 125
	SYNTH_OPT += -DPH_DIFF_ADV=4693
	CFLAGS += -DFCNT_EXP=60074
else
# SIRIUS ADV: 500 * 23 / 24 / 4 / 200 / 2 * (1<<14) = 4907
# FCNT_EXP = 500 * 23 / 24 * (1<<16) / 4 / 125
	SYNTH_OPT += -DPH_DIFF_ADV=4907
	CFLAGS += -DFCNT_EXP=62805
	VFLAGS += -DFREQ_SETTING_SIRIUS
endif
