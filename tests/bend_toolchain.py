"""The Bend compiler used by the test harnesses.

`BEND` is the compiler command (the `BEND` environment variable if set, else the
project toolchain's `main.ts`, else the home installation); `TOOLCHAIN` is the
project toolchain directory, used by harnesses that copy the compiler to inject
test-only primitives.
"""
import os
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
TOOLCHAIN = ROOT / 'build/bend-native-toolchain/bend2'
_native = TOOLCHAIN / 'main.ts'
BEND = os.environ.get('BEND', str(_native if _native.is_file() else Path.home() / '.bend/bin/bend'))
