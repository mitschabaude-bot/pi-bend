import Base
import ../packages/ai/test/openai-responses-message-id.bend as Ids
import ../packages/ai/test/openai-responses-foreign-toolcall-id.bend as Foreign
import ../packages/ai/test/openai-responses-empty-tool-result.bend as EmptyResult
import ../packages/ai/test/openai-responses-namespace.bend as Namespace

def main() -> IO(Unit):
  do IO<Unit>:
    Ids.run()
    Foreign.run()
    EmptyResult.run()
    Namespace.run()
