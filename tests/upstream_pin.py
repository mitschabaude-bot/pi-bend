"""The pi-mono commit the port targets (the v0.87.1 release since 2026-09-23),
and where that checkout lives.

Differential checks read upstream sources at this commit. The checkout is the
main pi-bend checkout's sibling `pi-mono` (found through git's common
directory, so worktrees elsewhere resolve it too), or PI_MONO when set.
Importing this module exports PI_MONO to subprocesses, so references and
inline scripts can read the same location.
"""
import os
import subprocess
from pathlib import Path

PIN = 'f07218c4d4bbc12bef056a7058c3dd49dfe41abe'

ROOT = Path(__file__).resolve().parents[1]


def _default_upstream() -> Path:
    common = subprocess.check_output(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=ROOT, text=True).strip()
    return Path(common).parent.parent / 'pi-mono'


UPSTREAM = Path(os.environ.get('PI_MONO') or _default_upstream()).resolve()
os.environ['PI_MONO'] = str(UPSTREAM)


def revision(path: Path = UPSTREAM) -> str:
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=path, text=True).strip()


def check_pin() -> Path:
    """Fail unless the upstream checkout is at the pin."""
    actual = revision()
    assert actual == PIN, f'{UPSTREAM} is at {actual}, expected {PIN}'
    return UPSTREAM


def check_sibling() -> Path:
    """For checks whose TypeScript references import `../../pi-mono/...`
    statically: that path resolves beside this checkout, so it must be the
    pinned tree too (a worktree under /tmp would see /tmp/pi-mono)."""
    sibling = ROOT.parent / 'pi-mono'
    assert sibling.resolve() == UPSTREAM or (sibling.is_dir() and revision(sibling) == PIN), f'{sibling} (used by static reference imports) is not the pinned tree {UPSTREAM}; run from a checkout beside it or link it'
    return UPSTREAM


# Every importer compares against upstream; verify the pin once up front.
check_pin()
