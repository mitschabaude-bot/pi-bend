"""Check generic laws and verify that the proof gate rejects missing/broken proofs.

Python only orchestrates the checker. No Python implementation or finite value
corpus supplies evidence for the universally quantified Bend laws.
"""
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BEND = os.environ.get('BEND', str(Path.home() / '.bend/bin/bend'))
def import_closure():
    pending = [ROOT / 'LAWS.bend', ROOT / 'PROOF.bend']
    visited = set()
    while pending:
        path = pending.pop().resolve()
        if path in visited:
            continue
        path.relative_to(ROOT)  # Never copy files outside this checkout.
        visited.add(path)
        for relative in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE):
            pending.append(path.parent / relative)
    return sorted(str(path.relative_to(ROOT)) for path in visited)

FILES = import_closure()
for name in FILES:
    if name in ('LAWS.bend', 'PROOF.bend') or name.startswith(('laws/', 'proofs/')):
        source = (ROOT / name).read_text()
        assert '@unsafe' not in source and '?TODO' not in source, name

def check(directory, source):
    run = subprocess.run([BEND, source], cwd=directory, capture_output=True, text=True, timeout=60)
    return {'source': source, 'exit_code': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr}

def accepted(result):
    # Agent types import an existing effectful runtime annotation. Keep its
    # current count explicit: increases require review, not silent acceptance.
    summaries = {'All terms check.', 'All terms check, with 1 unsafe annotation.'}
    assert result['exit_code'] == 0 and any(line in summaries for line in result['stdout'].splitlines()), result

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
    extra_mutations = [
        ('insertion-drops-new-key', 'packages/runtime/src/record.bend',
         'case Nil{}: Property{key, value} <> Nil{}',
         'case Nil{}: Nil{}', 'proofs/record.set_properties_lookup'),
        ('replacement-keeps-old-value', 'packages/runtime/src/record.bend',
         'String.eq(key, name), Property{key, value} <> rest',
         'String.eq(key, name), Property{name, old} <> rest', 'proofs/record.set_properties_lookup'),
        ('set-insertion-is-no-op', 'packages/runtime/src/string-set.bend',
         'Set{R.set(Unit, entries, value, Unit{})}',
         'Set{entries}', 'laws/string-set.insert_membership'),
        ('removal-keeps-matching-entry', 'packages/runtime/src/record.bend',
         'Bool.pick(List<&2, Property<V>>, String.eq(name, key), tail, Property{name, value} <> tail)',
         'Property{name, value} <> tail', 'proofs/record.remove_properties_absent'),
        ('removal-discards-other-entries', 'packages/runtime/src/record.bend',
         'Bool.pick(List<&2, Property<V>>, String.eq(name, key), tail, Property{name, value} <> tail)',
         'tail', 'proofs/record.remove_properties_absent'),
        ('set-removal-is-no-op', 'packages/runtime/src/string-set.bend',
         'Set{R.remove(Unit, entries, value)}', 'Set{entries}', 'laws/string-set.remove_membership'),
        ('clear-forgets-mode', 'packages/agent/src/pending-message-queue.bend',
         'case PendingMessageQueue{mode, _}: new(M, mode)',
         'case PendingMessageQueue{mode, _}: new(M, T.All{})', 'laws/pending-queue.clear'),
        ('mode-change-discards-messages', 'packages/agent/src/pending-message-queue.bend',
         'PendingMessageQueue{mode, messages}\ndef enqueue',
         'PendingMessageQueue{mode, F.new(M)}\ndef enqueue', 'laws/pending-queue.set_mode'),
        ('enqueue-clears-other-queue', 'packages/agent/src/agent-queues.bend',
         'Queues{Q.enqueue(M, steering, message), followUp}',
         'Queues{Q.enqueue(M, steering, message), Q.clear(M, followUp)}', 'laws/agent-queues.enqueue_isolated'),
        ('drain-clears-other-queue', 'packages/agent/src/agent-queues.bend',
         '(Queues{remaining, other}, messages)',
         '(Queues{remaining, Q.clear(M, other)}, messages)', 'proofs/agent-queues.delivered_isolated'),
    ]
    for label, name, before, after, diagnostic in extra_mutations:
        target = directory / name
        original_extra = target.read_text()
        assert original_extra.count(before) == 1, label
        target.write_text(original_extra.replace(before, after))
        # Import under a namespace: standalone Set conflicts with Base.Set.
        # This checks the module exactly as production callers import it.
        (directory / 'mutation-module.bend').write_text(f'import ./{name} as Subject\n')
        typed = check(directory, 'mutation-module.bend')
        typed['module'] = name
        accepted(typed)
        proof_result = check(directory, 'PROOF.bend')
        rejected(proof_result, diagnostic)
        results['mutations'].append({'name': label, 'module_check': typed, 'proof_check': proof_result})
        target.write_text(original_extra)
    proof = directory / 'proofs/fifo.bend'
    text = proof.read_text()
    start = text.index('def Laws.fifo_enqueue(')
    end = text.index('\nlaw append_empty:', start)
    proof.write_text(text[:start] + text[end:])
    results['missing_proof'] = check(directory, 'PROOF.bend')
    rejected(results['missing_proof'], 'unfilled law')
results['sha256'] = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES + ['scripts/check-proofs.py']}
(ROOT / 'build/proof-check.json').write_text(json.dumps(results, indent=2) + '\n')
print(f"PASS generic laws; open obligations, missing proof and {len(results['mutations'])} well-typed mutations rejected")
