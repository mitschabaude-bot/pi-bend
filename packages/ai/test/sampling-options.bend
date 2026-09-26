import Base
import ../src/types.bend as T
import ./anthropic-harness.bend as H
import ../../runtime/src/f64.bend as F
import ../../runtime/src/record.bend as R

# pi-mono f07218c4d packages/ai/test/sampling-options.test.ts, the case for a
# non-OpenAI-compatible API (Anthropic Messages, through streamSimple with the
# payload captured by onPayload). The Chat Completions cases run in
# tests/openai_completions_request_check.py.
def sampled(options: H.Simple(), sampling: R.Record<T.JsonValue>) -> H.Simple():
  match options:
    case T.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, _, maxTokens, transport, cache, session, ws, metadata, choice, reasoning, deferred, budgets}:
      T.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, Some{sampling}, maxTokens, transport, cache, session, ws, metadata, choice, reasoning, deferred, budgets}

def run() -> IO(Unit):
  +model = H.custom("vendor--claude", "Vendor Proxy Claude", "vendor-proxy", "http://127.0.0.1:9", 32000, 200000, None{}, None{})
  +name = {"is ignored by non-OpenAI-compatible APIs" : String}
  +sampling = {R.Record{R.Property{"top_p", T.JsonNumber{F.divide(F.fromU32(9), F.fromU32(10))}} <> R.Property{"top_k", T.JsonNumber{F.fromU32(40)}} <> Nil{}} : R.Record<T.JsonValue>}
  do IO<Unit>:
    outcome : H.Outcome <- H.runSimple(model, H.hello(), sampled(H.simple(Some{"fake-key"}, None{}, None{}), sampling), H.Capture{})
    +payload : Maybe<&2, T.JsonValue> <- IO.pure(Maybe<&2, T.JsonValue>, H.payloadOf(outcome))
    H.check(Maybe.is_some(&2, T.JsonValue, payload), name ++ ": payload captured")
    H.absent(H.fieldOf(payload, "top_p"), name)
    H.absent(H.fieldOf(payload, "top_k"), name)
    H.pass(name)
