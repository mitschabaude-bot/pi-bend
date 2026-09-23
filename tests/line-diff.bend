import Base
import ../packages/coding-agent/src/core/tools/diff.bend as D
import ../packages/runtime/src/json.bend as Json

def first(value: Maybe<&2,Nat>) -> String:
  match value:
    case None{}: "null"
    case Some{number}: Nat.show(number)

def result(value: D.DiffResult) -> String:
  match value:
    case D.DiffResult{text,line}: "[" ++ Json.quote(text) ++ "," ++ first(line) ++ "]"

def changes(values: List<&2,D.Change>) -> String:
  match values:
    case Nil{}: ""
    case D.Change{kind,lines} <> rest:
      "[" ++ Json.quote(D.prefix(kind)) ++ "," ++ Json.quote(String.concat(lines)) ++ "]," ++ changes(rest)

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case +old <> +newer <> +context <> +path <> rest:
      do IO<Unit>:
        IO.print("[" ++ result(D.generateDiffString(old,newer,String.length(context))) ++ "," ++ Json.quote(D.generateUnifiedPatch(path,old,newer,String.length(context))) ++ ",[" ++ changes(D.diffLines(old,newer)) ++ "null]]")
        run(rest)
    case _: IO.die(Unit,1,"expected old, new, context (length), path")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
