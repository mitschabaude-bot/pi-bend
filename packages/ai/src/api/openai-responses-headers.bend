import Base
import ./github-copilot-headers.bend as Copilot
import ../types.bend as T
import ../utils/provider-headers.bend as Headers
import ./openai-responses-policy.bend as Policy
import ../../../runtime/src/record.bend as R

def userAgentHeader(value: String) -> T.ProviderHeaders():
  R.Record{R.Property{"User-Agent", T.PresentValue{value}} <> Nil{}}

# Pure assembly extracted from createClient. forContext supplies the Copilot
# headers; normalization occurs at the transport boundary.
def defaultHeaders(userAgent: String, modelHeaders: Maybe<&2, R.Record<String>>, copilotHeaders: Maybe<&2, R.Record<String>>, affinity: T.SessionAffinityFormat, sessionId: Maybe<&2, String>, optionsHeaders: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  defaults = userAgentHeader(userAgent)
  model = Headers.overlayStrings(defaults, modelHeaders)
  copilot = Headers.overlayStrings(model, copilotHeaders)
  session = Headers.overlayStrings(copilot, Some{Policy.affinityHeaders(affinity, sessionId)})
  Headers.overlay(session, optionsHeaders)

# Client-facing assembly derives dynamic headers from the canonical transcript.
def forContext(-P: Data, -A: Data, -D: Data, -U: Data, userAgent: String, provider: String, modelHeaders: Maybe<&2, R.Record<String>>, context: T.TranscriptContext<P, A, D, U>, affinity: T.SessionAffinityFormat, sessionId: Maybe<&2, String>, optionsHeaders: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  match context:
    case T.TranscriptContext{messages}:
      defaultHeaders(userAgent, modelHeaders, Copilot.forProvider(P, A, D, U, provider, messages), affinity, sessionId, optionsHeaders)
