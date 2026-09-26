import Base
import ../packages/ai/test/openai-responses-partial-json-cleanup.bend as PartialJson
import ../packages/ai/test/pre-generation-error.bend as PreGeneration
import ../packages/ai/test/opencode-provider-headers.bend as OpenCode

# Standalone ai suite ports without a differential runner of their own:
# openai-responses-partial-json-cleanup, pre-generation-error (partial) and
# opencode-provider-headers.
def main() -> IO(Unit):
  do IO<Unit>:
    PartialJson.run()
    PreGeneration.run()
    OpenCode.main()
