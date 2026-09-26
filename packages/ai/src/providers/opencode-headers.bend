import Base
import ../types.bend as T
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/text.bend as Space

# pi-mono packages/ai/src/providers/opencode-headers.ts: OpenCode's required
# per-conversation routing header, added before API dispatch. The provider's
# stream wrapper is Models.OpenCodeStreams; these are its option rewrites for
# `stream` and `streamSimple`.
def OPENCODE_SESSION_HEADER() -> String: "x-opencode-session"

# Any caller entry with the name, case-insensitively, even a null removal.
def namedIn(entries: List<&2, R.Property<T.Nullable<String>>>, +name: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case R.Property{key, _} <> rest: String.eq(Space.asciiLower(key), name) || namedIn(rest, name)

def hasHeader(headers: Maybe<&2, T.ProviderHeaders()>, name: String) -> Bool:
  match headers:
    case None{}: False{}
    case Some{R.Record{entries}}: namedIn(entries, Space.asciiLower(name))

# The headers after `withSessionHeader`: the caller's entries, then the
# session header unless the caller already names it.
def sessionHeaders(+headers: Maybe<&2, T.ProviderHeaders()>, sessionId: Maybe<&2, String>) -> Maybe<&2, T.ProviderHeaders()>:
  match sessionId:
    case Some{SCon{c, cs}}:
      Bool.pick(Maybe<&2, T.ProviderHeaders()>, hasHeader(headers, OPENCODE_SESSION_HEADER()), headers, Some{R.set(T.Nullable<String>, Maybe.default(&2, T.ProviderHeaders(), headers, R.new(T.Nullable<String>)), OPENCODE_SESSION_HEADER(), T.PresentValue{SCon{c, cs}})})
    case _: headers

# Absent options stay absent, so callers pass present ones.
def withSessionHeader(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: T.StreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> T.StreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match options:
    case T.StreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, +session, ws, metadata}:
      T.StreamOptions{signal, telemetry, key, fetch, env, payload, response, sessionHeaders(headers, session), timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata}

def withSimpleSessionHeader(-Value: Data, -Signal: Data, -Telemetry: Data, -Fetch: Data, -Error: Data, options: T.SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>) -> T.SimpleStreamOptions<Value, Signal, Telemetry, Fetch, Error>:
  match options:
    case T.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, headers, timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, +session, ws, metadata, choice, reasoning, deferred, budgets}:
      T.SimpleStreamOptions{signal, telemetry, key, fetch, env, payload, response, sessionHeaders(headers, session), timeout, retries, delay, temperature, sampling, maxTokens, transport, cache, session, ws, metadata, choice, reasoning, deferred, budgets}
