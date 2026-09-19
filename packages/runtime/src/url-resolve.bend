import Base
import ./url-absolute.bend as Absolute
import ./url-input.bend as Input
import ./url-record.bend as Record
import ./url-scheme.bend as Scheme
import ./url-authority.bend as Authority
import ./url-path.bend as Path
import ./url-query.bend as Query
import ./url-percent.bend as Percent

type Error is Data:
  InvalidURL{reason: Absolute.Error}
  OpaqueBase{}

def absoluteResult(result: Result<&2, &2, Absolute.Error, Record.URL>) -> Result<&2, &2, Error, Record.URL>:
  match result:
    case Fail{reason}: Fail{InvalidURL{reason}}
    case Done{value}: Done{value}

# Inheritance copies immutable normalized components. Every reference replaces
# the fragment, including an empty reference (which removes it).
def fragment(base: Record.URL, value: Maybe<&2, String>) -> Record.URL:
  match base:
    case Record.URL{scheme, user, password, host, port, urlPath, query, _}: Record.URL{scheme, user, password, host, port, urlPath, query, value}

def query(base: Record.URL, parsed: Query.Parsed) -> Record.URL:
  match base parsed:
    case Record.URL{scheme, user, password, host, port, urlPath, _, _} Query.Parsed{value, hash}: Record.URL{scheme, user, password, host, port, urlPath, Some{value}, hash}

def path(base: Record.URL, parsed: Path.Parsed) -> Record.URL:
  match base:
    case Record.URL{scheme, user, password, host, port, _, _, _}: Absolute.hierarchical(scheme, user, password, host, port, parsed)

def scheme(base: Record.URL) -> Scheme.Scheme:
  match base:
    case Record.URL{value, _, _, _, _, _, _, _}: value

def segments(base: Record.URL) -> List<&2, String>:
  match base:
    case Record.URL{_, _, _, _, _, Record.Hierarchical{values}, _, _}: values
    case _: Nil{}

def driveBoundary(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, _}: U32.is_eq(code, 47) || U32.is_eq(code, 92) || U32.is_eq(code, 63) || U32.is_eq(code, 35)

# This is a drive prefix only at a path-component boundary. C:foo is not one.
def startsDrive(text: String) -> Bool:
  match text:
    case SCon{Chr{letter}, SCon{Chr{+separator}, rest}}: Scheme.alpha(letter) && (U32.is_eq(separator, 58) || U32.is_eq(separator, 124)) && driveBoundary(rest)
    case _: False{}

def baseDrive(values: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case +first <> _: Path.retainedDrive(Path.normalizedDrive(first), first)

def rootSegments(file: Bool, newDrive: Bool, base: Record.URL) -> List<&2, String>:
  match file newDrive:
    case True{} False{}: baseDrive(segments(base))
    case _ _: Nil{}

def root(+base: Record.URL, +input: String) -> Record.URL:
  path(base, Path.parse(input, scheme(base), rootSegments(Path.isFile(scheme(base)), startsDrive(input), base)))

def relativeSegments(newDrive: Bool, file: Bool, base: Record.URL) -> List<&2, String>:
  match newDrive file:
    case True{} True{}: Nil{}
    case _ isFile: List.reverse(&2, String, Path.shorten(List.reverse(&2, String, segments(base)), isFile))

def relativePath(+base: Record.URL, +input: String) -> Record.URL:
  path(base, Path.parse(input, scheme(base), relativeSegments(startsDrive(input), Path.isFile(scheme(base)), base)))

def network(context: Absolute.Context, value: Scheme.Scheme, input: String) -> Result<&2, &2, Error, Record.URL>:
  match value:
    case Scheme.File{}: absoluteResult(Absolute.fileAuthority(context, Authority.raw(input, True{})))
    case +other: absoluteResult(Absolute.nonFile(Scheme.isSpecial(other), context, other, "//" ++ input))

# The first slash has already been consumed. Special schemes also treat a
# backslash as a slash; custom schemes preserve it as a path character.
def slash(context: Absolute.Context, +base: Record.URL, input: String, special: Bool) -> Result<&2, &2, Error, Record.URL>:
  match input special:
    case SCon{'/', rest} _: network(context, scheme(base), rest)
    case SCon{'\\', rest} True{}: network(context, scheme(base), rest)
    case rest _: Done{root(base, rest)}

def hierarchical(context: Absolute.Context, +base: Record.URL, input: String, special: Bool) -> Result<&2, &2, Error, Record.URL>:
  match input special:
    case SNil{} _: Done{fragment(base, None{})}
    case SCon{'?', rest} isSpecial: Done{query(base, Query.parse(rest, isSpecial))}
    case SCon{'#', rest} _: Done{fragment(base, Some{Percent.encode(Percent.Fragment{}, rest)})}
    case SCon{'/', rest} isSpecial: slash(context, base, rest, isSpecial)
    case SCon{'\\', rest} True{}: slash(context, base, rest, True{})
    case rest _: Done{relativePath(base, rest)}

def opaque(base: Record.URL, input: String) -> Result<&2, &2, Error, Record.URL>:
  match input:
    case SCon{'#', rest}: Done{fragment(base, Some{Percent.encode(Percent.Fragment{}, rest)})}
    case _: Fail{OpaqueBase{}}

def relative(context: Absolute.Context, +base: Record.URL, input: String) -> Result<&2, &2, Error, Record.URL>:
  match base:
    case Record.URL{_, _, _, _, _, Record.Opaque{_}, _, _}: opaque(base, input)
    case _: hierarchical(context, base, input, Scheme.isSpecial(scheme(base)))

def absoluteOrRelative(sameSpecial: Bool, context: Absolute.Context, base: Record.URL, value: Scheme.Scheme, input: String) -> Result<&2, &2, Error, Record.URL>:
  match sameSpecial:
    case True{}: relative(context, base, input)
    case False{}: absoluteResult(Absolute.scheme(context, value, input))

def prefixed(context: Absolute.Context, +base: Record.URL, prefix: Input.Prefix) -> Result<&2, &2, Error, Record.URL>:
  match prefix:
    case Input.Relative{input}: relative(context, base, input)
    case Input.Absolute{+value, input}: absoluteOrRelative(Scheme.isSpecial(value) && String.eq(Scheme.serialize(value), Scheme.serialize(scheme(base))), context, base, value, input)

# Constructor resolution against an already parsed base. Domain policy remains
# explicit in the same Context as absolute parsing; no host-language URL code.
def parse(context: Absolute.Context, base: Record.URL, input: String) -> Result<&2, &2, Error, Record.URL>:
  prefixed(context, base, Input.prefix(Input.prepare(input)))
