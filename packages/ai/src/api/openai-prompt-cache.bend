import Base
import ../../../runtime/src/utf16.bend as Utf16

# Array.from upstream counts Unicode code points, not UTF-16 units. Normalize
# adjacent surrogate units before applying this provider's 64-character limit.
def OPENAI_PROMPT_CACHE_KEY_MAX_LENGTH() -> Nat: 64n

def clampOpenAIPromptCacheKey(key: Maybe<&2, String>) -> Maybe<&2, String>:
  match key:
    case None{}: None{}
    case Some{text}: Some{String.take(Utf16.normalize(text), OPENAI_PROMPT_CACHE_KEY_MAX_LENGTH())}
