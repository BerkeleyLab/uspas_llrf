import json
import argparse


class LLRFConfig:
    def __init__(self, conf='LEMP',
                 settings_fname='../settings.json',
                 output_fname='../settings.vams',
                 ) -> None:
        """Config class to generate settings.vams for verilog inclusion

        Args:
            conf (str): Application configuration key (aka FSET),
              in ['LEMP', 'ALSU', 'USPAS']
            settings_fname (str): configuration json file path
        """
        with open(settings_fname) as f:
            configs = json.load(f)
        self.config = configs[conf]
        self.config['CORDIC_GAIN'] = 1.646760258

        self.write_verilog(output_fname)

    def __repr__(self) -> str:
        attr = [f'{k:20s}:{v:12}' for k, v in self.config.items()]
        s = '\n    '.join(attr)
        return f'{self.__class__.__name__}:\n    {s}'

    def write_verilog(self, output_fname='settings.vams'):
        with open(output_fname, 'w') as f:
            for k, v in self.config.items():
                f.write(f"`define {k} {v}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-f", "--settings_fname", default="../settings.json")
    parser.add_argument("-o", "--output_fname", default="../settings.vams")
    parser.add_argument("-c", "--conf", default="LEMP")
    args = parser.parse_args()

    llrf_config = LLRFConfig(**vars(args))
    print(llrf_config)
