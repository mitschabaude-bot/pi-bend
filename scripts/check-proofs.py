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
    # The full root includes the previous four concrete annotations plus the
    # two response loops and SSE loop. Preparation also imports strict schema
    # traversal and Responses processing; its concrete specializations bring
    # the root summary to twelve. The body-source module alone reports
    # three. The provider HTTP adapter also imports the buffered-body loop.
    # The concrete native callback reaches six existing transport loops; the
    # full root now reports nineteen. These are not new unsafe definitions.
    # Configured acquisition instantiates two additional existing unsafe terms;
    # the exact source declaration set remains nineteen and is audited below.
    # The shared body reader additionally reaches the existing provider SSE loop:
    # twenty source declarations, twenty-two full-root instances; the isolated
    # generic reader/result modules report ten existing instances.
    # None supplies proof evidence; exact declarations are audited below.
    summaries = {'All terms check.', 'All terms check, with 1 unsafe annotation.',
                 'All terms check, with 2 unsafe annotations.', 'All terms check, with 3 unsafe annotations.', 'All terms check, with 4 unsafe annotations.',
                 'All terms check, with 6 unsafe annotations.', 'All terms check, with 7 unsafe annotations.', 'All terms check, with 8 unsafe annotations.', 'All terms check, with 12 unsafe annotations.', 'All terms check, with 13 unsafe annotations.', 'All terms check, with 14 unsafe annotations.', 'All terms check, with 19 unsafe annotations.', 'All terms check, with 21 unsafe annotations.', 'All terms check, with 22 unsafe annotations.', 'All terms check, with 10 unsafe annotations.'}
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
    ('packages/ai/src/api/strict-json-schema.bend', 'run'),
    ('packages/ai/src/api/strict-json-schema.bend', 'nullAllowed'),
    ('packages/ai/src/api/openai-responses-stream.bend', 'loop'),
    ('packages/ai/src/api/openai-sse-reader.bend', 'drive'),
    ('packages/runtime/src/callback.bend', 'factory'),
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
}, unsafe_declarations

