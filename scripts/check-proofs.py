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
    # The full owner import closure includes three existing schema/JSON
    # annotations as well as the original runtime annotation. None supplies
    # evidence for these laws; their exact source declarations are audited below.
    summaries = {'All terms check.', 'All terms check, with 1 unsafe annotation.',
                 'All terms check, with 4 unsafe annotations.'}
    assert result['exit_code'] == 0 and any(line in summaries for line in result['stdout'].splitlines()), result

def rejected(result, diagnostic):
    assert result['exit_code'] != 0 and diagnostic in result['stdout'] + result['stderr'], result

# Templates are included in this source audit even when the checker does not
# count them as a concrete unsafe definition. Keep this list explicit.
unsafe_declarations = {
    (name, match.group(1))
    for name in FILES
    for match in re.finditer(r'^@unsafe\s+def ([^\s(]+)', (ROOT / name).read_text(), re.MULTILINE)
}
assert unsafe_declarations == {
    ('packages/runtime/src/callback.bend', 'factory'),
    ('packages/ai/src/utils/event-stream.bend', 'drive'),
    ('packages/runtime/src/schema-value.bend', 'compare'),
    ('packages/ai/src/utils/json.bend', 'encode'),
    ('packages/ai/src/utils/schema-json.bend', 'convert'),
}, unsafe_declarations

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
        ('edns-code-uses-version', 'packages/runtime/src/dns-edns-response.bend',
         'Some{Response{_, upper, _, _, _}}: (upper * 16', 'Some{Response{_, _, version, _, _}}: (version * 16', 'laws/dns-edns-response.response_code_metadata_independent'),
        ('edns-duplicate-opt-accepted', 'packages/runtime/src/dns-edns-response.bend',
         'case True{} Done{Some{_}}: Fail{Duplicate{}}', 'case True{} Done{Some{prior}}: Done{Some{prior}}', 'laws/dns-edns-response.second_opt_rejected'),
        ('edns-misplaced-opt-accepted', 'packages/runtime/src/dns-edns-response.bend',
         'case True{}: Fail{Misplaced{}}', 'case True{}: Done{None{}}', 'laws/dns-edns-response.misplaced_opt_rejected'),
        ('udp-policy-ignores-invalid-opt', 'packages/runtime/src/dns-udp-policy.bend',
         'case Fail{error}: Fail{error}', 'case Fail{error}: Done{Accept{}}', 'laws/dns-udp-policy.invalid_extension_stops_policy'),
        ('dns-choice-ignores-forced-tcp', 'packages/runtime/src/dns-transport-choice.bend',
         'case True{}: TCP{}\n    case False{}: automatic', 'case True{}: UDP{}\n    case False{}: automatic', 'laws/dns-transport-choice.forced_tcp'),
        ('dns-choice-allows-extra-byte', 'packages/runtime/src/dns-transport-choice.bend',
         'case Zero{} _ <> _: True{}', 'case Zero{} _ <> _: False{}', 'laws/dns-transport-choice.exact_budget'),
        ('dns-choice-accepts-encoding-error', 'packages/runtime/src/dns-transport-choice.bend',
         'case Fail{error}: Fail{error}', 'case Fail{error}: Done{UDP{}}', 'laws/dns-transport-choice.invalid_encoding_stops_selection'),
        ('udp-fallback-restarts-server-list', 'packages/runtime/src/dns-udp-schedule.bend',
         'case Cursor{_, _, remaining}: selected <> remaining', 'case Cursor{_, original, _}: selected <> original', 'laws/dns-udp-schedule.fallback_current_pass'),
        ('udp-policy-accepts-server-failure', 'packages/runtime/src/dns-udp-policy.bend',
         'case FailureCode{}: Retry{ServerFailure{}}', 'case FailureCode{}: Accept{}', 'laws/dns-udp-policy.server_failure_retries'),
        ('udp-policy-accepts-unhelpful-empty', 'packages/runtime/src/dns-udp-policy.bend',
         'case True{}: Retry{UnhelpfulEmpty{}}', 'case True{}: Accept{}', 'laws/dns-udp-policy.unhelpful_success_retries'),
        ('udp-policy-accepts-truncation', 'packages/runtime/src/dns-udp-policy.bend',
         'case True{} False{}: UseTCP{}', 'case True{} False{}: Accept{}', 'laws/dns-udp-policy.truncation_uses_tcp'),
        ('udp-oversized-duration-accepted', 'packages/runtime/src/dns-udp-timeout.bend',
         'case Zero{} Succ{_}: Fail{OutOfRange{}}',
         'case Zero{} Succ{_}: Done{accumulated}', 'laws/dns-udp-timeout.oversized_duration_rejected'),
        ('udp-plan-replaces-first-server', 'packages/runtime/src/dns-udp-plan.bend',
         'case first <> second <> Nil{}: Done{Located{first, Timeout.First{}}',
         'case first <> +second <> Nil{}: Done{Located{second, Timeout.First{}}', 'laws/dns-udp-plan.assignment_preserves_payloads'),
        ('udp-plan-discards-position', 'packages/runtime/src/dns-udp-plan.bend',
         'case Done{duration}: Done{Attempt{server, position, duration}}',
         'case Done{duration}: Done{Attempt{server, Timeout.First{}, duration}}', 'laws/dns-udp-plan.timing_preserves_identity'),
        ('udp-plan-accepts-failed-layout', 'packages/runtime/src/dns-udp-plan.bend',
         'case Fail{error}: Fail{error}', 'case Fail{error}: Done{Nil{}}', 'laws/dns-udp-plan.invalid_layout_stops_preparation'),
        ('udp-plan-discards-excess-servers', 'packages/runtime/src/dns-udp-plan.bend',
         'case _ <> _ <> _ <> _ <> _: Fail{TooManyServers{}}',
         'case _ <> _ <> _ <> _ <> _: Done{Nil{}}', 'laws/dns-udp-plan.assignment_preserves_payloads'),
        ('udp-duration-can-be-zero', 'packages/runtime/src/dns-udp-timeout.bend',
         'case Duration{additional}: Succ{additional}', 'case Duration{additional}: additional', 'laws/dns-udp-timeout.duration_positive'),
        ('udp-zero-timeout-floor-is-two', 'packages/runtime/src/dns-udp-timeout.bend',
         'case Zero{}: Duration{Zero{}}', 'case Zero{}: Duration{Succ{Zero{}}}', 'laws/dns-udp-timeout.zero_floor'),
        ('udp-positive-timeout-inflated', 'packages/runtime/src/dns-udp-timeout.bend',
         'case Succ{rest}: Duration{rest}', 'case Succ{rest}: Duration{Succ{rest}}', 'laws/dns-udp-timeout.positive_preserved'),
        ('udp-first-timeout-discarded', 'packages/runtime/src/dns-udp-timeout.bend',
         'case First{}: timeout', 'case First{}: 0', 'laws/dns-udp-timeout.first_server_undivided'),
        ('udp-two-server-budget-halved', 'packages/runtime/src/dns-udp-timeout.bend',
         'case SecondOfTwo{}: timeout', 'case SecondOfTwo{}: (timeout / 2 : U32)', 'proofs/dns-udp-timeout.two_checked'),
        ('udp-schedule-drops-later-rounds', 'packages/runtime/src/dns-udp-schedule.bend',
         'case Succ{later}: Cursor{later, servers, servers}',
         'case Succ{later}: Cursor{Zero{}, servers, servers}', 'laws/dns-udp-schedule.initial_sequence'),
        ('udp-schedule-skips-pending-servers', 'packages/runtime/src/dns-udp-schedule.bend',
         'case Cursor{later, servers, first <> rest}: Try{first, Cursor{later, servers, rest}}',
         'case Cursor{later, servers, first <> rest}: Try{first, Cursor{later, servers, Nil{}}}', 'laws/dns-udp-schedule.next_sequence'),
        ('udp-schedule-never-restarts', 'packages/runtime/src/dns-udp-schedule.bend',
         'case Succ{later} first <> rest: Try{first, Cursor{later, servers, rest}}',
         'case Succ{later} first <> rest: Exhausted{}', 'laws/dns-udp-schedule.next_sequence'),
        ('abort-outcome-discards-reason', 'packages/runtime/src/abort-outcome.bend',
         'case Some{why} _: Aborted{why}', 'case Some{why} _: Cancelled{}', 'laws/abort-outcome.retained_abort_wins'),
        ('abort-outcome-discards-completion', 'packages/runtime/src/abort-outcome.bend',
         'case None{} Some{result}: Completed{result}', 'case None{} Some{result}: Cancelled{}', 'laws/abort-outcome.completion_preserved'),
        ('resolver-search-accepts-diagnostics', 'packages/runtime/src/resolver-search.bend',
         'case Options.Report{_, diagnostics}: Fail{diagnostics}',
         'case Options.Report{options, _}: Done{prepare(options, domains)}', 'laws/resolver-search.rejects_diagnostics'),
        ('resolver-plan-discards-request-policy', 'packages/runtime/src/resolver-search.bend',
         'Plan{requestOptions(configuration), start(', 'Plan{Query.defaults(), start(', 'laws/resolver-search.preserves_request_policy'),
        ('resolver-plan-discards-dot-count', 'packages/runtime/src/resolver-search.bend',
         'Plan{requestOptions(configuration), start(configuration, base, dots, absolute)}',
         'Plan{requestOptions(configuration), start(configuration, base, 0, absolute)}', 'laws/resolver-search.preserves_search_policy'),
        ('resolver-request-discards-settings', 'packages/runtime/src/resolver-request.bend',
         'Prepared{options, selected(', 'Prepared{Resolver.defaults(), selected(', 'laws/resolver-request.preserves_settings'),
        ('resolver-request-accepts-diagnostics', 'packages/runtime/src/resolver-request.bend',
         'case Resolver.Report{_, issues}: Fail{issues}',
         'case Resolver.Report{_, issues}: Done{prepare(Resolver.defaults())}', 'laws/resolver-request.rejects_diagnostics'),
        ('dns-query-discards-extension', 'packages/runtime/src/dns-query.bend',
         'case Options{flags, extension}: Request{id, flags, question, extension}',
         'case Options{flags, extension}: Request{id, flags, question, None{}}', 'laws/dns-query.creation_preserves_intent'),
        ('tool-start-does-not-register-pending', 'packages/agent/src/agent-state.bend',
         'streaming, partial, Set.insert(pending, id), error}',
         'streaming, partial, pending, error}', 'laws/agent-events.tool_start_membership'),
        ('tool-end-retains-pending', 'packages/agent/src/agent-state.bend',
         'streaming, partial, Set.remove(pending, id), error}',
         'streaming, partial, pending, error}', 'laws/agent-events.tool_end_membership'),
        ('finish-run-remains-streaming', 'packages/agent/src/agent-state.bend',
         'T.AgentState{model, thinking, tools, messages, False{}, None{}, Set.empty(), error}',
         'T.AgentState{model, thinking, tools, messages, True{}, None{}, Set.empty(), error}', 'laws/agent-events.finish_idle'),
        ('finish-run-discards-error', 'packages/agent/src/agent-state.bend',
         'T.AgentState{model, thinking, tools, messages, False{}, None{}, Set.empty(), error}',
         'T.AgentState{model, thinking, tools, messages, False{}, None{}, Set.empty(), None{}}', 'laws/agent-events.finish_idle'),
        ('message-start-discards-history', 'packages/agent/src/agent-state.bend',
         'T.MessageStart{message}: T.AgentState{model, thinking, tools, messages, streaming, Some{message}, pending, error}',
         'T.MessageStart{message}: T.AgentState{model, thinking, tools, Nil{}, streaming, Some{message}, pending, error}', 'laws/agent-events.message_start'),
        ('message-end-does-not-append', 'packages/agent/src/agent-state.bend',
         'tools, List.append(&2, T.AgentMessage<Parameters, Arguments, DiagnosticDetails, Details, Custom>, messages, message <> Nil{}), streaming, None{}, pending, error}',
         'tools, messages, streaming, None{}, pending, error}', 'laws/agent-events.message_end'),
        ('agent-end-declares-idle', 'packages/agent/src/agent-state.bend',
         'T.AgentEnd{_}: T.AgentState{model, thinking, tools, messages, streaming, None{}, pending, error}',
         'T.AgentEnd{_}: T.AgentState{model, thinking, tools, messages, False{}, None{}, pending, error}', 'laws/agent-events.events_preserve_configuration'),
        ('agent-end-retains-partial-message', 'packages/agent/src/agent-state.bend',
         'T.AgentEnd{_}: T.AgentState{model, thinking, tools, messages, streaming, None{}, pending, error}',
         'T.AgentEnd{_}: T.AgentState{model, thinking, tools, messages, streaming, partial, pending, error}', 'laws/agent-events.agent_end'),
        ('enqueue-changes-agent-state', 'packages/agent/src/agent-runtime.bend',
         '(OwnedState{state, Q.enqueue(T.AgentMessage<P, A, G, D, C>, queues, kind, message)}, Unit{})',
         '(OwnedState{State.beginRun(P, A, G, D, C, V, S, E, J, state), Q.enqueue(T.AgentMessage<P, A, G, D, C>, queues, kind, message)}, Unit{})', 'laws/agent-owner.enqueue_preserves_state'),
        ('queue-update-changes-agent-state', 'packages/agent/src/agent-runtime.bend',
         '(OwnedState{state, update(queues)}, Unit{})',
         '(OwnedState{State.beginRun(P, A, G, D, C, V, S, E, J, state), update(queues)}, Unit{})', 'laws/agent-owner.queue_update_preserves_state'),
        ('drain-changes-agent-state', 'packages/agent/src/agent-runtime.bend',
         '(OwnedState{state, queues}, messages)',
         '(OwnedState{State.beginRun(P, A, G, D, C, V, S, E, J, state), queues}, messages)', 'proofs/agent-owner.drained_preserves_state'),
        ('replace-messages-discards-input', 'packages/agent/src/agent-state.bend',
         'ReplaceMessages{messages}: T.AgentState{model, thinking, tools, messages, streaming, current, pending, error}',
         'ReplaceMessages{messages}: T.AgentState{model, thinking, tools, Nil{}, streaming, current, pending, error}', 'laws/agent-owner.replace_messages'),
        ('model-change-stops-run', 'packages/agent/src/agent-state.bend',
         'SetModel{model}: T.AgentState{model, thinking, tools, messages, streaming, current, pending, error}',
         'SetModel{model}: T.AgentState{model, thinking, tools, messages, False{}, current, pending, error}', 'laws/agent-owner.changes_preserve_run_state'),
        ('flush-drops-pending-lines', 'packages/runtime/src/line-decoder.bend',
         'case LineDecoder{pending}: consume(LineDecoder{pending}, 10)',
         'case LineDecoder{pending}: Decoded{create(), Nil{}}', 'laws/line-decoder.flush_result'),
        ('flush-drops-line-before-carriage-return', 'packages/runtime/src/line-decoder.bend',
         'case Nil{}: Decoded{create(), line(before) <> Nil{}}',
         'case Nil{}: Decoded{create(), Nil{}}', 'laws/line-decoder.flush_result'),
        ('sse-empty-block-retains-diagnostics', 'packages/runtime/src/sse-decoder.bend',
         'case SSEDecoder{None{}, Nil{}, _}: Decoded{create(), None{}}',
         'case SSEDecoder{None{}, Nil{}, raw}: Decoded{SSEDecoder{None{}, Nil{}, raw}, None{}}', 'laws/sse-decoder.blank_clears_buffers'),
        ('sse-empty-block-emits-event', 'packages/runtime/src/sse-decoder.bend',
         'case SSEDecoder{None{}, Nil{}, _}: Decoded{create(), None{}}',
         'case SSEDecoder{None{}, Nil{}, _}: Decoded{create(), Some{ServerSentEvent{None{}, "", Nil{}}}}', 'laws/sse-decoder.repeated_blank'),
        ('line-chunk-resets-pending-state', 'packages/runtime/src/line-decoder.bend',
         'collect(bytes, Decoded{decoder, Nil{}}, Nil{})',
         'collect(bytes, Decoded{create(), Nil{}}, Nil{})', 'laws/line-decoder.empty_chunk'),
        ('line-collector-drops-emitted-lines', 'packages/runtime/src/line-decoder.bend',
         'case head <> tail: prepend(tail, head <> reversed)',
         'case head <> tail: prepend(tail, reversed)', 'proofs/line-decoder.prepend_reverse'),
        ('ordered-map-drops-replaced-key', 'packages/runtime/src/ordered-map.bend',
         'String.eq(name, key), R.Property{key, value} <> rest',
         'String.eq(name, key), rest', 'proofs/ordered-map.put_equivalent'),
        ('ordered-map-removal-is-no-op', 'packages/runtime/src/ordered-map.bend',
         'OrderedMap{R.removeProperties(V, properties, key)}',
         'OrderedMap{properties}', 'laws/ordered-map.remove'),
        ('ordered-map-lookup-always-missing', 'packages/runtime/src/ordered-map.bend',
         'case OrderedMap{properties}: R.getProperties(V, properties, key)',
         'case OrderedMap{properties}: None{}', 'laws/ordered-map.lookup'),
        ('replacement-duplicates-old-entry', 'packages/runtime/src/record.bend',
         'String.eq(key, name), Property{key, value} <> rest',
         'String.eq(key, name), Property{key, value} <> (Property{name, old} <> rest)', 'proofs/record.set_properties_lookup'),
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
