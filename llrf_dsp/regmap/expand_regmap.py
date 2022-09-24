import json
import sys

def main(argv):
    manual = argv[1]
    auto = argv[2:]
    with open(manual, 'r') as f:
        regmap = json.load(f, parse_int=int)

    for core in auto:
        with open(core, 'r') as f:
            auto_regmap = json.load(f, parse_int=int)
        regmap.update(auto_regmap)
    print(json.dumps(regmap, indent=4, sort_keys=True))

if __name__ == "__main__":
    main(sys.argv)
