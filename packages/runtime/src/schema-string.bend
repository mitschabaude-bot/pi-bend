import Base
import ./big-nat.bend as B

# The pinned schema dependency measures a limited set of grapheme clusters.
# Keep this validation policy separate from general Unicode segmentation: skin
# tones, Hangul composition and other UAX #29 rules are not part of this policy.
def between(+point: U32, lower: U32, upper: U32) -> Bool:
  U32.is_ge(point, lower) && U32.is_le(point, upper)

def modifier(+point: U32) -> Bool:
  between(point, 768, 879) || between(point, 6832, 6911) || between(point, 7616, 7679) || between(point, 65056, 65071) || between(point, 65024, 65039)

def regional(point: U32) -> Bool: between(point, 127462, 127487)

def modifiers(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+point}, +rest}:
      Bool.pick(Unit -> String, modifier(point), _ => modifiers(rest), _ => SCon{Chr{point}, rest})(Unit{})

@unsafe
def joined(text: String) -> String:
  match text:
    case SCon{Chr{8205}, SCon{_, rest}}: joined(modifiers(rest))
    case other: other

def regionalPair(enabled: Bool, text: String) -> String:
  match enabled text:
    case True{} SCon{Chr{+point}, +rest}: Bool.pick(String, regional(point), rest, SCon{Chr{point}, rest})
    case _ other: other

def next(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{point}, rest}: regionalPair(regional(point), joined(modifiers(rest)))

# Every iteration consumes at least its first scalar, plus any recognized
# modifiers/joined scalars. Large declared bounds never expand into unary Nats.
@unsafe
def countFrom(text: String, total: B.BigNat) -> B.BigNat:
  match text:
    case SNil{}: total
    case SCon{point, rest}: countFrom(next(SCon{point, rest}), B.add(total, B.fromU32(1)))

def length(text: String) -> B.BigNat: countFrom(text, B.zero())
