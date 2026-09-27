"""Compare normalized component gestures and clipped hit testing with pi."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def sgr(code, x, y, release=False):
    return f"\x1b[<{code};{x};{y}{'m' if release else 'M'}"

# A nested leaf is at (10,5), width 20, height 4. Captured drags leave
# its clip; moved presses must not click. Repeated stationary releases
# advance the component's click count and wrap after the third click.
# Unhandled document presses enter pi's separate text-selection subsystem;
# this comparison covers gestures dispatched to a component.
sequences = [
    [sgr(0, 13, 7), sgr(0, 13, 7, True)] * 4,
    [sgr(0, 13, 7), sgr(32, 2, 2), sgr(0, 2, 2, True), sgr(0, 13, 7), sgr(0, 13, 7, True)],
    [sgr(code, 13, 7) for code in (64, 65, 72, 73, 35)],
    [sgr(28, 13, 7), sgr(28, 13, 7, True)],
]
for threads in (1, 4):
    for steps in sequences:
        expected = subprocess.check_output(['bun', 'tests/fullscreen_mouse_reference.mts'],
                                           cwd=ROOT, input=json.dumps(steps).encode())
        actual = subprocess.check_output([str(ROOT / 'build/fullscreen-mouse'), '--threads', str(threads), '--', *steps], cwd=ROOT)
        assert actual == expected, (threads, steps, actual.decode(), expected.decode())
    print(f'native{threads}: nested targeting, capture, signed coordinates, modifiers, click counts and wheel traces match pi')
