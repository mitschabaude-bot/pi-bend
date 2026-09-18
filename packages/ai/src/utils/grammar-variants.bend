import Base
import ../types.bend as T

def empty() -> T.GrammarVariants: T.GrammarVariants{None{}, None{}}

def set(variants: T.GrammarVariants, format: T.GrammarFormat, value: Maybe<&2, String>) -> T.GrammarVariants:
  match variants format:
    case T.GrammarVariants{_, regex} T.OpenAILark{}: T.GrammarVariants{value, regex}
    case T.GrammarVariants{lark, _} T.OpenAIRegex{}: T.GrammarVariants{lark, value}

def get(variants: T.GrammarVariants, format: T.GrammarFormat) -> Maybe<&2, String>:
  match variants format:
    case T.GrammarVariants{lark, _} T.OpenAILark{}: lark
    case T.GrammarVariants{_, regex} T.OpenAIRegex{}: regex

def remove(variants: T.GrammarVariants, format: T.GrammarFormat) -> T.GrammarVariants:
  set(variants, format, None{})
