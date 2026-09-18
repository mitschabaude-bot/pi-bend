import Base
import ../types.bend as T

# Ordered operations for Partial<Record<GrammarFormat, string>>. None means an
# own property whose value is undefined; removing it is a separate operation.
def name(format: T.GrammarFormat) -> String:
  match format:
    case T.OpenAILark{}: "openai_lark"
    case T.OpenAIRegex{}: "openai_regex"

def same(left: T.GrammarFormat, right: T.GrammarFormat) -> Bool:
  match left right:
    case T.OpenAILark{} T.OpenAILark{}: True{}
    case T.OpenAIRegex{} T.OpenAIRegex{}: True{}
    case _ _: False{}

def empty() -> T.GrammarVariants: T.GrammarVariants{Nil{}}

def put(properties: List<&2, T.GrammarVariant>, +format: T.GrammarFormat, +value: Maybe<&2, String>) -> List<&2, T.GrammarVariant>:
  match properties:
    case Nil{}: T.GrammarVariant{format, value} <> Nil{}
    case T.GrammarVariant{+key, old} <> +rest:
      Bool.pick(List<&2, T.GrammarVariant>, same(key, format), T.GrammarVariant{format, value} <> rest, T.GrammarVariant{key, old} <> put(rest, format, value))

def set(variants: T.GrammarVariants, format: T.GrammarFormat, value: Maybe<&2, String>) -> T.GrammarVariants:
  match variants:
    case T.GrammarVariants{properties}: T.GrammarVariants{put(properties, format, value)}

def lookup(properties: List<&2, T.GrammarVariant>, +format: T.GrammarFormat) -> Maybe<&2, Maybe<&2, String>>:
  match properties:
    case Nil{}: None{}
    case T.GrammarVariant{key, value} <> rest:
      Bool.pick(Maybe<&2, Maybe<&2, String>>, same(key, format), Some{value}, lookup(rest, format))

def get(variants: T.GrammarVariants, format: T.GrammarFormat) -> Maybe<&2, Maybe<&2, String>>:
  match variants:
    case T.GrammarVariants{properties}: lookup(properties, format)

def erase(properties: List<&2, T.GrammarVariant>, +format: T.GrammarFormat) -> List<&2, T.GrammarVariant>:
  match properties:
    case Nil{}: Nil{}
    case T.GrammarVariant{+key, value} <> +rest:
      Bool.pick(List<&2, T.GrammarVariant>, same(key, format), rest, T.GrammarVariant{key, value} <> erase(rest, format))

def remove(variants: T.GrammarVariants, format: T.GrammarFormat) -> T.GrammarVariants:
  match variants:
    case T.GrammarVariants{properties}: T.GrammarVariants{erase(properties, format)}
