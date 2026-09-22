"""The Bend compiler used by the test harnesses: `BEND` if set, else the project toolchain, else the home installation."""
import os
from pathlib import Path
_native = Path(__file__).resolve().parents[1] / 'build/bend-native-toolchain/bend2/main.ts'
BEND = os.environ.get('BEND', str(_native if _native.is_file() else Path.home() / '.bend/bin/bend'))
