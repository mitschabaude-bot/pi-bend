"""Check generic laws with the trusted Bend compiler.

Python only orchestrates the checker. No Python implementation or finite value
corpus supplies evidence for the universally quantified Bend laws.
"""
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
NATIVE_COMPILER = ROOT / 'build/bend-native-toolchain/bend2/main.ts'
BEND = os.environ.get('BEND', str(NATIVE_COMPILER if NATIVE_COMPILER.is_file() else Path.home() / '.bend/bin/bend'))
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
    # The checker also counts template instantiations of the audited unsafe
    # definitions; that number varies with the import closure and is not
    # evidence. The exact source declarations are audited below.
    summary = re.compile(r'^All terms check(, with \d+ unsafe annotations)?\.$')
    assert result['exit_code'] == 0 and any(summary.match(line) for line in result['stdout'].splitlines()), result

# Templates are included in this source audit even when the checker does not
# count them as a concrete unsafe definition. Keep this list explicit.
unsafe_declarations = {
    (name, match.group(1))
    for name in FILES
    for match in re.finditer(r'^@unsafe\s+def ([^\s(]+)', (ROOT / name).read_text(), re.MULTILINE)
}
assert unsafe_declarations == {
    ('packages/ai/src/api/constrained-sampling.bend', 'run'),
    ('packages/ai/src/api/constrained-sampling.bend', 'nullAllowed'),
    ('packages/ai/src/api/openai-responses-stream.bend', 'loop'),
    ('packages/ai/src/api/openai-sse.bend', 'drive'),
    ('packages/runtime/src/callback.bend', 'factory'),
    ('packages/runtime/src/file-fold.bend', 'drive'),
    ('packages/runtime/src/http-response.bend', 'seek'),
    ('packages/runtime/src/http-body-consume.bend', 'drive'),
    ('packages/runtime/src/http-response.bend', 'drive'),
    ('packages/runtime/src/sse-reader.bend', 'drive'),
    ('packages/runtime/src/dns-search-run.bend', 'drive'),
    ('packages/runtime/src/dns-address-lookup.bend', 'drive'),
    ('packages/runtime/src/dns-tcp-connection.bend', 'drive'),
    ('packages/runtime/src/dns-tcp-query.bend', 'read'),
    ('packages/runtime/src/dns-udp-query.bend', 'read'),
    ('packages/runtime/src/http-response-reader.bend', 'drive'),
    ('packages/runtime/src/random-index.bend', 'retry'),
    ('packages/ai/src/utils/event-stream.bend', 'drive'),
    ('packages/runtime/src/schema-value.bend', 'compare'),
    ('packages/ai/src/utils/json.bend', 'encode'),
    ('packages/ai/src/utils/schema-json.bend', 'convert'),
    # Reached since the agent laws import the consolidated agent modules.
    ('packages/agent/src/agent-loop.bend', 'advanceCall'),
    ('packages/agent/src/agent-loop.bend', 'advanceLoop'),
    ('packages/agent/src/agent-loop.bend', 'consumeAssistantIterations'),
    ('packages/agent/src/agent-loop.bend', 'deliverParallel'),
    ('packages/agent/src/agent-loop.bend', 'deliverTurn'),
    ('packages/agent/src/agent-loop.bend', 'executeParallel'),
    ('packages/agent/src/agent-loop.bend', 'prepareParallel'),
    ('packages/agent/src/agent-loop.bend', 'sequentialBatch'),
    ('packages/agent/src/agent.bend', 'dispatch'),
    ('packages/ai/src/utils/validation-normalize.bend', 'run'),
    ('packages/ai/src/utils/validation.bend', 'coerceTasks'),
    ('packages/runtime/src/schema-errors.bend', 'collect'),
    ('packages/runtime/src/schema-load.bend', 'run'),
    ('packages/runtime/src/schema-string.bend', 'countFrom'),
    ('packages/runtime/src/schema-string.bend', 'joined'),
    ('packages/runtime/src/schema.bend', 'evaluate'),
}, unsafe_declarations

source_hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES + ['scripts/check-proofs.py']}

results = {'proof': check(ROOT, 'PROOF.bend')}
accepted(results['proof'])
assert source_hashes == {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in source_hashes}, 'proof sources changed during validation'
results['sha256'] = source_hashes
(ROOT / 'build').mkdir(exist_ok=True)
(ROOT / 'build/proof-check.json').write_text(json.dumps(results, indent=2) + '\n')
print("PASS generic laws")
