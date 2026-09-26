import Base
import ../packages/ai/test/google-thinking-signature.bend as ThinkingSignature
import ../packages/ai/test/google-shared-convert-tools.bend as ConvertTools
import ../packages/ai/test/google-shared-gemini3-unsigned-tool-call.bend as UnsignedToolCall
import ../packages/ai/test/google-shared-image-tool-result-routing.bend as ImageRouting
import ../packages/ai/test/google-shared-signed-empty-blocks.bend as SignedEmptyBlocks
import ../packages/ai/test/google-shared-retry.bend as Retry
import ../packages/ai/test/google-thinking-level-map.bend as LevelMap
import ../packages/ai/test/google-raw-stop-reason.bend as RawStopReason
import ../packages/ai/test/google-fetch-option.bend as FetchOption

# The ported upstream Google suites (tests/google_generative_ai_check.py).
def main() -> IO(Unit):
  do IO<Unit>:
    ThinkingSignature.run()
    ConvertTools.run()
    UnsignedToolCall.run()
    ImageRouting.run()
    SignedEmptyBlocks.run()
    Retry.run()
    LevelMap.run()
    RawStopReason.run()
    FetchOption.run()
