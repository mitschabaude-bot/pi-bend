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
def inverse(+text: String) -> String:
  Bool.pick(String,String.is_empty(text),"","\u{1b}[7m" ++ text ++ "\u{1b}[27m")
def changedWord(+text: String,first: Bool) -> String:
  Bool.pick(Unit -> String,first,
    _ => Tokens.leadingSpace(text) ++ inverse(Tokens.stripLeading(text)),_ => inverse(text))(Unit{})
def prefixMarked(old: String,newer: String,tail: String & String) -> String & String:
  match tail: case (oldTail,newTail): (old ++ oldTail,newer ++ newTail)
def markedWords(spans: List<&2,Tokens.WordSpan>,firstOld: Bool,firstNew: Bool) -> String & String:
  match spans:
    case Nil{}: ("", "")
    case Tokens.WordSpan{Tokens.Same{},+text} <> rest:
      prefixMarked(text,text,markedWords(rest,firstOld,firstNew))
    case Tokens.WordSpan{Tokens.Removed{},text} <> rest:
      prefixMarked(changedWord(text,firstOld),"",markedWords(rest,False{},firstNew))
    case Tokens.WordSpan{Tokens.Added{},text} <> rest:
      prefixMarked("",changedWord(text,firstNew),markedWords(rest,firstOld,False{}))
def markedPair(before: String,after: String) -> String & String:
  markedWords(Tokens.diffWords(before,after),True{},True{})
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
