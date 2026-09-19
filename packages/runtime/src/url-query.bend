import Base
import ./url-percent.bend as Percent

# Entry after '?'. Presence is represented by this result even when value is
# empty; an absent query never enters this parser.
type Parsed is Data:
  Parsed{value: String, fragment: Maybe<&2, String>}

def encodeSet(special: Bool) -> Percent.EncodeSet:
  match special:
    case True{}: Percent.SpecialQuery{}
    case False{}: Percent.Query{}

# URL queries preserve '+' and existing escapes. Form decoding is separate.
def scan(text: String, +set: Percent.EncodeSet, reversed: String) -> Parsed:
  match text:
    case SNil{}: Parsed{Percent.encode(set, String.reverse(reversed)), None{}}
    case SCon{'#', rest}: Parsed{Percent.encode(set, String.reverse(reversed)), Some{Percent.encode(Percent.Fragment{}, rest)}}
    case SCon{char, rest}: scan(rest, set, SCon{char, reversed})

def parse(text: String, special: Bool) -> Parsed:
  scan(text, encodeSet(special), "")
