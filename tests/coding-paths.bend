import Base
import ../packages/coding-agent/src/utils/paths.bend as P
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as Wire

def text(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: String.reverse(reversed)
    case "" <> rest: text(rest, reversed)
    case head <> rest: text(rest, SCon{Chr{Wire.decimal(head, 0)}, reversed})

def decode(value: String) -> String:
  text(Strings.split(value, ','), "")

def override(value: String) -> Maybe<&2, String>:
  match value:
    case "-": None{}
    case other: Some{decode(other)}

def result(value: Result<&2, &2, P.Error, String>) -> String:
  match value:
    case Done{path}: "+" ++ Wire.showText(path)
    case Fail{_}: "!"

def evaluate(+environment: P.Environment, +input: String, base: String, mode: String, +options: P.PathInputOptions) -> String:
  result(Bool.pick(Unit -> Result<&2, &2, P.Error, String>, String.eq(mode, "n"), _ => P.normalizePath(environment, input, options), _ => P.resolvePath(environment, input, base, options))(Unit{}))

def run(context: URL.Context, fields: List<&2, String>) -> String:
  match fields:
    case mode <> cwd <> home <> input <> base <> trimming <> tilde <> selectedHome <> strip <> spaces <> Nil{}:
      evaluate(P.Environment{decode(cwd), decode(home), context}, decode(input), decode(base), mode, P.PathInputOptions{String.eq(trimming, "1"), String.eq(tilde, "1"), override(selectedHome), String.eq(strip, "1"), String.eq(spaces, "1")})
    case _: "bad fixture arguments"

def cases(args: List<String>, +context: URL.Context) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case first <> rest:
      do IO<Unit>:
        IO.print(run(context, Strings.split(first, '|')))
        cases(rest, context)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    cases(args, URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}})
