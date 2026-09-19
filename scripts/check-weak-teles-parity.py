"""Compare native and JS emission for an isolated weak-cache candidate.

This checks output equivalence on selected fixtures, not full compiler parity.
Run under run-rss-guarded.py; sources and every output are hashed in the report.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('prepare', ROOT / 'scripts/prepare-weak-teles-candidate.py')
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)
candidate = Path(sys.argv[1]).resolve()
destination = Path(sys.argv[2])
prepare.verify(candidate)
bun = Path.home() / '.bun/bin/bun'
folder = ROOT / 'build/weak-teles-parity'
folder.mkdir(exist_ok=True)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

report = {
    'scope': __doc__,
    'bun': subprocess.check_output([str(bun), '--version'], text=True).strip(),
    'compiler_sha256': {name: digest(path / 'comp.ts') for name, path in [('baseline', prepare.BASELINE), ('candidate', candidate)]},
    'fixtures': [],
}
for source in [
    'tests/typed-do-shadow.bend',
    'tests/static-sum-layout.bend',
    'tests/compiler-dot-state.bend',
    'packages/runtime/test/deferred.bend',
    'packages/runtime/test/http-line.bend',
    'packages/runtime/test/schema-builder.bend',
]:
    row = {'source': source, 'source_sha256': digest(ROOT / source), 'outputs': {}}
    for suffix in ['c', 'js']:
        outputs = []
        for name, compiler in [('baseline', prepare.BASELINE), ('candidate', candidate)]:
            output = folder / f'{Path(source).stem}-{name}.{suffix}'
            run = subprocess.run([str(bun), str(compiler / 'main.ts'), source, '-o', str(output)], cwd=ROOT, capture_output=True, text=True, timeout=120)
            assert run.returncode == 0, (source, name, suffix, run.stdout, run.stderr)
            outputs.append(output.read_bytes())
        assert outputs[0] == outputs[1], (source, suffix, 'emission differs')
        row['outputs'][suffix] = {'identical': True, 'bytes': len(outputs[0]), 'sha256': hashlib.sha256(outputs[0]).hexdigest()}
    report['fixtures'].append(row)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + '\n')
    print(source, 'C/JS identical', flush=True)
prepare.verify(candidate)
