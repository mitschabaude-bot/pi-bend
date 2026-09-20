"""Check generic laws and verify that the proof gate rejects missing/broken proofs.

Python only orchestrates the checker. No Python implementation or finite value
corpus supplies evidence for the universally quantified Bend laws.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get('BEND', str(Path.home() / '.bend/bin/bend'))
FILES = ['LAWS.bend', 'PROOF.bend', 'packages/runtime/src/fifo.bend']

def check(directory, source):
    run = subprocess.run([BEND, source], cwd=directory, capture_output=True, text=True, timeout=60)
    return {'source': source, 'exit_code': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr}

def accepted(result):
    assert result['exit_code'] == 0 and 'All terms check.' in result['stdout'], result

def rejected(result, diagnostic):
    assert result['exit_code'] != 0 and diagnostic in result['stdout'] + result['stderr'], result

results = {'proof': check(ROOT, 'PROOF.bend'), 'open_laws': check(ROOT, 'LAWS.bend'), 'mutations': []}
accepted(results['proof'])
rejected(results['open_laws'], 'TODO')
mutations = [
    ('drop-enqueued-value', 'Queue{value <> incoming, outgoing}', 'Queue{incoming, outgoing}', 'fifo_enqueue'),
    ('omit-dequeued-value', 'case Queue{incoming, head <> tail}: (Queue{incoming, tail}, Some{head})', 'case Queue{incoming, head <> tail}: (Queue{incoming, tail}, None{})', 'fifo_dequeue'),
    ('reverse-transfer-order', 'takeFront(A, Nil{}, List.reverse(&2, A, incoming))', 'takeFront(A, Nil{}, incoming)', 'fifo_dequeue'),
]
(ROOT / 'build').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='proof-gate-', dir=ROOT / 'build') as temporary:
    directory = Path(temporary)
    for name in FILES:
        destination = directory / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, destination)
    module = directory / 'packages/runtime/src/fifo.bend'
    original = module.read_text()
    for label, before, after, law in mutations:
        assert before in original
        module.write_text(original.replace(before, after))
        typed = check(directory, 'packages/runtime/src/fifo.bend')
        accepted(typed)  # Rule out a syntax/type error as the reason for rejection.
        proof = check(directory, 'PROOF.bend')
        rejected(proof, f'LAWS.{law}')
        results['mutations'].append({'name': label, 'module_check': typed, 'proof_check': proof})
    module.write_text(original)
    proof = directory / 'PROOF.bend'
    text = proof.read_text()
    start = text.index('def Laws.fifo_enqueue(')
    end = text.index('\nlaw append_empty:', start)
    proof.write_text(text[:start] + text[end:])
    results['missing_proof'] = check(directory, 'PROOF.bend')
    rejected(results['missing_proof'], 'TODO')
results['sha256'] = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES + ['scripts/check-proofs.py']}
(ROOT / 'build/proof-check.json').write_text(json.dumps(results, indent=2) + '\n')
print('PASS generic FIFO laws; open obligations and three well-typed mutations rejected')
