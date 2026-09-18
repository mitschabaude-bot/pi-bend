import Base
import ../types.bend as T

def rank(level: T.ModelThinkingLevel) -> U32:
  match level:
    case T.Off{}: 0
    case T.Thinking{T.Minimal{}}: 1
    case T.Thinking{T.Low{}}: 2
    case T.Thinking{T.Medium{}}: 3
    case T.Thinking{T.High{}}: 4
    case T.Thinking{T.XHigh{}}: 5
    case T.Thinking{T.Max{}}: 6

def name(level: T.ModelThinkingLevel) -> String:
  match level:
    case T.Off{}: "off"
    case T.Thinking{T.Minimal{}}: "minimal"
    case T.Thinking{T.Low{}}: "low"
    case T.Thinking{T.Medium{}}: "medium"
    case T.Thinking{T.High{}}: "high"
    case T.Thinking{T.XHigh{}}: "xhigh"
    case T.Thinking{T.Max{}}: "max"

def all() -> List<&2, T.ModelThinkingLevel>:
  T.Off{} <> T.Thinking{T.Minimal{}} <> T.Thinking{T.Low{}} <> T.Thinking{T.Medium{}} <> T.Thinking{T.High{}} <> T.Thinking{T.XHigh{}} <> T.Thinking{T.Max{}} <> Nil{}

# An absent property and an own undefined value both read as undefined. Null
# stays distinct and disables the level. Ordered mappings require unique keys.
def lookup(properties: List<&2, T.ThinkingLevelMapping>, +level: T.ModelThinkingLevel) -> Maybe<&2, T.Nullable<String>>:
  match properties:
    case Nil{}: None{}
    case T.ThinkingLevelMapping{key, value} <> tail:
      Bool.pick(Maybe<&2, T.Nullable<String>>, U32.is_eq(rank(key), rank(level)), value, lookup(tail, level))

def mapped(mapping: Maybe<&2, T.ThinkingLevelMap>, level: T.ModelThinkingLevel) -> Maybe<&2, T.Nullable<String>>:
  match mapping:
    case None{}: None{}
    case Some{T.ThinkingLevelMap{properties}}: lookup(properties, level)

def supported(level: T.ModelThinkingLevel, value: Maybe<&2, T.Nullable<String>>) -> Bool:
  match value:
    case Some{T.NullValue{}}: False{}
    case Some{T.PresentValue{_}}: True{}
    case None{}: U32.is_lt(rank(level), 5)

def filter(levels: List<&2, T.ModelThinkingLevel>, +mapping: Maybe<&2, T.ThinkingLevelMap>) -> List<&2, T.ModelThinkingLevel>:
  match levels:
    case Nil{}: Nil{}
    case +head <> tail:
      +rest = filter(tail, mapping)
      Bool.pick(List<&2, T.ModelThinkingLevel>, supported(head, mapped(mapping, head)), head <> rest, rest)

def available(reasoning: Bool, mapping: Maybe<&2, T.ThinkingLevelMap>) -> List<&2, T.ModelThinkingLevel>:
  match reasoning:
    case False{}: T.Off{} <> Nil{}
    case True{}: filter(all(), mapping)

# Supported levels are in ascending order. Prefer an equal/higher level, then
# the closest lower one. If all levels are disabled, upstream returns off.
def closest(remaining: List<&2, T.ModelThinkingLevel>, +requested: U32, fallback: T.ModelThinkingLevel) -> T.ModelThinkingLevel:
  match remaining:
    case Nil{}: fallback
    case +head <> tail: Bool.pick(T.ModelThinkingLevel, U32.is_ge(rank(head), requested), head, closest(tail, requested, head))
