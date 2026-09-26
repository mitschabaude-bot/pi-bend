import Base
import ../packages/coding-agent/src/core/tools/edit-diff.bend as Edits
import ../packages/coding-agent/src/core/tools/diff.bend as Diff
import ../packages/coding-agent/src/utils/paths.bend as Paths
import ../packages/runtime/src/url.bend as URL
import ../packages/runtime/src/idna.bend as IDNA
import ../packages/runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../packages/runtime/src/unicode-17-normalization.bend as Normalization
import ../packages/runtime/src/unicode-17-idna-properties.bend as Properties
import ../packages/runtime/src/json.bend as Json

def environment(cwd: String,home: String) -> Paths.Environment:
  Paths.Environment{cwd,home,URL.Context{IDNA.Context{Mapping.table(),Normalization.tables(),Properties.table()},IDNA.Options{IDNA.LabelOptions{False{},False{},True{},IDNA.Nontransitional{}},True{},False{}}}}
def replacements(args: List<String>) -> List<&2,Edits.Edit>:
  match args:
    case old <> new <> rest: Edits.Edit{old,new} <> replacements(rest)
    case _: Nil{}
def line(value: Maybe<&2,Nat>) -> String:
  match value:
    case None{}: "null"
    case Some{number}: Nat.show(number)
def report(result: Edits.Preview()) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("{\"error\":" ++ Json.quote(message) ++ "}")
    case Done{Diff.DiffResult{diff,first}}: IO.print("{\"diff\":" ++ Json.quote(diff) ++ ",\"firstChangedLine\":" ++ line(first) ++ "}")
def run(args: List<String>) -> IO(Unit):
  match args:
    case +cwd <> home <> path <> rest:
      do IO<Unit>:
        result : Edits.Preview() <- Edits.computeEditsDiff(environment(cwd,home),path,replacements(rest),cwd)
        report(result)
    case _: IO.die(Unit,1,"usage: edit-preview cwd home path [old new ...]")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
