# Default use ALS-U frequency settings
# set FREQ_SETTING_SIRIUS = 1 for SIRIUS settings
# details see README.md
FREQ_SETTING_SIRIUS = 1

ifneq ($(FREQ_SETTING_SIRIUS),1)
# ALSU      ADV: 500 * 11 / 11 / 4 / 200 / 2 * (1<<14)    = 4693
#           FCNT_EXP = 500 * 11 / 12 * (1<<16) / 4 / 125  = 60074
    SYNTH_OPT += -DPH_DIFF_ADV=4693
    CFLAGS += -DFCNT_EXP=60074
else
# SIRIUS    ADV: 500 * 23 / 24 / 4 / 200 / 2 * (1<<14)    = 4907
# SIRIUS    FCNT_EXP = 500 * 23 / 24 * (1<<16) / 4 / 125  = 62805

# USPAS     ADV: 460 / 4 / 200 / 2 * (1<<14)              = 4710
# USPAS     FCNT_EXP = 460 * (1<<16) / 4 / 125            = 60293
    SYNTH_OPT += -DPH_DIFF_ADV=4710
    CFLAGS += -DFCNT_EXP=60293
    VFLAGS += -DFREQ_SETTING_SIRIUS
	VFLAGS_DEP += -DFREQ_SETTING_SIRIUS
endif
