import Base
import ../laws/thinking-levels.bend as Laws
import ../packages/ai/src/types.bend as T
import ../packages/ai/src/utils/thinking-levels.bend as Levels

def Laws.non_reasoning_models_only_offer_off(mapping): {==}

def Laws.an_explicit_null_disables_a_level(level): {==}

def Laws.an_explicit_mapping_enables_a_level(level, value): {==}

def Laws.unmapped_levels_are_supported_up_to_high(level):
  match level:
    case T.Off{}: {==}
    case T.Thinking{T.Minimal{}}: {==}
    case T.Thinking{T.Low{}}: {==}
    case T.Thinking{T.Medium{}}: {==}
    case T.Thinking{T.High{}}: {==}
    case T.Thinking{T.XHigh{}}: {==}
    case T.Thinking{T.Max{}}: {==}

def Laws.closest_takes_the_first_level_at_or_above_the_request(head, tail, requested, fallback, enough):
  Equal.cong(Bool, T.ModelThinkingLevel, above => Bool.pick(T.ModelThinkingLevel, above, head, Levels.closest(tail, requested, head)), U32.is_ge(Levels.rank(head), requested), True{}, enough)

def Laws.closest_skips_levels_below_the_request(head, tail, requested, fallback, short):
  Equal.cong(Bool, T.ModelThinkingLevel, above => Bool.pick(T.ModelThinkingLevel, above, head, Levels.closest(tail, requested, head)), U32.is_ge(Levels.rank(head), requested), False{}, short)

def Laws.closest_without_candidates_is_the_fallback(requested, fallback): {==}

def Laws.a_level_name_reads_back_as_the_level(level):
  match level:
    case T.Off{}: {==}
    case T.Thinking{T.Minimal{}}: {==}
    case T.Thinking{T.Low{}}: {==}
    case T.Thinking{T.Medium{}}: {==}
    case T.Thinking{T.High{}}: {==}
    case T.Thinking{T.XHigh{}}: {==}
    case T.Thinking{T.Max{}}: {==}
