import Base
import ../laws/openai-responses-acquire.bend as Laws

def Laws.preparation_preserves_client_and_payload(url, defaults, timeout, key, base, headers, payload, compat, grammar, retention): {==}
def Laws.invalid_envelope_has_no_transport_effect(Error, State, encode, request, cause): {==}
def Laws.valid_envelope_transfers_unchanged(Error, State, encode, request, wire): {==}
