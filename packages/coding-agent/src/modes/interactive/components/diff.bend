import Base
import ../theme/theme.bend as Theme
import ./messages.bend as Messages
import ../../../core/tools/diff.bend as Tokens

type Line is Data: Line{prefix: Char,lineNum: String,content: String}
def white(char: Char) -> Bool:
  match char: case Chr{code}: Tokens.wordSpace(code)
def digit(char: Char) -> Bool:
  match char: case Chr{+code}: U32.is_ge(code,48) && U32.is_le(code,57)
def singleLine(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{'\n',_}: False{}
    case SCon{'\r',_}: False{}
    case SCon{Chr{8232},_}: False{}
    case SCon{Chr{8233},_}: False{}
    case SCon{_,rest}: singleLine(rest)
def parsedBody(prefix: Char,reversed: String,+body: String) -> Maybe<&2,Line>:
  Bool.pick(Maybe<&2,Line>,singleLine(body),Some{Line{prefix,String.reverse(reversed),body}},None{})
def separator(+prefix: Char,+reversed: String,+rest: String) -> Maybe<&2,Line>:
  match rest:
    case SCon{+char,body}: Bool.pick(Maybe<&2,Line>,white(char),parsedBody(prefix,reversed,body),None{})
    case SNil{}: None{}
def digits(+rest: String,+prefix: Char,+reversed: String) -> Maybe<&2,Line>:
  match rest:
    case SCon{+char,+tail}: Bool.pick(Unit -> Maybe<&2,Line>,digit(char),
      _ => digits(tail,prefix,SCon{char,reversed}),_ => separator(prefix,reversed,rest))(Unit{})
    case SNil{}: None{}
def noDigits(prefix: Char,reversed: String,body: String) -> Maybe<&2,Line>:
  match reversed:
    case SNil{}: None{}
    case SCon{_,number}: parsedBody(prefix,number,body)
def digitsOrBody(parsed: Maybe<&2,Line>,prefix: Char,reversed: String,body: String) -> Maybe<&2,Line>:
  match parsed:
    case Some{line}: Some{line}
    case None{}: noDigits(prefix,reversed,body)
def afterWhitespace(+prefix: Char,+reversed: String,+rest: String) -> Maybe<&2,Line>:
  match rest:
    case SCon{char,_}: Bool.pick(Unit -> Maybe<&2,Line>,digit(char),
      _ => digitsOrBody(digits(rest,prefix,reversed),prefix,reversed,rest),_ => noDigits(prefix,reversed,rest))(Unit{})
    case SNil{}: noDigits(prefix,reversed,rest)
def leading(+rest: String,+prefix: Char,+reversed: String) -> Maybe<&2,Line>:
  match rest:
    case SCon{+char,+tail}: Bool.pick(Unit -> Maybe<&2,Line>,white(char),
      _ => leading(tail,prefix,SCon{char,reversed}),_ => afterWhitespace(prefix,reversed,rest))(Unit{})
    case SNil{}: afterWhitespace(prefix,reversed,rest)
def parseDiffLine(line: String) -> Maybe<&2,Line>:
  match line:
    case SCon{+prefix,+rest}: Bool.pick(Unit -> Maybe<&2,Line>,Char.is_eq(prefix,'-') || Char.is_eq(prefix,'+') || white(prefix),
      _ => leading(rest,prefix,""),_ => None{})(Unit{})
    case SNil{}: None{}
def replaceTabs(text: String) -> String: String.join(String.split(text,'\t'),"   ")
def source(line: Line) -> String:
  match line: case Line{+prefix,number,content}: SCon{Bool.pick(Char,Char.is_eq(prefix,'-') || Char.is_eq(prefix,'+'),prefix,' '),SNil{}} ++ number ++ " " ++ replaceTabs(content)
def role(line: Line) -> String:
  match line:
    case Line{'-',_,_}: "toolDiffRemoved"
    case Line{'+',_,_}: "toolDiffAdded"
    case _: "toolDiffContext"
type Group is Data: Group{lines: List<&2,Line>,rest: List<&2,String>}
def belongs(parsed: Maybe<&2,Line>,prefix: Char) -> Bool:
  match parsed:
    case Some{Line{tag,_,_}}: Char.is_eq(tag,prefix)
    case None{}: False{}
def prependParsed(parsed: Maybe<&2,Line>,reversed: List<&2,Line>) -> List<&2,Line>:
  match parsed:
    case Some{line}: line <> reversed
    case None{}: reversed
def takeGroup(+lines: List<&2,String>,+prefix: Char,+reversed: List<&2,Line>) -> Group:
  match lines:
    case Nil{}: Group{List.reverse(&2,Line,reversed),Nil{}}
    case line <> +tail:
      +parsed = parseDiffLine(line)
      Bool.pick(Unit -> Group,belongs(parsed,prefix),
        _ => takeGroup(tail,prefix,prependParsed(parsed,reversed)),
        _ => Group{List.reverse(&2,Line,reversed),lines})(Unit{})
def commonLengthFrom(a: String,b: String,+count: Nat) -> Nat:
  match a b:
    case SCon{left,restLeft} SCon{right,restRight}:
      Bool.pick(Unit -> Nat,Char.is_eq(left,right),_ => commonLengthFrom(restLeft,restRight,count + 1n),_ => count)(Unit{})
    case _ _: count
def commonLength(a: String,b: String) -> Nat: commonLengthFrom(a,b,0n)
def wordBoundary(+text: String,+index: Nat) -> Bool:
  Nat.is_eq(index,0n) || Nat.is_eq(index,String.length(text)) || String.ends_with(String.take(text,index)," ") || String.starts_with(String.drop(text,index)," ") || String.ends_with(String.take(text,index),"\t") || String.starts_with(String.drop(text,index),"\t")
def space(+char: Char) -> Bool: Char.is_eq(char,' ') || Char.is_eq(char,'\t')
def lastSpaceEnd(chars: String,+index: Nat,last: Nat) -> Nat:
  match chars:
    case SNil{}: last
    case SCon{char,rest}: lastSpaceEnd(rest,index + 1n,Bool.pick(Nat,space(char),index + 1n,last))
def firstSpace(chars: String,+index: Nat) -> Maybe<&2,Nat>:
  match chars:
    case SNil{}: None{}
    case SCon{char,rest}: Bool.pick(Unit -> Maybe<&2,Nat>,space(char),_ => Some{index},_ => firstSpace(rest,index + 1n))(Unit{})
def suffixAfterSpace(found: Maybe<&2,Nat>,count: Nat) -> Nat:
  match found:
    case Some{position}: count - position
    case None{}: 0n
def alignedPrefix(+before: String,+after: String,+count: Nat) -> Nat:
  Bool.pick(Nat,wordBoundary(before,count) && wordBoundary(after,count),count,lastSpaceEnd(String.take(before,count),0n,0n))
def alignedSuffix(+before: String,+after: String,+count: Nat) -> Nat:
  Bool.pick(Nat,wordBoundary(before,String.length(before) - count) && wordBoundary(after,String.length(after) - count),count,
    suffixAfterSpace(firstSpace(String.take(String.drop(before,String.length(before) - count),count),0n),count))
def highlight(+content: String,+prefix: Nat,+suffix: Nat) -> String:
  +middle = String.take(String.drop(content,prefix),String.length(content) - prefix - suffix)
  Bool.pick(String,String.is_empty(middle),content,
    String.take(content,prefix) ++ "\u{1b}[7m" ++ middle ++ "\u{1b}[27m" ++ String.drop(content,String.length(content) - suffix))
def markedPair(+before: String,+after: String) -> String & String:
  +prefix = alignedPrefix(before,after,commonLength(before,after))
  +suffix = alignedSuffix(before,after,commonLength(String.reverse(String.drop(before,prefix)),String.reverse(String.drop(after,prefix))))
  (highlight(before,prefix,suffix),highlight(after,prefix,suffix))
def paintLine(+line: Line,theme: Theme.Theme) -> IO(String):
  Messages.foregroundText(theme,role(line),source(line))
def paintLines(lines: List<&2,Line>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,reversed)
    case line <> rest:
      do IO<List<&2,String>>:
        painted : String <- paintLine(line,theme)
        paintLines(rest,theme,painted <> reversed)
def paintedPair(marked: String & String,oldNumber: String,newNumber: String,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match marked:
    case (oldMarked,newMarked):
      do IO<List<&2,String>>:
        oldLine : String <- Messages.foregroundText(theme,"toolDiffRemoved","-" ++ oldNumber ++ " " ++ oldMarked)
        newLine : String <- Messages.foregroundText(theme,"toolDiffAdded","+" ++ newNumber ++ " " ++ newMarked)
        return newLine <> (oldLine <> reversed)
def pair(removed: Line,added: Line,theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match removed added:
    case Line{_,oldNumber,oldContent} Line{_,newNumber,newContent}:
      paintedPair(markedPair(replaceTabs(oldContent),replaceTabs(newContent)),oldNumber,newNumber,theme,reversed)
def paintGroup(removed: List<&2,Line>,added: List<&2,Line>,+theme: Theme.Theme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match removed added:
    case old <> Nil{} newer <> Nil{}: pair(old,newer,theme,reversed)
    case old newer:
      do IO<List<&2,String>>:
        first : List<&2,String> <- paintLines(old,theme,reversed)
        paintLines(newer,theme,first)
type Pending is Data: Pending{lines: List<&2,String>,reversed: List<&2,String>}
def paintedBlocks(removed: Group,added: Group,theme: Theme.Theme,reversed: List<&2,String>) -> IO(Pending):
  match removed added:
    case Group{old,_} Group{newer,rest}:
      do IO<Pending>:
        output : List<&2,String> <- paintGroup(old,newer,theme,reversed)
        return Pending{rest,output}
def removedBlock(+removed: Group,theme: Theme.Theme,reversed: List<&2,String>) -> IO(Pending):
  match removed:
    case Group{_,remaining}: paintedBlocks(removed,takeGroup(remaining,'+',Nil{}),theme,reversed)
def renderStep(parsed: Maybe<&2,Line>,lines: List<&2,String>,theme: Theme.Theme,reversed: List<&2,String>) -> IO(Pending):
  match parsed lines:
    case Some{Line{'-',_,_}} lines: removedBlock(takeGroup(lines,'-',Nil{}),theme,reversed)
    case Some{line} _ <> rest:
      do IO<Pending>:
        painted : String <- paintLine(line,theme)
        return Pending{rest,painted <> reversed}
    case None{} line <> rest:
      do IO<Pending>:
        painted : String <- Messages.foregroundText(theme,"toolDiffContext",line)
        return Pending{rest,painted <> reversed}
    case _ Nil{}: IO.pure(Pending,Pending{Nil{},reversed})
def renderLines(fuel: Nat,state: Pending,+theme: Theme.Theme) -> IO(List<&2,String>):
  match fuel state:
    case Zero{} Pending{_,reversed}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case _ Pending{Nil{},reversed}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case Succ{left} Pending{+line <> rest,reversed}:
      do IO<List<&2,String>>:
        next : Pending <- renderStep(parseDiffLine(line),line <> rest,theme,reversed)
        renderLines(left,next,theme)
def renderDiff(diff: String,theme: Theme.Theme) -> IO(String):
  do IO<String>:
    +source : List<&2,String> = String.split(diff,'\n')
    lines : List<&2,String> <- renderLines(List.length(&2,String,source),Pending{source,Nil{}},theme)
    return String.join(lines,"\n")
