__all__ = ['llrf_app']
import sys
from pathlib import Path

p_bedrock = Path(__file__).resolve().parents[2] / 'submodules' / 'bedrock'
leep_dir = str(p_bedrock / 'projects' / 'common')
if leep_dir not in sys.path:
    sys.path.insert(0, leep_dir)

p_llrf_model = Path(__file__).resolve().parents[2] / 'llrf_dsp'
if str(p_llrf_model) not in sys.path:
    sys.path.insert(0, str(p_llrf_model))
