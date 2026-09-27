import Base
import ../packages/ai/test/openai-responses-partial-json-cleanup.bend as PartialJson
import ../packages/ai/test/pre-generation-error.bend as PreGeneration
import ../packages/ai/test/opencode-provider-headers.bend as OpenCode
import ../packages/ai/test/google-tool-call-counter.bend as GoogleCounter
import ../packages/ai/test/oauth-device-code.bend as DeviceCode
import ../packages/ai/test/openrouter-oauth.bend as OpenRouterProviders
import ../packages/ai/test/oauth-auth.bend as OAuthModels
import ../packages/ai/test/assistant-message-frame.bend as Frames

# Standalone ai suite ports without a differential runner of their own:
# openai-responses-partial-json-cleanup, pre-generation-error (partial) and
# opencode-provider-headers, oauth-device-code (real clock), the provider half
# of openrouter-oauth, the Models.getAuth half of oauth-auth,
# assistant-message-frame, and the native Gemini tool-call id counter check.
def main() -> IO(Unit):
  do IO<Unit>:
    PartialJson.run()
    PreGeneration.run()
    OpenCode.main()
    GoogleCounter.run()
    DeviceCode.run()
    OpenRouterProviders.run()
    OAuthModels.run()
    Frames.run()
