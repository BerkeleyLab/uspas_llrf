__all__ = ['llrf_app']
import os
import sys
base_dir = os.path.dirname(os.path.abspath(__file__)) or '.'
leep_dir = os.path.join(base_dir, '../../submodules/bedrock/projects/common')
if leep_dir not in sys.path:
    sys.path.insert(0, leep_dir)
