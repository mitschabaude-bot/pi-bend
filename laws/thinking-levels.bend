import Base
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/thinking-levels.bend as Levels

# Which thinking levels a model offers, and which one a request resolves to.

law non_reasoning_models_only_offer_off:
  for mapping: Maybe<&2, T.ThinkingLevelMap>
  {Levels.available(False{}, mapping) == T.Off{} <> Nil{} : List<&2, T.ModelThinkingLevel>}

law an_explicit_null_disables_a_level:
  for level: T.ModelThinkingLevel
  {Levels.supported(level, Some{T.NullValue{}}) == False{} : Bool}

law an_explicit_mapping_enables_a_level:
  for level: T.ModelThinkingLevel
  for value: String
  {Levels.supported(level, Some{T.PresentValue{value}}) == True{} : Bool}

law unmapped_levels_are_supported_up_to_high:
  for level: T.ModelThinkingLevel
  {Levels.supported(level, None{}) == U32.is_le(Levels.rank(level), 4) : Bool}

law closest_takes_the_first_level_at_or_above_the_request:
  for head: T.ModelThinkingLevel
  for tail: List<&2, T.ModelThinkingLevel>
  for +requested: U32
  for fallback: T.ModelThinkingLevel
  for enough: {U32.is_ge(Levels.rank(head), requested) == True{} : Bool}
  {Levels.closest(head <> tail, requested, fallback) == head : T.ModelThinkingLevel}

law closest_skips_levels_below_the_request:
  for head: T.ModelThinkingLevel
  for tail: List<&2, T.ModelThinkingLevel>
  for +requested: U32
  for fallback: T.ModelThinkingLevel
  for short: {U32.is_ge(Levels.rank(head), requested) == False{} : Bool}
  {Levels.closest(head <> tail, requested, fallback) == Levels.closest(tail, requested, head) : T.ModelThinkingLevel}

law closest_without_candidates_is_the_fallback:
  for requested: U32
  for fallback: T.ModelThinkingLevel
  {Levels.closest(Nil{}, requested, fallback) == fallback : T.ModelThinkingLevel}
