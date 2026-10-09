from uspas_llrf import LLRFApp
from pprint import pprint
import time

if __name__ == "__main__":
    llrf = LLRFApp(
        addr="192.168.18.79:803", conf="ALSU", chan_keep=0x3ff,
        assert_system_bist=False)  # EVR not connected yet
    print(llrf)
    pprint(llrf.model.cal_factors)
    while True:
        try:
            df_mon = llrf.get_rfmon()
            print('#' * 40)
            print(df_mon)
        except TimeoutError:
            pass
        time.sleep(0.5)
