import Base
import ../../../ai/src/types.bend as Ai
import ../../../ai/src/utils/thinking-levels.bend as Levels

# upstream core/defaults.ts
def DEFAULT_THINKING_LEVEL() -> Ai.ModelThinkingLevel: Ai.Thinking{Ai.Medium{}}
def THINKING_LEVEL_OPTIONS() -> List<&2, Ai.ModelThinkingLevel>: Levels.all()
