import Base
import ../packages/coding-agent/src/core/tools/edit-diff.bend as Edit
import ../packages/runtime/src/unicode-17-compatibility.bend as Unicode
import ../packages/runtime/src/string.bend as Strings
import ../packages/runtime/test/utf8-runner.bend as Wire

def text(encoded: String) -> String: Wire.fromScalars(Wire.parseNumbers(encoded))

def edits(fields: List<&2,String>) -> List<&2,Edit.Edit>:
  match fields:
    case oldText <> newText <> rest: Edit.Edit{text(oldText),text(newText)} <> edits(rest)
    case _: Nil{}

def applied(result: Result<&2,&2,Edit.Error,Edit.AppliedEditsResult>, count: Nat) -> String:
  match result:
    case Fail{error}: "error|" ++ Edit.errorMessage(error,"file.txt",count)
    case Done{Edit.AppliedEditsResult{base,new}}: "ok|" ++ Wire.showText(base) ++ "|" ++ Wire.showText(new)

def found(result: Edit.FuzzyMatchResult) -> String:
  match result:
    case Edit.Missing{content}: "missing|" ++ Wire.showText(content)
    case Edit.Found{index,size,fuzzy,content}: Nat.show(index) ++ "|" ++ Nat.show(size) ++ "|" ++ Bool.show(fuzzy) ++ "|" ++ Wire.showText(content)

def replacements(fields: List<&2,String>) -> List<&2,Edit.TextReplacement>:
  match fields:
    case index <> size <> value <> rest: Edit.TextReplacement{U32.to_nat(Wire.decimal(index,0)),U32.to_nat(Wire.decimal(size,0)),text(value)} <> replacements(rest)
    case _: Nil{}

def preserved(result: Result<&2,&2,Edit.Error,String>) -> String:
  match result:
    case Fail{error}: "error|" ++ Edit.errorMessage(error,"file.txt",0n)
    case Done{value}: "ok|" ++ Wire.showText(value)

def repeat(count: Nat, +char: Char, result: String) -> String:
  match count:
    case Zero{}: result
    case Succ{rest}: repeat(rest,char,SCon{char,result})

def longResult(result: Result<&2,&2,Edit.Error,Edit.AppliedEditsResult>) -> String:
  match result:
    case Fail{error}: Edit.errorMessage(error,"file.txt",1n)
    case Done{Edit.AppliedEditsResult{_,value}}: Nat.show(Edit.length(value,0n))

def run(parts: List<&2,String>) -> String:
  match parts:
    case "g" <> count <> Nil{}:
      +size = U32.to_nat(Wire.decimal(count,0))
      longResult(Edit.applyEditsToNormalizedContent(repeat(size,'a',"TARGET" ++ repeat(size,'z',"")),Edit.Edit{"TARGET","X"} <> Nil{}))
    case "n" <> value <> Nil{}: Wire.showText(Unicode.nfkc(text(value)))
    case "f" <> value <> Nil{}: Wire.showText(Edit.normalizeForFuzzyMatch(text(value)))
    case "m" <> content <> oldText <> Nil{}: found(Edit.fuzzyFindText(text(content),text(oldText)))
    case "l" <> value <> ending <> Nil{}:
      +source = text(value)
      Wire.showText(Edit.detectLineEnding(source)) ++ "|" ++ Wire.showText(Edit.normalizeToLF(source)) ++ "|" ++ Wire.showText(Edit.restoreLineEndings(source,text(ending)))
    case "e" <> content <> fields:
      +values = edits(fields)
      applied(Edit.applyEditsToNormalizedContent(text(content),values),List.length(&2,Edit.Edit,values))
    case "p" <> original <> base <> fields: preserved(Edit.applyReplacementsPreservingUnchangedLines(text(original),text(base),replacements(fields)))
    case _: "invalid fixture input"

def all(arguments: List<String>) -> IO(Unit):
  match arguments:
    case Nil{}: IO.pure(Unit,Unit{})
    case argument <> rest:
      do IO<Unit>:
        IO.print(run(Strings.split(argument,'|')))
        all(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    arguments : List<String> <- IO.args()
    all(arguments)
