import Base
import ./url-percent.bend as Percent
import ./url-query.bend as Query

type Parsed is Data:
  Parsed{value: String, query: Maybe<&2, String>, fragment: Maybe<&2, String>}

# Only the final literal space directly before '?' or '#' is encoded here.
# Other spaces remain literal. Constructor-edge trimming happens before this
# state; path parsing must not trim data supplied through other parser entries.
def beforeDelimiter(reversed: String) -> String:
  match reversed:
    case SCon{' ', rest}: Percent.encode(Percent.Controls{}, String.reverse(rest)) ++ "%20"
    case other: Percent.encode(Percent.Controls{}, String.reverse(other))

def queried(value: String, result: Query.Parsed) -> Parsed:
  match result:
    case Query.Parsed{query, fragment}: Parsed{value, Some{query}, fragment}

# The enclosing parser enters this state only for an opaque path. It does not
# split slashes, shorten dot segments, decode escapes, or normalize drive names.
def scan(text: String, reversed: String) -> Parsed:
  match text:
    case SNil{}: Parsed{Percent.encode(Percent.Controls{}, String.reverse(reversed)), None{}, None{}}
    case SCon{'?', rest}: queried(beforeDelimiter(reversed), Query.parse(rest, False{}))
    case SCon{'#', rest}: Parsed{beforeDelimiter(reversed), None{}, Some{Percent.encode(Percent.Fragment{}, rest)}}
    case SCon{char, rest}: scan(rest, SCon{char, reversed})

def parse(text: String) -> Parsed: scan(text, "")