source_hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES + ['scripts/check-proofs.py']}

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
        proof = check(directory, 'proofs/fifo.bend')
        rejected(proof, f'laws/fifo.{law}')
        results['mutations'].append({'name': label, 'module_check': typed, 'proof_check': proof})
    module.write_text(original)
    extra_mutations = [
        ('body-reader-loses-secondary-disposal-error', 'packages/ai/src/api/openai-body-responses-reader.bend', 'case Fail{first} Fail{second}: Fail{BothFailures{first, second}}', 'case Fail{first} Fail{second}: Fail{ReaderFailure{first}}', 'laws/openai-body-responses-reader.simultaneous_disposal_failures_are_retained_in_order'),
        ('processed-result-drops-cleanup', 'packages/ai/src/api/openai-responses-process-result.bend', 'cleanup(Transport, E, disposalError, disposal)', 'None{}', 'laws/openai-responses-process-result.simultaneous_failures_retain_message_and_both_causes'),
        ('processed-result-drops-primary', 'packages/ai/src/api/openai-responses-process-result.bend', 'failure(E, processingError, error)', 'None{}', 'laws/openai-responses-process-result.simultaneous_failures_retain_message_and_both_causes'),
        ('retry-options-drops-limit', 'packages/ai/src/utils/provider-retry-options.bend', 'Done{Retry.ProviderRetryOptions{retries, limit, signal}}', 'Done{Retry.ProviderRetryOptions{retries, None{}, signal}}', 'laws/provider-retry-options.accepted_options_preserve_all_fields'),
        ('retry-options-allows-invalid-limit', 'packages/ai/src/utils/provider-retry-options.bend', 'case False{}: Fail{InvalidDelayLimit{value}}', 'case False{}: Done{Some{value}}', 'laws/provider-retry-options.invalid_delay_retains_original_value'),
        ('retry-config-drops-signal', 'packages/ai/src/utils/provider-retry-config.bend', 'Options.resolve(Reason, retries, limit, signal)', 'Options.resolve(Reason, retries, limit, None{})', 'laws/provider-retry-config.request_uses_only_retry_settings'),
        ('invalid-sleep-becomes-abort', 'packages/ai/src/utils/provider-retry.bend', 'case Fail{InvalidSleepDuration{error}}: Finished{Fail{SleepRejected{error}}}', 'case Fail{InvalidSleepDuration{error}}: Finished{Fail{RequestAborted{}}}', 'laws/provider-retry.invalid_sleep_retains_cause'),
        ('invalid-sleep-allocates-timer', 'packages/ai/src/utils/provider-retry-sleep.bend', 'case Fail{error}: IO.pure(Result<&2, &2, R.SleepError, Unit>, Fail{R.InvalidSleepDuration{error}})', 'case Fail{error}: valid(Reason, 1, signal)', 'laws/provider-retry-sleep.invalid_duration_has_no_timer_effect'),
        ('retry-map-discards-status', 'packages/ai/src/utils/provider-retry-map.bend', 'Retry.Provider{Retry.ProviderError{embed(cause), message, status, hint, milliseconds, seconds}}', 'Retry.Provider{Retry.ProviderError{embed(cause), message, None{}, hint, milliseconds, seconds}}', 'laws/provider-retry-map.failure_identity'),
        ('retry-map-changes-terminal-category', 'packages/ai/src/utils/provider-retry-map.bend', 'case Retry.Other{cause}: Retry.Other{embed(cause)}', 'case Retry.Other{cause}: Retry.Provider{Retry.ProviderError{embed(cause), "", None{}, None{}, None{}, None{}}}', 'laws/provider-retry-map.failure_identity'),
        ('responses-acquire-retries-invalid-envelope', 'packages/ai/src/api/openai-responses-acquire.bend', 'Fail{Retry.Other{encodeError(cause)}}', 'Fail{Retry.Provider{Retry.ProviderError{encodeError(cause), "invalid", None{}, None{}, None{}, None{}}}}', 'laws/openai-responses-acquire.invalid_envelope_has_no_transport_effect'),
        ('responses-acquire-drops-valid-envelope', 'packages/ai/src/api/openai-responses-acquire.bend', 'case Done{wire}: C.call(Envelope.Request, Outcome(E, State), request, wire)', 'case Done{wire}: IO.pure(Outcome(E, State), Fail{Retry.Other{encodeError(Envelope.NonFinitePayload{})}})', 'laws/openai-responses-acquire.valid_envelope_transfers_unchanged'),
        ('native-retry-ignores-plan-rejection', 'packages/ai/src/api/openai-responses-native-error.bend', 'case Native.Rejected{_}: Attempt.NonRetryable{}', 'case Native.Rejected{_}: connection()', 'laws/openai-responses-native-error.rejected_transport_plan_is_terminal'),
        ('native-retry-overwrites-invalid-dns-setup', 'packages/ai/src/api/openai-responses-native-error.bend', 'case DNS.Report{Fail{Search.Halted{DNS.SetupFailed{cause}}}, _}: setup(Reason, cause)', 'case DNS.Report{Fail{Search.Halted{DNS.SetupFailed{cause}}}, why}: dnsDeadline(Reason, setup(Reason, cause), why)', 'laws/openai-responses-native-error.invalid_dns_encoding_precedes_late_deadline'),
        ('native-retry-hides-header-cleanup', 'packages/ai/src/api/openai-responses-native-error.bend', 'case Progress.FailureWithCleanup{_, _}: Attempt.NonRetryable{}', 'case Progress.FailureWithCleanup{primary, _}: headerPrimary(Reason, primary)', 'laws/openai-responses-native-error.header_cleanup_failure_cannot_be_hidden_by_primary_classification'),
        ('responses-attempt-retries-configuration', 'packages/ai/src/api/openai-responses-attempt.bend', 'case NonRetryable{}: Retry.Other{original}\n    case other:', 'case NonRetryable{}: connection(E, original, "configuration")\n    case other:', 'laws/openai-responses-attempt.configuration_failure_is_terminal'),
        ('responses-attempt-drops-http-message', 'packages/ai/src/api/openai-responses-attempt.bend', 'HTTPFailure{HTTPError.APIError{metadata, value, message}}, message, metadata)', 'HTTPFailure{HTTPError.APIError{metadata, value, message}}, "", metadata)', 'laws/openai-responses-attempt.http_failure_retains_diagnostic_and_policy'),
        ('native-fetch-drops-header-attempts', 'packages/ai/src/api/openai-responses-cleartext-fetch.bend', 'Fail{HeaderFailure{resolution, attempts, cause}}', 'Fail{HeaderFailure{resolution, Nil{}, cause}}', 'laws/openai-responses-cleartext-fetch.header_failure_retains_trace_and_cause'),
        ('native-fetch-replaces-unresolved-cause', 'packages/ai/src/api/openai-responses-cleartext-fetch.bend', 'Fail{Unresolved{resolution}}', 'Fail{Rejected{Plan.TLSRequired{}}}', 'laws/openai-responses-cleartext-fetch.unresolved_request_preserves_resolution'),
        ('timer-conversion-skips-roundtrip', 'packages/runtime/src/timer-milliseconds.bend', 'checked(value, word, F.compare(value, F.fromU32(word)))', 'checked(value, word, Some{EQ{}})', 'laws/timer-milliseconds.accepted_durations_round_trip'),
        ('timer-conversion-rejects-exact', 'packages/runtime/src/timer-milliseconds.bend', 'case Some{EQ{}}: Done{milliseconds}', 'case Some{EQ{}}: Fail{Unrepresentable{value}}', 'laws/timer-milliseconds.exact_conversion_retains_duration'),
        ('timer-conversion-rounds-mismatch', 'packages/runtime/src/timer-milliseconds.bend', 'case _: Fail{Unrepresentable{value}}', 'case _: Done{milliseconds}', 'laws/timer-milliseconds.smaller_conversion_is_rejected'),
        ('responses-fetch-drops-body', 'packages/ai/src/api/openai-responses-fetch.bend', 'Input{url, String.to_upper(method), headers, body, signal}', 'Input{url, String.to_upper(method), headers, "", signal}', 'laws/openai-responses-fetch.fetch_input_retains_request'),
        ('responses-fetch-ignores-custom', 'packages/ai/src/api/openai-responses-fetch.bend', 'case Some{fetch}: fetch', 'case Some{fetch}: native', 'laws/openai-responses-fetch.custom_fetch_takes_precedence'),
        ('finite-validator-accepts-infinity', 'packages/ai/src/utils/json-finite.bend', 'case _: False{}', 'case _: True{}', 'laws/json-finite.infinities_are_rejected'),
        ('finite-validator-skips-number', 'packages/ai/src/utils/json-finite.bend', 'case T.JsonNumber{value}: number(F.decode(value))', 'case T.JsonNumber{value}: True{}', 'laws/json-finite.invalid_numeric_leaf_is_rejected'),
        ('finite-validator-skips-array-head', 'packages/ai/src/utils/json-finite.bend', 'case T.JsonArray{head <> rest}: Bool.pick(Unit -> Bool, valid(head), unused => valid(T.JsonArray{rest}), unused => False{})(Unit{})', 'case T.JsonArray{head <> rest}: valid(T.JsonArray{rest})', 'laws/json-finite.array_checks_head_and_tail'),
        ('envelope-accepts-invalid-payload', 'packages/ai/src/api/openai-responses-envelope.bend', 'case False{}: Fail{NonFinitePayload{}}', 'case False{}: Done{"null"}', 'laws/openai-responses-envelope.invalid_payload_has_no_body'),
        ('envelope-drops-encoded-body', 'packages/ai/src/api/openai-responses-envelope.bend', 'case Some{text}: Done{text}', 'case Some{text}: Done{""}', 'laws/openai-responses-envelope.encoding_retains_text'),
        ('envelope-changes-custom-fetch-method', 'packages/ai/src/api/openai-responses-envelope.bend', 'Request{url, "post", fields, body, timeout}', 'Request{url, "POST", fields, body, timeout}', 'laws/openai-responses-envelope.completed_request_retains_fields'),
        ('envelope-invents-timeout-header', 'packages/ai/src/api/openai-responses-envelope.bend', 'case None{}: Done{None{}}', 'case None{}: Done{Some{"600"}}', 'laws/openai-responses-envelope.absent_timeout_has_no_header'),
        ('strict-form-loses-value', 'packages/runtime/src/url-form-strict.bend', 'case Some{name} Some{value}: Done{Form.Entry{name, value}}', 'case Some{name} Some{value}: Done{Form.Entry{name, ""}}', 'laws/url-form-strict.decoded_values_are_preserved'),
        ('strict-form-name-error-loses-position', 'packages/runtime/src/url-form-strict.bend', 'case None{} _: Fail{InvalidName{field}}', 'case None{} _: Fail{InvalidName{Zero{}}}', 'laws/url-form-strict.invalid_name_precedes_value'),
        ('strict-form-value-error-wrong-component', 'packages/runtime/src/url-form-strict.bend', 'case Some{_} None{}: Fail{InvalidValue{field}}', 'case Some{_} None{}: Fail{InvalidName{field}}', 'laws/url-form-strict.invalid_value_retains_position'),
        ('strict-form-prepend-drops-tuple', 'packages/runtime/src/url-form-strict.bend', 'case Done{tuple}: Done{tuple <> reversed}', 'case Done{tuple}: Done{reversed}', 'laws/url-form-strict.prepend_retains_entry'),
        ('responses-url-drops-query-field', 'packages/ai/src/api/openai-responses-url.bend', 'case Form.Entry{name, value} <> rest: collect(rest, R.set(String, fields, name, value))', 'case Form.Entry{name, value} <> rest: collect(rest, fields)', 'laws/openai-responses-url.singleton_field_updates_dictionary'),
        ('responses-url-accepts-malformed-query', 'packages/ai/src/api/openai-responses-url.bend', 'case Fail{cause}: Fail{InvalidQuery{cause}}', 'case Fail{cause}: Done{url}', 'laws/openai-responses-url.malformed_query_preserves_cause'),
        ('responses-url-loses-parse-cause', 'packages/ai/src/api/openai-responses-url.bend', 'case Fail{cause}: Fail{InvalidURL{cause}}', 'case Fail{cause}: Fail{InvalidURL{Absolute.MissingScheme{}}}', 'laws/openai-responses-url.malformed_url_preserves_cause'),
        ('query-names-drop-head', 'packages/runtime/src/url-search-params.bend', 'case Form.Entry{name, _} <> rest: name <> names(rest)', 'case Form.Entry{name, _} <> rest: names(rest)', 'laws/url-search-params.names_retain_head'),
        ('query-values-drop-head', 'packages/runtime/src/url-search-params.bend', 'case Form.Entry{_, value} <> rest: value <> contents(rest)', 'case Form.Entry{_, value} <> rest: contents(rest)', 'laws/url-search-params.values_retain_head'),
        ('query-append-drops-prefix', 'packages/runtime/src/url-search-params.bend', 'URLSearchParams{List.append(&2, Form.Entry, entries(params), Form.normalize(Form.Entry{name, value}) <> Nil{})}', 'URLSearchParams{Form.normalize(Form.Entry{name, value}) <> Nil{}}', 'laws/url-search-params.append_preserves_prefix'),
        ('query-delete-retains-matches', 'packages/runtime/src/url-search-params.bend', 'Bool.pick(List<&2, Form.Entry>, matches(entry, name, value), remaining, entry <> remaining)', 'entry <> remaining', 'laws/url-search-params.remove_matching_head'),
        ('header-layers-ignore-configuration', 'packages/ai/src/utils/provider-header-state.bend', 'case head <> rest: layers(rest, apply(head, result))', 'case head <> rest: layers(rest, result)', 'laws/provider-header-state.singleton_layer_applies_configuration'),
        ('header-entries-ignore-field', 'packages/ai/src/utils/provider-header-state.bend', 'case R.Property{name, value} <> rest Done{state}: entries(rest, field(state, name, value))', 'case R.Property{name, value} <> rest Done{state}: entries(rest, Done{state})', 'laws/provider-header-state.singleton_entry_applies_field'),
        ('header-state-replaces-values-with-removal', 'packages/ai/src/utils/provider-header-state.bend', 'case State{fields}: State{R.set(T.Nullable<String>, fields, name, value)}', 'case State{fields}: State{R.set(T.Nullable<String>, fields, name, T.NullValue{})}', 'laws/provider-header-state.latest_setting_is_observable'),
        ('header-removal-emits-empty-wire-field', 'packages/ai/src/utils/provider-header-state.bend', 'case R.Property{_, T.NullValue{}} <> rest: materialize(rest)', 'case R.Property{name, T.NullValue{}} <> rest: R.Property{name, "" <> Nil{}} <> materialize(rest)', 'laws/provider-header-state.removal_has_no_wire_field'),
        ('header-assignment-drops-wire-value', 'packages/ai/src/utils/provider-header-state.bend', 'case R.Property{name, T.PresentValue{text}} <> rest: R.Property{name, text <> Nil{}} <> materialize(rest)', 'case R.Property{name, T.PresentValue{text}} <> rest: materialize(rest)', 'laws/provider-header-state.assignment_retains_wire_value'),
        ('header-entries-swallow-error', 'packages/ai/src/utils/provider-header-state.bend', 'case _ Fail{cause}: Fail{cause}', 'case _ Fail{cause}: Done{empty()}', 'laws/provider-header-state.entries_preserve_first_error'),
        ('openai-header-authentication-failure-is-success', 'packages/ai/src/api/openai-request-headers.bend', 'case False{}: Fail{MissingAuthentication{}}', 'case False{}: Done{State.headers(state)}', 'laws/openai-request-headers.failed_authentication_has_no_headers'),
        ('openai-header-removal-is-not-an-override', 'packages/ai/src/api/openai-request-headers.bend', 'State.nonempty(value) || State.removed(value)', 'State.nonempty(value)', 'laws/openai-request-headers.removal_allows_authentication_override'),
        ('openai-header-timeout-ignores-explicit-value', 'packages/ai/src/api/openai-request-headers.bend', 'case Some{milliseconds}: milliseconds', 'case Some{milliseconds}: F.fromU32(600000)', 'laws/openai-request-headers.explicit_timeout_is_retained'),
        ('openai-header-timeout-accepts-noninteger', 'packages/ai/src/api/openai-request-headers.bend', 'case False{}: Fail{TimeoutNotInteger{value}}', 'case False{}: Done{value}', 'laws/openai-request-headers.noninteger_timeout_is_rejected'),
        ('openai-header-error-loses-cause', 'packages/ai/src/api/openai-request-headers.bend', 'case Fail{cause}: Fail{HeaderFailure{cause}}', 'case Fail{cause}: Fail{HeaderFailure{H.InvalidName{}}}', 'laws/openai-request-headers.header_failure_preserves_cause'),
        ('responses-params-omits-explicit-null', 'packages/ai/src/api/openai-responses-params.bend', 'case Some{T.NullValue{}}: R.set(T.JsonValue, fields, key, T.JsonNull{})', 'case Some{T.NullValue{}}: fields', 'laws/openai-responses-prepare.explicit_null_replaces_field'),
        ('responses-preparation-rejects-valid-api', 'packages/ai/src/api/openai-responses-prepare.bend', 'case T.OpenAIResponsesApi{}: Done{ModelSettings{provider, baseUrl, headers, Policy.getCompat(provider, baseUrl, compat)}}', 'case T.OpenAIResponsesApi{}: Fail{UnsupportedApi{T.OpenAIResponsesApi{}}}', 'laws/openai-responses-prepare.responses_model_preserves_configuration'),
        ('responses-preparation-accepts-wrong-api', 'packages/ai/src/api/openai-responses-prepare.bend', 'case other: Fail{UnsupportedApi{other}}', 'case other: Done{ModelSettings{provider, baseUrl, headers, Policy.getCompat(provider, baseUrl, None{})}}', 'laws/openai-responses-prepare.custom_api_is_rejected'),
        ('responses-extension-drops-fetch', 'packages/ai/src/api/openai-responses-options.bend', '}: OpenAIResponsesOptions{signal, telemetryContext, apiKey, fetch, env', '}: OpenAIResponsesOptions{signal, telemetryContext, apiKey, None{}, env', 'laws/openai-responses-options.extension_preserves_base'),
        ('responses-extension-drops-summary', 'packages/ai/src/api/openai-responses-options.bend', 'metadata, reasoningEffort, reasoningSummary, serviceTier, toolChoice}\n', 'metadata, reasoningEffort, None{}, serviceTier, toolChoice}\n', 'laws/openai-responses-options.extension_preserves_provider_settings'),
        ('responses-projection-drops-telemetry', 'packages/ai/src/api/openai-responses-options.bend', '}: T.StreamOptions{signal, telemetryContext, apiKey', '}: T.StreamOptions{signal, None{}, apiKey', 'laws/openai-responses-options.extension_preserves_base'),
        ('responses-preparation-discards-payload-cause', 'packages/ai/src/api/openai-responses-prepare.bend', 'case Fail{cause}: Fail{PayloadFailure{cause}}', 'case Fail{cause}: Fail{UnsupportedApi{T.OpenAIResponsesApi{}}}', 'laws/openai-responses-prepare.failed_payload_preserves_cause'),
        ('responses-preparation-drops-headers', 'packages/ai/src/api/openai-responses-prepare.bend', 'Done{Prepared{apiKey, baseUrl, headers, value, compat, grammarResult, retention}}', 'Done{Prepared{apiKey, baseUrl, R.new(T.Nullable<String>), value, compat, grammarResult, retention}}', 'laws/openai-responses-prepare.successful_preparation_preserves_all_fields'),
        ('responses-credential-failure-performs-effects', 'packages/ai/src/api/openai-responses-prepare.bend', 'case _ Fail{cause}: IO.pure(Result<&2, &2, Error, Prepared>, Fail{CredentialFailure{cause}})', 'case _ Fail{cause}: IO.bind(Unit, Result<&2, &2, Error, Prepared>, IO.print("unexpected preparation effect"), ignored => IO.pure(Result<&2, &2, Error, Prepared>, Fail{CredentialFailure{cause}}))', 'laws/openai-responses-prepare.credential_failure_has_no_effects'),
        ('responses-grammar-failure-performs-effects', 'packages/ai/src/api/openai-responses-prepare.bend', 'case _ Fail{cause}: IO.pure(Result<&2, &2, Error, Prepared>, Fail{GrammarFailure{cause}})', 'case _ Fail{cause}: IO.bind(Unit, Result<&2, &2, Error, Prepared>, IO.print("unexpected preparation effect"), ignored => IO.pure(Result<&2, &2, Error, Prepared>, Fail{GrammarFailure{cause}}))', 'laws/openai-responses-prepare.grammar_failure_has_no_effects'),
        ('session-omits-dependency-finalizer', 'packages/ai/src/api/openai-responses-session.bend',
         '    cleanup\n    return result', '    return result', 'laws/openai-responses-session.dependency_cleanup_precedes_unchanged_result'),
        ('session-drops-published-event', 'packages/ai/src/api/openai-responses-session.bend',
         'Events.push(T.AssistantMessageEvent<A, G>, T.AssistantMessage<A, G>, stream, event)',
         'IO.pure(Unit, Unit{})', 'laws/openai-responses-session.publication_preserves_event'),
        ('session-end-omits-final-result', 'packages/ai/src/api/openai-responses-session.bend',
         'Events.end(T.AssistantMessageEvent<A, G>, T.AssistantMessage<A, G>, stream, Some{output})',
         'Events.end(T.AssistantMessageEvent<A, G>, T.AssistantMessage<A, G>, stream, None{})', 'laws/openai-responses-session.end_supplies_final_snapshot'),
        ('session-leaks-publication-callback', 'packages/ai/src/api/openai-responses-session.bend',
         'C.dispose(T.AssistantMessageEvent<A, G>, Result<&2, &2, E, Unit>, sink)',
         'IO.pure(Unit, Unit{})', 'laws/openai-responses-session.callbacks_retire_before_run_result'),
        ('session-leaks-event-stream', 'packages/ai/src/api/openai-responses-session.bend',
         'Events.disposeAssistantMessageEventStream(A, G, stream)',
         'IO.pure(Unit, Unit{})', 'laws/openai-responses-session.finished_disposal_preserves_result'),
        ('session-completed-wait-mutates-stream', 'packages/ai/src/api/openai-responses-session.bend',
         'case Finished{stream, result}: IO.pure(Run<A, G, E> & Life.RunResult<A, G, E>, completed(A, G, E, stream, result))',
         'case Finished{+stream, result}: IO.bind(Unit, Run<A, G, E> & Life.RunResult<A, G, E>, Events.end(T.AssistantMessageEvent<A, G>, T.AssistantMessage<A, G>, stream, None{}), ignored => IO.pure(Run<A, G, E> & Life.RunResult<A, G, E>, completed(A, G, E, stream, result)))', 'laws/openai-responses-session.finished_wait_has_no_effects'),
        ('lifecycle-ignores-cancellation', 'packages/ai/src/api/openai-responses-lifecycle.bend',
         'case True{} _: Fail{RequestAborted{}}', 'case True{} _: Fail{MissingStopReason{}}', 'laws/openai-responses-lifecycle.cancellation_precedes_stop_reason'),
        ('lifecycle-drops-partial-content', 'packages/ai/src/api/openai-responses-lifecycle.bend',
         'T.AssistantMessage{content, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, stopReason(aborted)',
         'T.AssistantMessage{Nil{}, api, provider, model, responseModel, responseId, thinking, diagnostics, usage, stopReason(aborted)', 'laws/openai-responses-lifecycle.failure_preserves_unrelated_fields'),
        ('lifecycle-hides-processing-failure', 'packages/ai/src/api/openai-responses-lifecycle.bend',
         'case Some{cause} _: Some{ProcessingFailure{cause}}', 'case Some{cause} _: None{}', 'laws/openai-responses-lifecycle.primary_failure_precedes_cleanup'),
        ('lifecycle-hides-primary-on-delivery-failure', 'packages/ai/src/api/openai-responses-lifecycle.bend',
         'case Failed{reason, output, primary}: Failed{reason, output, primary}',
         'case Failed{reason, output, primary}: Successful{T.DoneStop{}, output}', 'laws/openai-responses-lifecycle.failed_delivery_retains_primary'),
        ('lifecycle-skips-stream-close', 'packages/ai/src/api/openai-responses-driver.bend',
         'C.call(T.AssistantMessage<A, G>, Unit, finish, Life.message(A, G, E, terminal))',
         'IO.pure(Unit, Unit{})', 'laws/openai-responses-lifecycle.close_precedes_run_result'),
        ('lifecycle-changes-done-reason', 'packages/ai/src/api/openai-responses-lifecycle.bend',
         'case Successful{reason, output}: T.StreamDone{reason, output}',
         'case Successful{reason, output}: T.StreamDone{T.DoneStop{}, output}', 'laws/openai-responses-lifecycle.successful_event_retains_message'),
        ('http-abort-classification-hides-combined', 'packages/runtime/src/http-abort-classification.bend',
         'case Progress.FailureWithCleanup{_, _}: False{}', 'case Progress.FailureWithCleanup{_, _}: True{}', 'laws/http-abort-classification.combined_failures_are_not_cancellation'),
        ('http-abort-classification-ignores-transport', 'packages/runtime/src/http-abort-classification.bend',
         'case Progress.TransportFailure{cause}: classify(cause)', 'case Progress.TransportFailure{cause}: False{}', 'laws/http-abort-classification.lone_transport_uses_classifier'),
        ('http-body-source-erases-bytes', 'packages/runtime/src/http-body-source.bend',
         'Done{Some{SSE.Bytes{bytes}}}', 'Done{Some{SSE.Bytes{Nil{}}}}', 'laws/http-body-source.bytes_are_not_decoded_or_changed'),
        ('http-body-source-eof-becomes-chunk', 'packages/runtime/src/http-body-source.bend',
         'case Done{None{}}: Done{None{}}', 'case Done{None{}}: Done{Some{SSE.EmptyChunk{}}}', 'laws/http-body-source.eof_is_not_an_empty_chunk'),
        ('http-response-progress-erases-chunk', 'packages/runtime/src/http-response-progress.bend',
         'Chunk{first <> rest}', 'Chunk{Nil{}}', 'laws/http-response-progress.nonempty_chunks_preserve_bytes'),
        ('http-response-progress-erases-trailers', 'packages/runtime/src/http-response-progress.bend',
         'Complete{fields}', 'Complete{Nil{}}', 'laws/http-response-progress.completion_retains_trailers'),
        ('http-response-progress-replaces-primary', 'packages/runtime/src/http-response-progress.bend',
         'Fail{FailureWithCleanup{error, cleanup}}', 'Fail{CleanupFailure{cleanup}}', 'laws/http-response-progress.dual_failure_retains_both'),
        ('http-response-metadata-erases-fields', 'packages/runtime/src/http-response-metadata.bend',
         'appendFields(fields, Headers.new()), exposeBody', 'Headers.new(), exposeBody', 'laws/http-response-metadata.received_headers_retained'),
        ('http-response-metadata-accepts-300', 'packages/runtime/src/http-response-metadata.bend',
         'U32.is_lt(code, 300)', 'U32.is_le(code, 300)', 'laws/http-response-metadata.success_classification'),
        ('http-response-metadata-erases-exposure', 'packages/runtime/src/http-response-metadata.bend',
         'case Metadata{_, _, expose}: expose', 'case Metadata{_, _, expose}: False{}', 'laws/http-response-metadata.exposure_retained'),
        ('http-exchange-plan-conflates-tls', 'packages/runtime/src/http-exchange-plan.bend',
         'case URL.Endpoint{URL.TLS{}, _, _, _, _} _: Rejected{TLSRequired{}}',
         'case URL.Endpoint{URL.TLS{}, _, _, _, _} _: Rejected{InvalidReadSize{}}', 'laws/http-exchange-plan.tls_cannot_start_cleartext'),
        ('http-exchange-plan-allows-zero-read', 'packages/runtime/src/http-exchange-plan.bend',
         'case URL.Endpoint{URL.Plaintext{}, _, _, _, _} 0: Rejected{InvalidReadSize{}}',
         'case URL.Endpoint{URL.Plaintext{}, host, port, _, _} 0: Start{host, port, request, 0}', 'laws/http-exchange-plan.zero_read_size_cannot_start'),
        ('connection-plan-calls-unavailable-connector', 'packages/runtime/src/connection-plan.bend',
         'case Candidates.NoAddresses{resolution}: IO.pure(Report<Resolution, Reason, Value>, Unresolved{resolution})',
         'case Candidates.NoAddresses{resolution}:\n      do IO<Report<Resolution, Reason, Value>>:\n        connection : Driver.Report<Reason, Value> <- connect(context, Nil{})\n        return Attempted{resolution, connection}',
         'laws/connection-plan.unavailable_does_not_connect'),
        ('connection-progress-loses-parent-abort', 'packages/runtime/src/connection-progress.bend',
         'case _ Some{reason}: Stop{Aborted{reason}}', 'case _ Some{reason}: Advance{}', 'laws/connection-progress.parent_abort_wins'),
        ('connection-progress-retries-abort', 'packages/runtime/src/connection-progress.bend',
         'case Fail{Attempt.Aborted{reason}} None{}: Stop{Aborted{reason}}', 'case Fail{Attempt.Aborted{reason}} None{}: Advance{}', 'laws/connection-progress.reported_abort_stops'),
        ('connection-progress-times-final', 'packages/runtime/src/connection-progress.bend',
         'case Nil{}: Final{}', 'case Nil{}: NonFinal{}', 'laws/connection-progress.last_attempt_untimed'),
        ('connection-attempt-erases-errno', 'packages/runtime/src/connection-attempt-result.bend',
         'case Connect.SocketError{code, message}: SocketFailure{code, message}\n    case Connect.Aborted{Abort.Supplied{Deadline.Expired{}}}', 'case Connect.SocketError{code, message}: SocketFailure{0, message}\n    case Connect.Aborted{Abort.Supplied{Deadline.Expired{}}}', 'laws/connection-attempt-result.timed_socket_failure_retained'),
        ('connection-attempt-conflates-expiry', 'packages/runtime/src/connection-attempt-result.bend',
         'case Connect.Aborted{Abort.Supplied{Deadline.Expired{}}}: TimedOut{}', 'case Connect.Aborted{Abort.Supplied{Deadline.Expired{}}}: UnexpectedDefaultAbort{}', 'laws/connection-attempt-result.expiry_distinguished'),
        ('connection-attempt-erases-parent-reason', 'packages/runtime/src/connection-attempt-result.bend',
         'case Connect.Aborted{Abort.Supplied{Deadline.ParentAbort{reason}}}: Aborted{reason}', 'case Connect.Aborted{Abort.Supplied{Deadline.ParentAbort{reason}}}: Aborted{Abort.DefaultAbort{}}', 'laws/connection-attempt-result.timed_parent_reason_retained'),
        ('interleave-swaps-leading-pair', 'packages/runtime/src/list-interleave.bend',
         'a <> b <> interleave(A, xs, ys)', 'b <> a <> interleave(A, xs, ys)', 'laws/list-interleave.leading_pair'),
        ('interleave-drops-right-tail', 'packages/runtime/src/list-interleave.bend',
         'case Nil{} other: other', 'case Nil{} other: Nil{}', 'laws/list-interleave.left_empty'),
        ('connection-addresses-erases-hosts', 'packages/runtime/src/connection-addresses.bend',
         'case first <> rest: host(first) <> hosts(rest)', 'case first <> rest: Nil{}', 'laws/connection-addresses.hosts_count'),
        ('connection-addresses-erases-answers', 'packages/runtime/src/connection-addresses.bend',
         'case first <> rest: answer(first) <> answers(rest)', 'case first <> rest: Nil{}', 'laws/connection-addresses.answers_count'),
        ('connection-addresses-loses-ordered-tail', 'packages/runtime/src/connection-addresses.bend',
         'Addresses{report, Ordered{first, rest}}', 'Addresses{report, Ordered{first, Nil{}}}', 'laws/connection-addresses.ordered_retains_report_and_occurrences'),
        ('connection-addresses-loses-sibling', 'packages/runtime/src/connection-addresses.bend',
         'Paired{first <> rest, other}', 'Paired{first <> rest, Nil{}}', 'laws/connection-addresses.paired_retains_both_groups'),
        ('connection-addresses-invents-scope', 'packages/runtime/src/connection-addresses.bend',
         'case DNS.V6{value, _}: Connect.V6{value, 0}', 'case DNS.V6{value, _}: Connect.V6{value, 1}', 'laws/connection-addresses.ipv6_answer_address_retained'),
        ('http-host-loses-numeric-address', 'packages/runtime/src/http-host-route.bend',
         'case Host.IPv4{address}: Numeric{Connect.V4{address}}', 'case Host.IPv4{address}: Invalid{}', 'laws/http-host-route.ipv4_bypasses_lookup'),
        ('http-host-discards-domain', 'packages/runtime/src/http-host-route.bend',
         'case Host.Domain{name}: Lookup{name}', 'case Host.Domain{name}: Lookup{""}', 'laws/http-host-route.domain_spelling_retained'),
        ('http-host-accepts-empty-domain', 'packages/runtime/src/http-host-route.bend',
         'case Host.Domain{SNil{}}: Invalid{}', 'case Host.Domain{SNil{}}: Lookup{""}', 'laws/http-host-route.empty_domain_rejected'),
        ('numeric-scope-defaults-failure', 'packages/runtime/src/numeric-scope.bend',
         'case Fail{error}: Fail{InvalidScope{error}}', 'case Fail{error}: Done{Connect.V6{address, 0}}', 'laws/numeric-scope.failed_scope_is_terminal'),
        ('numeric-scope-discards-index', 'packages/runtime/src/numeric-scope.bend',
         'case Done{scope}: Done{Connect.V6{address, scope}}', 'case Done{scope}: Done{Connect.V6{address, 0}}', 'laws/numeric-scope.successful_scope_retained'),
        ('numeric-scope-erases-request', 'packages/runtime/src/numeric-scope.bend',
         'case Done{Host.V6{address, Some{zone}}}: ResolveZone{address, zone}', 'case Done{Host.V6{address, Some{zone}}}: Ready{Done{Connect.V6{address, 0}}}', 'laws/numeric-scope.scoped_ipv6_retains_request'),
        ('numeric-host-accepts-wrong-family', 'packages/runtime/src/numeric-host.bend',
         'case Family.IPv4Only{} V6{_, _}: Fail{FamilyMismatch{}}', 'case Family.IPv4Only{} V6{address, zone}: Done{V6{address, zone}}', 'laws/numeric-host.ipv4_rejects_ipv6'),
        ('numeric-host-erases-zone', 'packages/runtime/src/numeric-host.bend',
         'case _ value: Done{value}', 'case _ V6{address, _}: Done{V6{address, None{}}}\n    case _ value: Done{value}', 'laws/numeric-host.unrestricted_preserves_input'),
        ('numeric-host-replaces-parse-error', 'packages/runtime/src/numeric-host.bend',
         'case Fail{error}: Fail{error}', 'case Fail{error}: Fail{FamilyMismatch{}}', 'laws/numeric-host.failed_parse_retained'),
        ('dns-pair-queries-loses-aaaa-type', 'packages/runtime/src/dns-pair-queries.bend',
         'Message.Question{name, 28, 1}', 'Message.Question{name, 1, 1}', 'laws/dns-pair-queries.shared_query_intent'),
        ('dns-pair-queries-mislabels-first-error', 'packages/runtime/src/dns-pair-queries.bend',
         'Fail{Encoding{IPv4{}, error}}', 'Fail{Encoding{IPv6{}, error}}', 'laws/dns-pair-queries.first_encoding_failure'),
        ('dns-pair-queries-rejects-valid-intent', 'packages/runtime/src/dns-pair-queries.bend',
         'case Done{_} Done{_}: Done{queries}', 'case Done{_} Done{_}: Fail{Encoding{IPv4{}, Edns.InvalidField{}}}', 'laws/dns-pair-queries.valid_queries_retained'),
        ('dns-pair-hides-terminal-report', 'packages/runtime/src/dns-pair-result.bend',
         'case Stopped{}: Run.Halt{reports}', 'case Stopped{}: Run.Answer{reports}', 'laws/dns-pair-result.left_terminal_retains_both'),
        ('dns-pair-swaps-family-reports', 'packages/runtime/src/dns-pair-result.bend',
         'Reports{Classified{a, da}, Classified{b, db}}', 'Reports{Classified{b, db}, Classified{a, da}}', 'laws/dns-pair-result.left_terminal_retains_both'),
        ('dns-pair-erases-unavailable-cause', 'packages/runtime/src/dns-pair-result.bend',
         'case Unavailable{cause} Unavailable{_}: Failed{cause}', 'case Unavailable{cause} Unavailable{_}: Failed{Response.EmptyAnswer{}}', 'laws/dns-pair-result.same_failure_is_stable'),
        ('dns-pair-ignores-second-error', 'packages/runtime/src/dns-pair-result.bend',
         'response(Bool.pick(U32, U32.is_eq(ipv4, 0), ipv6, ipv4))', 'response(ipv4)', 'laws/dns-pair-result.empty_reply_defers_to_other_code'),
        ('dns-text-drops-dot', 'packages/runtime/src/dns-search-text.bend',
         'case True{}: Succ{rest}', 'case True{}: rest', 'laws/dns-search-text.leading_dot_counted'),
        ('dns-text-erases-parse-error', 'packages/runtime/src/dns-search-text.bend',
         'case Fail{error}: Fail{error}', 'case Fail{error}: Fail{Presentation.RawNul{}}', 'laws/dns-search-text.invalid_input_is_terminal'),
        ('dns-text-discards-absolute', 'packages/runtime/src/dns-search-text.bend',
         'Input{name, U32.from_nat(dots(text)), absolute}', 'Input{name, U32.from_nat(dots(text)), False{}}', 'laws/dns-search-text.prepared_fields_retained'),
        ('hosts-dispatch-ignores-source-error', 'packages/runtime/src/hosts-resolve.bend',
         'case Fail{error}: SourceFailure{error}', 'case Fail{error}: Query{family, name}', 'laws/hosts-resolve.source_error_is_terminal'),
        ('hosts-dispatch-queries-despite-local-result', 'packages/runtime/src/hosts-resolve.bend',
         'case first <> rest: Local{first, rest}', 'case first <> rest: Query{family, name}', 'laws/hosts-resolve.eligible_rows_are_local'),
        ('hosts-dispatch-erases-query-name', 'packages/runtime/src/hosts-resolve.bend',
         'case Nil{}: Query{family, name}', 'case Nil{}: Query{family, ""}', 'laws/hosts-resolve.empty_database_queries_original'),
        ('hosts-family-admits-wrong-family', 'packages/runtime/src/hosts-family.bend',
         'case _ _: False{}', 'case _ _: True{}', 'laws/hosts-resolve.ipv4_excludes_ipv6'),
        ('strict-utf8-erases-first-error', 'packages/runtime/src/utf8-strict.bend',
         'case _ Fail{error}: Fail{error}', 'case _ Fail{error}: Fail{IncompleteSequence{0n}}', 'laws/utf8-strict.failure_retained'),
        ('strict-utf8-accepts-truncated-text', 'packages/runtime/src/utf8-strict.bend',
         'case Done{State{offset, UTF8.Accumulator{UTF8.Decoder{UTF8.Continuation{_, _, _, _}, _}, _}}}: Fail{IncompleteSequence{offset}}',
         'case Done{State{offset, UTF8.Accumulator{UTF8.Decoder{UTF8.Continuation{_, _, _, _}, _}, reversed}}}: Done{String.reverse(reversed)}', 'laws/utf8-strict.incomplete_rejected'),
        ('strict-utf8-loses-invalid-byte-offset', 'packages/runtime/src/utf8-strict.bend',
         'Fail{InvalidByte{offset, byte}}', 'Fail{InvalidByte{0n, byte}}', 'laws/utf8-strict.invalid_byte_rejected'),
        ('provider-hook-ignores-replacement', 'packages/ai/src/utils/provider-request.bend',
         'case Done{Some{value}}: Done{value}', 'case Done{Some{value}}: Done{original}', 'laws/provider-request.present_replacement_is_exact'),
        ('provider-hook-discards-payload-error', 'packages/ai/src/utils/provider-request.bend',
         'Fail{PayloadFailure{cause}}', 'Fail{RequestFailure{Retry.RequestAborted{}}}', 'laws/provider-request.payload_failure_is_preserved'),
        ('provider-hook-skips-owner-release', 'packages/ai/src/utils/provider-request.bend',
         'cleanup : Result<&2, &2, E, Unit> <- release(owner)',
         'cleanup : Result<&2, &2, E, Unit> <- IO.pure(Result<&2, &2, E, Unit>, Done{Unit{}})', 'laws/provider-request.failed_response_hook_retires_owner_first'),
        ('provider-response-view-discards-owner', 'packages/ai/src/utils/provider-response-view.bend',
         'Response.Response{metadata, body}, T.ProviderResponse',
         'Response.Response{metadata, Response.Closed{None{}}}, T.ProviderResponse', 'laws/provider-response-view.metadata_projection_retains_owned_response'),
        ('text-budget-appends-after-stop', 'packages/runtime/src/text-unit-budget.bend',
         'Stopped{prefix, omitted + width(char)}', 'Stopped{SCon{char, prefix}, omitted + width(char)}', 'laws/text-unit-budget.stopped_prefix_is_stable'),
        ('text-budget-drops-fitting-character', 'packages/runtime/src/text-unit-budget.bend',
         'Taking{remaining - size, SCon{char, reversed}}', 'Taking{remaining - size, reversed}', 'laws/text-unit-budget.fitting_character_is_preserved'),
        ('openai-error-discards-read-cause', 'packages/ai/src/api/openai-http-error.bend',
         'Fail{DiagnosticReadFailure{metadata, cause}}',
         'Fail{DiagnosticEncodingFailure{metadata, TextDiagnostic{""}}}', 'laws/openai-http-error.diagnostic_read_failure_retains_cause'),
        ('openai-error-discards-diagnostic', 'packages/ai/src/api/openai-http-error.bend',
         'APIError{metadata, diagnostic, statusMessage(Metadata.status(metadata), text)}',
         'APIError{metadata, TextDiagnostic{""}, statusMessage(Metadata.status(metadata), text)}', 'laws/openai-http-error.construction_retains_diagnostic'),
        ('openai-error-ignores-envelope', 'packages/ai/src/api/openai-http-error.bend',
         'case Some{value}: value', 'case Some{value}: fallback', 'laws/openai-http-error.present_error_is_selected'),
        ('provider-http-discards-success', 'packages/ai/src/utils/provider-http-response.bend',
         'Done{Response.Response{metadata, body}})', 'Fail{StatusFailure{metadata, Done{""}}})', 'laws/provider-http-response.accepted_owner_has_no_body_io'),
        ('provider-http-skips-diagnostic-consumption', 'packages/ai/src/utils/provider-http-response.bend',
         'Consume.textUsing(E, State, read, close, limit, body)',
         'IO.pure(Result<&2, &2, Consume.TextError<E>, String>, Done{""})', 'laws/provider-http-response.rejected_owner_runs_diagnostic_first'),
        ('provider-http-erases-status', 'packages/ai/src/utils/provider-http-response.bend',
         'Some{F.fromU32(status)}', 'Some{F.fromU32(0)}', 'laws/provider-http-response.retry_metadata_projection'),
        ('retry-discards-successful-owner', 'packages/ai/src/utils/provider-retry.bend',
         'case _ Done{value}: IO.pure(Decision<v, E, Value>, Finished{Done{value}})', 'case _ Done{value}: IO.pure(Decision<v, E, Value>, Finished{Fail{RequestAborted{}}})', 'laws/provider-retry.success_bypasses_retry_effects'),
        ('retry-continues-after-finish', 'packages/ai/src/utils/provider-retry.bend',
         'case Finished{result}: IO.pure(Result<&2, v, RetryFailure<E>, Value>, result)', 'case Finished{result}: next(Unit{})', 'laws/provider-retry.finished_bypasses_continuation'),
        ('retry-ignores-abort-on-failure', 'packages/ai/src/utils/provider-retry.bend',
         'case True{} _: IO.pure(Decision<v, E, Value>, Finished{Fail{RequestAborted{}}})', 'case True{} _: IO.pure(Decision<v, E, Value>, Finished{Fail{RequestFailed{failure}}})', 'laws/provider-retry.abort_stops_failed_request'),
        ('body-buffer-discards-cleanup', 'packages/runtime/src/http-body-buffer.bend',
         'Fail{FailureWithCleanup{primary, cleanup}}', 'Fail{PrimaryFailure{primary}}', 'laws/http-body-buffer.simultaneous_failures_preserved'),
        ('body-buffer-returns-prefix-on-read-failure', 'packages/runtime/src/http-body-buffer.bend',
         'case Fail{error}: Finished{Fail{ReadFailure{error}}}', 'case Fail{error}: completed(E, Bytes.finish(buffer))', 'laws/http-body-buffer.read_failure_rejects_prefix'),
        ('body-buffer-continues-after-overflow', 'packages/runtime/src/http-body-buffer.bend',
         'case Bytes.State{_, _, True{}}: Finished{Fail{ByteLimitExceeded{}}}', 'case Bytes.State{_, _, True{}}: Continue{Bytes.create(0n)}', 'laws/http-body-buffer.any_excess_stops'),
        ('bounded-finish-reverses-body', 'packages/runtime/src/bounded-bytes.bend',
         'Done{List.reverse(&2, U32, reversed)}', 'Done{reversed}', 'laws/bounded-bytes.fitting_input_preserved'),
        ('bounded-finish-accepts-truncation', 'packages/runtime/src/bounded-bytes.bend',
         'case State{_, _, True{}}: Fail{LimitExceeded{}}', 'case State{_, _, True{}}: Done{Nil{}}', 'laws/bounded-bytes.overflow_rejected'),
        ('bounded-create-allows-extra-byte', 'packages/runtime/src/bounded-bytes.bend',
         'State{limit, Nil{}, False{}}', 'State{1n+limit, Nil{}, False{}}', 'laws/bounded-bytes.fitting_input_preserved'),
        ('bounded-reader-forgets-overflow', 'packages/runtime/src/bounded-bytes.bend',
         'case _ State{_, reversed, True{}}: State{0n, reversed, True{}}', 'case _ State{_, reversed, True{}}: State{0n, reversed, False{}}', 'laws/bounded-bytes.overflow_sticky'),
        ('bounded-reader-retains-excess-byte', 'packages/runtime/src/bounded-bytes.bend',
         'case _ <> _ State{0n, reversed, False{}}: State{0n, reversed, True{}}', 'case byte <> _ State{0n, reversed, False{}}: State{0n, byte <> reversed, True{}}', 'laws/bounded-bytes.chunk_composition'),
        ('bounded-reader-does-not-consume-budget', 'packages/runtime/src/bounded-bytes.bend',
         'consumed(rest, State{remaining, byte <> reversed, False{}})', 'consumed(rest, State{1n+remaining, byte <> reversed, False{}})', 'laws/bounded-bytes.chunk_composition'),
        ('hosts-discards-matched-row', 'packages/runtime/src/hosts.bend',
         'case True{}: entry <> rest', 'case True{}: rest', 'laws/hosts.matched_entry_retained'),
        ('hosts-reverses-matches', 'packages/runtime/src/hosts.bend',
         'case True{}: entry <> rest', 'case True{}: List.append(&2, Entry<Address>, rest, entry <> Nil{})', 'proofs/hosts.selected_append'),
        ('hosts-ignores-canonical-name', 'packages/runtime/src/hosts.bend',
         'same(name, canonical) || alias(name, aliases)', 'alias(name, aliases)', 'laws/hosts.canonical_matches'),
        ('hosts-ignores-aliases', 'packages/runtime/src/hosts.bend',
         'same(name, canonical) || alias(name, aliases)', 'same(name, canonical)', 'laws/hosts.canonical_matches'),
        ('hosts-accepts-partial-database', 'packages/runtime/src/hosts-file.bend',
         'case Fail{error}: Fail{Failure{number, error}}', 'case Fail{error}: Done{reversed}', 'laws/hosts.invalid_line_discards_partial_database'),
        ('resolver-erases-transport-error', 'packages/runtime/src/resolver-configuration.bend',
         'case Fail{error}: Fail{error}', 'case Fail{error}: Fail{Plan.NoServers{}}', 'laws/resolver-configuration.rejects_invalid_transport'),
        ('resolver-search-discards-options', 'packages/runtime/src/resolver-configuration.bend',
         ': Search.Configuration{options, domains}', ': Search.Configuration{Options.defaults(), domains}', 'laws/resolver-configuration.shared_search_settings'),
        ('resolver-assembly-discards-deadline', 'packages/runtime/src/resolver-configuration.bend',
         'Done{Config{transport, domains, milliseconds, maximum}}', 'Done{Config{transport, domains, 0, maximum}}', 'laws/resolver-configuration.assembly_retains_configuration'),
        ('search-resumes-after-halt', 'packages/runtime/src/dns-search-run.bend',
         'case Halt{failure}: Finished{Fail{Halted{failure}}}',
         'case Halt{failure}: Active{cursor, history}', 'laws/dns-search-run.halt_is_terminal'),
        ('search-discards-answer', 'packages/runtime/src/dns-search-run.bend',
         'case Answer{value}: Finished{Done{value}}',
         'case Answer{value}: Active{cursor, history}', 'laws/dns-search-run.answer_is_terminal'),
        ('search-forgets-initial-failure', 'packages/runtime/src/dns-search-response.bend',
         'case History{Some{value}, _, _, _}: value',
         'case History{Some{value}, _, _, last}: last', 'laws/dns-search-run.initial_failure_precedence'),
        ('transport-settings-discarded', 'packages/runtime/src/resolver-transport.bend',
         'Done{Prepared{options, servers}}', 'Done{Prepared{Options.defaults(), servers}}', 'laws/resolver-transport.settings_and_entries_preserved'),
        ('transport-timing-error-ignored', 'packages/runtime/src/resolver-transport.bend',
         'case Fail{error}: Fail{error}', 'case Fail{error}: Done{Prepared{options, Nil{}}}', 'laws/resolver-transport.preparation_failure_retained'),
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
    # Validate each affected proof module before mutating it, then require the
    # same named contract to reject the mutant. This avoids recompiling the
    # entire provider stack for unrelated queue/decoder mutations. The full
    # root, open obligations and missing-proof checks remain mandatory.
    results['mutation_baselines'] = {}
    def mutation_entry(diagnostic):
        module = diagnostic.split('.', 1)[0]
        if module.startswith('laws/'):
            module = 'proofs/' + module[len('laws/'):]
        module += '.bend'
        assert (directory / module).exists(), module
        pending = [module]
        visited = set()
        while pending:
            relative = pending.pop()
            if relative in visited:
                continue
            visited.add(relative)
            path = directory / relative
            # A law module may import another module's specifications without
            # importing its proofs. Include those proofs transitively too.
            if relative.startswith('laws/'):
                companion = 'proofs/' + relative[len('laws/'):]
                assert (directory / companion).exists(), companion
                pending.append(companion)
            for imported in re.findall(r'^import (\.[^\s]+)', path.read_text(), re.MULTILINE):
                pending.append(str((path.parent / imported).resolve().relative_to(directory)))
        # A future proof importing the global root still requires its complete
        # proof environment. Queue contracts now have a local laws module.
        if 'LAWS.bend' in visited:
            return 'PROOF.bend'
        entry = 'mutation-proof-' + Path(module).stem + '.bend'
        if entry not in results['mutation_baselines']:
            dependencies = sorted(name for name in visited if name.startswith('proofs/'))
            (directory / entry).write_text(''.join(f'import ./{name} as Contract{index}\n' for index, name in enumerate(dependencies)))
            baseline = check(directory, entry)
            accepted(baseline)
            results['mutation_baselines'][entry] = baseline
        return entry

    # Preflight every proof environment before changing any implementation.
    for _, _, _, _, diagnostic in extra_mutations:
        mutation_entry(diagnostic)

    for label, name, before, after, diagnostic in extra_mutations:
        target = directory / name
        entry = mutation_entry(diagnostic)
        original_extra = target.read_text()
        assert original_extra.count(before) == 1, label
        target.write_text(original_extra.replace(before, after))
        # Import under a namespace: standalone Set conflicts with Base.Set.
        # This checks the module exactly as production callers import it.
        (directory / 'mutation-module.bend').write_text(f'import ./{name} as Subject\n')
        typed = check(directory, 'mutation-module.bend')
        typed['module'] = name
        accepted(typed)
        proof_result = check(directory, entry)
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
assert source_hashes == {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in source_hashes}, 'proof sources changed during validation'
results['sha256'] = source_hashes
(ROOT / 'build/proof-check.json').write_text(json.dumps(results, indent=2) + '\n')
print(f"PASS generic laws; open obligations, missing proof and {len(results['mutations'])} well-typed mutations rejected")
