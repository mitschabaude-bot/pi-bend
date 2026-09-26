import Base
import ../packages/ai/test/anthropic-sse-parsing.bend as SseParsing
import ../packages/ai/test/anthropic-temperature-compat.bend as Temperature
import ../packages/ai/test/anthropic-force-adaptive-thinking.bend as ForceAdaptive
import ../packages/ai/test/anthropic-thinking-disable.bend as ThinkingDisable
import ../packages/ai/test/anthropic-empty-thinking-signature-compat.bend as EmptySignature
import ../packages/ai/test/anthropic-cache-write-1h-cost.bend as CacheWrite
import ../packages/ai/test/anthropic-mid-conversation-effort.bend as MidConversation
import ../packages/ai/test/anthropic-eager-tool-input-compat.bend as EagerToolInput
import ../packages/ai/test/github-copilot-anthropic.bend as CopilotAnthropic
import ../packages/ai/test/anthropic-auth-token.bend as AuthToken

# The ported upstream Anthropic suites (tests/anthropic_messages_check.py).
def main() -> IO(Unit):
  do IO<Unit>:
    SseParsing.run()
    Temperature.run()
    ForceAdaptive.run()
    ThinkingDisable.run()
    EmptySignature.run()
    CacheWrite.run()
    MidConversation.run()
    EagerToolInput.run()
    CopilotAnthropic.run()
    AuthToken.run()
