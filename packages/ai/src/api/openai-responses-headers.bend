import Base
import ../types.bend as T
import ../utils/provider-headers.bend as Headers
import ./openai-responses-policy.bend as Policy
import ../../../runtime/src/record.bend as R

def userAgentHeader(value: String) -> T.ProviderHeaders():
  R.Record{R.Property{"User-Agent", T.PresentValue{value}} <> Nil{}}

# Pure assembly extracted from createClient. The caller obtains the user agent
# and Copilot dynamic headers; normalization occurs at the transport boundary.
def defaultHeaders(userAgent: String, modelHeaders: Maybe<&2, R.Record<String>>, copilotHeaders: Maybe<&2, R.Record<String>>, affinity: T.SessionAffinityFormat, sessionId: Maybe<&2, String>, optionsHeaders: Maybe<&2, T.ProviderHeaders()>) -> T.ProviderHeaders():
  defaults = userAgentHeader(userAgent)
  model = Headers.overlayStrings(defaults, modelHeaders)
  copilot = Headers.overlayStrings(model, copilotHeaders)
  session = Headers.overlayStrings(copilot, Some{Policy.affinityHeaders(affinity, sessionId)})
  Headers.overlay(session, optionsHeaders)
