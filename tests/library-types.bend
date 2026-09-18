import Base
import ../packages/runtime/src/schema.bend as Schema
import ../packages/ai/src/types.bend as Ai
import ../packages/ai/src/models.bend as Models
import ../packages/ai/src/utils/transcript.bend as Transcript
import ../packages/ai/src/utils/validation.bend as Validation
import ../packages/agent/src/types.bend as Agent
import ../packages/agent/src/agent-loop.bend as Loop
import ../packages/agent/src/tool-update-scope.bend as Updates

def main() -> IO(Unit):
  IO.print("PASS canonical library type check")
