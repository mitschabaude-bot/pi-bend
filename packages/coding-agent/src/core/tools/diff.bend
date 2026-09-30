import Base
import ../../../../runtime/src/string.bend as Strings

# Line tokens retain their terminator, including CRLF and a missing final LF.
type ChangeKind is Data:
  Same{}
  Added{}
  Removed{}

type Change is Data:
  Change{kind: ChangeKind, lines: List<&2,String>}

type DiffResult is Data:
  DiffResult{diff: String, firstChangedLine: Maybe<&2,Nat>}

def tokenize(text: String, +reversed: String, +lines: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}:
      List.reverse(&2,String,Bool.pick(List<&2,String>,Strings.equal(reversed,""),lines,String.reverse(reversed) <> lines))
    case SCon{'\n',rest}: tokenize(rest,"",String.reverse(SCon{'\n',reversed}) <> lines)
    case SCon{char,rest}: tokenize(rest,SCon{char,reversed},lines)

def sameKind(left: ChangeKind, right: ChangeKind) -> Bool:
  match left right:
    case Same{} Same{}: True{}
    case Added{} Added{}: True{}
    case Removed{} Removed{}: True{}
    case _ _: False{}

def record(+kind: ChangeKind, +line: String, history: List<&2,Change>) -> List<&2,Change>:
  match history:
    case Nil{}: Change{kind,line <> Nil{}} <> Nil{}
    case Change{+previous,+lines} <> +rest:
      Bool.pick(List<&2,Change>,sameKind(kind,previous),Change{kind,line <> lines} <> rest,Change{kind,line <> Nil{}} <> Change{previous,lines} <> rest)

type Path is Data:
  Path{old: List<&2,String>, newer: List<&2,String>, oldPosition: Nat, history: List<&2,Change>}

def common(old: List<&2,String>, newer: List<&2,String>, +position: Nat, +history: List<&2,Change>) -> Path:
  match old newer:
    case +left <> +rest +right <> +tail:
      Bool.pick(Unit -> Path,Strings.equal(left,right),
        unused => common(rest,tail,1n+position,record(Same{},right,history)),
        unused => Path{left <> rest,right <> tail,position,history})(Unit{})
    case left right: Path{left,right,position,history}

def insertion(path: Maybe<&2,Path>) -> Maybe<&2,Path>:
  match path:
    case Some{Path{old,line <> newer,position,history}}: Some{Path{old,newer,position,record(Added{},line,history)}}
    case _: None{}

def deletion(path: Maybe<&2,Path>) -> Maybe<&2,Path>:
  match path:
    case Some{Path{line <> old,newer,position,history}}: Some{Path{old,newer,1n+position,record(Removed{},line,history)}}
    case _: None{}

# Compare positions BEFORE deletion: jsdiff chooses deletion on ties.
def branch(removed: Maybe<&2,Path>, added: Maybe<&2,Path>) -> Maybe<&2,Path>:
  match removed added:
    case None{} value: value
    case value None{}: value
    case Some{Path{+old,+newer,+position,+history}} Some{Path{+a,+b,+other,+h}}:
      Some{Bool.pick(Path,Nat.is_le(position,other),Path{a,b,other,h},Path{old,newer,position,history})}

def extend(path: Maybe<&2,Path>) -> Maybe<&2,Path>:
  match path:
    case None{}: None{}
    case Some{Path{old,newer,position,history}}: Some{common(old,newer,position,history)}

# Once a path reaches an edge, an impossible neighboring diagonal is discarded.
# Trimming absent edge paths keeps pure append/delete workloads linear in D.
def trim(paths: List<&2,Maybe<&2,Path>>) -> List<&2,Maybe<&2,Path>>:
  match paths:
    case None{} <> rest: trim(rest)
    case values: values

def diagonal(rights: List<&2,Maybe<&2,Path>>, left: Maybe<&2,Path>, reversed: List<&2,Maybe<&2,Path>>) -> List<&2,Maybe<&2,Path>>:
  match rights:
    case Nil{}: trim(List.reverse(&2,Maybe<&2,Path>,trim(reversed)))
    case +right <> rest:
      diagonal(rest,right,extend(branch(deletion(left),insertion(right))) <> reversed)

def finished(paths: List<&2,Maybe<&2,Path>>) -> Maybe<&2,List<&2,Change>>:
  match paths:
    case Nil{}: None{}
    case Some{Path{Nil{},Nil{},_,history}} <> _: Some{history}
    case _ <> rest: finished(rest)

def search(fuel: Nat, paths: List<&2,Maybe<&2,Path>>, result: Maybe<&2,List<&2,Change>>) -> List<&2,Change>:
  match fuel result:
    case _ Some{history}: history
    case 0n None{}: Nil{}
    case 1n+fuel None{}:
      +next = diagonal(List.append(&2,Maybe<&2,Path>,paths,None{} <> Nil{}),None{},Nil{})
      search(fuel,next,finished(next))

def ordered(changes: List<&2,Change>, result: List<&2,Change>) -> List<&2,Change>:
  match changes:
    case Nil{}: result
    case Change{kind,lines} <> rest: ordered(rest,Change{kind,List.reverse(&2,String,lines)} <> result)

# Myers shortest-edit search: O((N+M)D) time, persistent shared path histories.
# Remaining input tails provide constant-time movement without indexed arrays.
def diffTokens(+left: List<&2,String>,+right: List<&2,String>) -> List<&2,Change>:
  +paths = {Some{common(left,right,0n,Nil{})} <> Nil{} : List<&2,Maybe<&2,Path>>}
  ordered(search(List.length(&2,String,left) + List.length(&2,String,right),paths,finished(paths)),Nil{})
def diffLines(old: String,newer: String) -> List<&2,Change>:
  diffTokens(tokenize(old,"",Nil{}),tokenize(newer,"",Nil{}))

# Default jsdiff word matching ignores surrounding whitespace.
def wordChar(+code: U32) -> Bool:
  (U32.is_ge(code,48) && U32.is_le(code,57)) || (U32.is_ge(code,65) && U32.is_le(code,90)) ||
  (U32.is_ge(code,97) && U32.is_le(code,122)) || U32.is_eq(code,95) || U32.is_eq(code,173) ||
  (U32.is_ge(code,192) && U32.is_le(code,214)) || (U32.is_ge(code,216) && U32.is_le(code,246)) ||
  (U32.is_ge(code,248) && U32.is_le(code,710)) || (U32.is_ge(code,712) && U32.is_le(code,727)) ||
  (U32.is_ge(code,734) && U32.is_le(code,767)) || (U32.is_ge(code,7680) && U32.is_le(code,7935))
def wordSpace(+code: U32) -> Bool:
  (U32.is_ge(code,9) && U32.is_le(code,13)) || U32.is_eq(code,32) || U32.is_eq(code,160) || U32.is_eq(code,5760) ||
  (U32.is_ge(code,8192) && U32.is_le(code,8202)) || U32.is_eq(code,8232) || U32.is_eq(code,8233) ||
  U32.is_eq(code,8239) || U32.is_eq(code,8287) || U32.is_eq(code,12288) || U32.is_eq(code,65279)
def finishWord(word: String,keys: List<&2,String>) -> List<&2,String>:
  match word:
    case SNil{}: keys
    case word: String.reverse(word) <> keys
def scanWords(text: String,+word: String,+keys: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,finishWord(word,keys))
    case SCon{Chr{+code},+rest}:
      Bool.pick(Unit -> List<&2,String>,wordChar(code),
        _ => scanWords(rest,SCon{Chr{code},word},keys),
        _ => Bool.pick(Unit -> List<&2,String>,wordSpace(code),
          _ => scanWords(rest,"",finishWord(word,keys)),
          _ => scanWords(rest,"",SCon{Chr{code},SNil{}} <> finishWord(word,keys)))(Unit{}))(Unit{})
def whitespaceWord(keys: List<&2,String>) -> List<&2,String>:
  match keys:
    case Nil{}: "" <> Nil{}
    case keys: keys
def wordKeys(text: String) -> List<&2,String>:
  match text:
    case SNil{}: Nil{}
    case text: whitespaceWord(scanWords(text,"",Nil{}))
def diffWordKeys(old: String,newer: String) -> List<&2,Change>:
  diffTokens(wordKeys(old),wordKeys(newer))

# Display tokens include the surrounding whitespace on both adjacent words.
# Matching uses trimmed keys; these tokens recover the selected source text.
type WordSpan is Data: WordSpan{kind: ChangeKind,text: String}
def leadingSpace(text: String) -> String:
  match text:
    case SCon{+char,+rest}: Bool.pick(Unit -> String,wordSpace(Char.to_u32(char)),_ => SCon{char,leadingSpace(rest)},_ => "")(Unit{})
    case SNil{}: ""
def stripLeading(+text: String) -> String: String.drop(text,String.length(leadingSpace(text)))
def trailingSpace(text: String) -> String: String.reverse(leadingSpace(String.reverse(text)))
def tokenClass(+char: Char) -> Nat:
  Bool.pick(Nat,wordSpace(Char.to_u32(char)),0n,Bool.pick(Nat,wordChar(Char.to_u32(char)),1n,2n))
def wordParts(text: String,+kind: Nat,+current: String,+reversed: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,finishWord(current,reversed))
    case SCon{+char,+rest}:
      +next = tokenClass(char)
      Bool.pick(Unit -> List<&2,String>,Nat.is_eq(kind,next) && Bool.not(Nat.is_eq(next,2n)),
        _ => wordParts(rest,next,SCon{char,current},reversed),
        _ => wordParts(rest,next,SCon{char,""},finishWord(current,reversed)))(Unit{})
def appendWordSpace(space: String,reversed: List<&2,String>) -> List<&2,String>:
  match reversed:
    case Nil{}: space <> Nil{}
    case word <> rest: (word ++ space) <> rest
def prependWordSpace(+word: String,+space: String,+reversed: List<&2,String>) -> List<&2,String>:
  match reversed:
    case +previous <> rest: Bool.pick(List<&2,String>,Strings.equal(previous,space),(space ++ word) <> rest,(space ++ word) <> reversed)
    case Nil{}: (space ++ word) <> Nil{}
def stitchWords(parts: List<&2,String>,+space: String,+reversed: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: List.reverse(&2,String,reversed)
    case +part <> +rest:
      Bool.pick(Unit -> List<&2,String>,String.is_empty(stripLeading(part)),
        _ => stitchWords(rest,part,appendWordSpace(part,reversed)),
        _ => stitchWords(rest,"",prependWordSpace(part,space,reversed)))(Unit{})
def wordDisplayTokens(text: String) -> List<&2,String>:
  stitchWords(wordParts(text,2n,"",Nil{}),"",Nil{})
def joinWordTail(tokens: List<&2,String>) -> String:
  match tokens:
    case Nil{}: ""
    case token <> rest: stripLeading(token) ++ joinWordTail(rest)
def stripMaybeLeading(value: Maybe<&2,String>) -> Maybe<&2,String>:
  match value:
    case None{}: None{}
    case Some{text}: Some{stripLeading(text)}
def joinWordTokens(tokens: List<&2,String>) -> String:
  match tokens:
    case Nil{}: ""
    case first <> rest: first ++ joinWordTail(rest)
def wordSpans(changes: List<&2,Change>,+old: List<&2,String>,+newer: List<&2,String>) -> List<&2,WordSpan>:
  match changes:
    case Nil{}: Nil{}
    case Change{Removed{},keys} <> rest:
      +n = List.length(&2,String,keys)
      WordSpan{Removed{},joinWordTokens(List.take(&2,String,old,n))} <> wordSpans(rest,List.drop(&2,String,old,n),newer)
    case Change{Added{},keys} <> rest:
      +n = List.length(&2,String,keys)
      WordSpan{Added{},joinWordTokens(List.take(&2,String,newer,n))} <> wordSpans(rest,old,List.drop(&2,String,newer,n))
    case Change{Same{},keys} <> rest:
      +n = List.length(&2,String,keys)
      WordSpan{Same{},joinWordTokens(List.take(&2,String,newer,n))} <> wordSpans(rest,List.drop(&2,String,old,n),List.drop(&2,String,newer,n))

def commonPrefix(a: String,b: String) -> String:
  match a b:
    case SCon{+left,rest} SCon{right,tail}: Bool.pick(Unit -> String,Char.is_eq(left,right),_ => SCon{left,commonPrefix(rest,tail)},_ => "")(Unit{})
    case _ _: ""
def commonSuffix(a: String,b: String) -> String: String.reverse(commonPrefix(String.reverse(a),String.reverse(b)))
def removePrefix(text: String,prefix: String) -> String: String.drop(text,String.length(prefix))
def removeSuffix(+text: String,suffix: String) -> String: String.take(text,String.length(text) - String.length(suffix))
def overlap(+a: String,+b: String,+n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+ +k: Bool.pick(Unit -> String,Strings.equal(String.drop(a,String.length(a) - n),String.take(b,n)),_ => String.take(b,n),_ => overlap(a,b,k))(Unit{})
def whitespaceOverlap(+a: String,+b: String) -> String: overlap(a,b,Nat.min(String.length(a),String.length(b)))
# A change block lies between two common spans, either of which may be absent.
# Keep that boundary explicit rather than mutating adjacent change objects.
type WordBlock is Data: WordBlock{before: Maybe<&2,String>,removed: Maybe<&2,String>,added: Maybe<&2,String>,after: Maybe<&2,String>}
def tidyReplacement(before: Maybe<&2,String>,+old: String,+newer: String,after: Maybe<&2,String>,+prefix: String,+suffix: String) -> WordBlock:
  match before after:
    case Some{start} Some{+end}: WordBlock{Some{removeSuffix(start,leadingSpace(newer)) ++ prefix},Some{removeSuffix(removePrefix(old,prefix),suffix)},Some{removeSuffix(removePrefix(newer,prefix),suffix)},Some{suffix ++ removePrefix(end,leadingSpace(end))}}
    case Some{start} None{}: WordBlock{Some{removeSuffix(start,leadingSpace(newer)) ++ prefix},Some{removePrefix(old,prefix)},Some{removePrefix(newer,prefix)},None{}}
    case None{} Some{+end}: WordBlock{None{},Some{removeSuffix(old,suffix)},Some{removeSuffix(newer,suffix)},Some{suffix ++ removePrefix(end,leadingSpace(end))}}
    case None{} None{}: WordBlock{None{},Some{old},Some{newer},None{}}
def tidyWordBlock(block: WordBlock) -> WordBlock:
  match block:
    case WordBlock{before,Some{+old},Some{+newer},after}:
      +prefix = commonPrefix(leadingSpace(old),leadingSpace(newer))
      +suffix = commonSuffix(trailingSpace(old),trailingSpace(newer))
      tidyReplacement(before,old,newer,after,prefix,suffix)
    case WordBlock{Some{before},None{},Some{newer},after}:
      WordBlock{Some{before},None{},Some{stripLeading(newer)},stripMaybeLeading(after)}
    case WordBlock{None{},None{},Some{newer},after}:
      WordBlock{None{},None{},Some{newer},stripMaybeLeading(after)}
    case WordBlock{Some{+before},Some{+old},None{},Some{+after}}:
      +full = leadingSpace(after)
      +prefix = commonPrefix(full,leadingSpace(old))
      +suffix = commonSuffix(removePrefix(full,prefix),trailingSpace(old))
      WordBlock{Some{removeSuffix(before,full) ++ removeSuffix(full,suffix)},Some{removeSuffix(removePrefix(old,prefix),suffix)},None{},Some{suffix ++ removePrefix(after,full)}}
    case WordBlock{None{},Some{+old},None{},Some{+after}}:
      WordBlock{None{},Some{removeSuffix(old,whitespaceOverlap(trailingSpace(old),leadingSpace(after)))},None{},Some{after}}
    case WordBlock{Some{+before},Some{+old},None{},None{}}:
      WordBlock{Some{before},Some{removePrefix(old,whitespaceOverlap(trailingSpace(before),leadingSpace(old)))},None{},None{}}
    case block: block

def maybeSpan(kind: ChangeKind,value: Maybe<&2,String>,rest: List<&2,WordSpan>) -> List<&2,WordSpan>:
  match value:
    case None{}: rest
    case Some{text}: WordSpan{kind,text} <> rest
type WordWalk is Data:
  Gather{before: Maybe<&2,String>,removed: Maybe<&2,String>,added: Maybe<&2,String>}
  Emit{block: WordBlock}
def collectWordBlock(block: WordBlock,reversed: List<&2,WordSpan>) -> List<&2,WordSpan>:
  match block:
    case WordBlock{start,old,newer,_}: maybeSpan(Added{},newer,maybeSpan(Removed{},old,maybeSpan(Same{},start,reversed)))
def tidyWordSpans(fuel: Nat,walk: WordWalk,spans: List<&2,WordSpan>,+reversed: List<&2,WordSpan>) -> List<&2,WordSpan>:
  match fuel walk spans:
    case 0n _ _: List.reverse(&2,WordSpan,reversed)
    case 1n+left Gather{before,removed,added} WordSpan{Removed{},text} <> rest: tidyWordSpans(left,Gather{before,Some{text},added},rest,reversed)
    case 1n+left Gather{before,removed,added} WordSpan{Added{},text} <> rest: tidyWordSpans(left,Gather{before,removed,Some{text}},rest,reversed)
    case 1n+left Gather{before,removed,added} WordSpan{Same{},text} <> rest: tidyWordSpans(left,Emit{tidyWordBlock(WordBlock{before,removed,added,Some{text}})},rest,reversed)
    case 1n+left Gather{before,removed,added} Nil{}: tidyWordSpans(left,Emit{tidyWordBlock(WordBlock{before,removed,added,None{}})},Nil{},reversed)
    case 1n+left Emit{WordBlock{start,old,newer,Some{+end}}} rest: tidyWordSpans(left,Gather{Some{end},None{},None{}},rest,collectWordBlock(WordBlock{start,old,newer,Some{end}},reversed))
    case _ Emit{block} _: List.reverse(&2,WordSpan,collectWordBlock(block,reversed))
def displayWordKey(text: String,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}: Bool.pick(Unit -> String,wordSpace(Char.to_u32(char)),
      _ => String.reverse(reversed),_ => displayWordKey(rest,SCon{char,reversed}))(Unit{})
def displayWordKeys(tokens: List<&2,String>) -> List<&2,String>:
  match tokens:
    case Nil{}: Nil{}
    case token <> rest: displayWordKey(stripLeading(token),"") <> displayWordKeys(rest)
def diffWords(old: String,newer: String) -> List<&2,WordSpan>:
  +oldTokens = wordDisplayTokens(old)
  +newTokens = wordDisplayTokens(newer)
  +spans = wordSpans(diffTokens(displayWordKeys(oldTokens),displayWordKeys(newTokens)),oldTokens,newTokens)
  tidyWordSpans(List.length(&2,WordSpan,spans) * 2n + 2n,Gather{None{},None{},None{}},spans,Nil{})

def size(lines: List<&2,String>) -> Nat: List.length(&2,String,lines)

def prefix(kind: ChangeKind) -> String:
  match kind:
    case Same{}: " "
    case Added{}: "+"
    case Removed{}: "-"

def stripLast(text: String) -> String:
  match text:
    case SCon{'\n',rest}: String.reverse(rest)
    case value: String.reverse(value)

def stripLf(text: String) -> String:
  stripLast(String.reverse(text))

def spaces(count: Nat) -> String:
  match count:
    case 0n: ""
    case 1n+rest: SCon{' ',spaces(rest)}

def displayLines(lines: List<&2,String>, +kind: ChangeKind, +number: Nat, +width: Nat, output: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: output
    case line <> rest:
      +digits = Nat.show(number)
      displayLines(rest,kind,1n+number,width,(prefix(kind) ++ spaces(width - String.length(digits)) ++ digits ++ " " ++ stripLf(line)) <> output)

def isChange(changes: List<&2,Change>) -> Bool:
  match changes:
    case Change{Same{},_} <> _: False{}
    case Nil{}: False{}
    case _: True{}

def firstLine(previous: Maybe<&2,Nat>, line: Nat) -> Maybe<&2,Nat>:
  match previous:
    case None{}: Some{line}
    case value: value

def contextDisplay(+lines: List<&2,String>, before: Bool, after: Bool, +context: Nat, +number: Nat, +width: Nat, +output: List<&2,String>) -> List<&2,String>:
  match before after:
    case False{} False{}: output
    case True{} True{}:
      Bool.pick(Unit -> List<&2,String>,Nat.is_le(size(lines),context + context),
        unused => displayLines(lines,Same{},number,width,output),
        unused => displayLines(List.drop(&2,String,lines,size(lines) - context),Same{},number + size(lines) - context,width,
          (" " ++ spaces(width) ++ " ...") <> displayLines(List.take(&2,String,lines,context),Same{},number,width,output)))(Unit{})
    case True{} False{}:
      +shown = displayLines(List.take(&2,String,lines,context),Same{},number,width,output)
      Bool.pick(List<&2,String>,Nat.is_gt(size(lines),context),(" " ++ spaces(width) ++ " ...") <> shown,shown)
    case False{} True{}:
      +skip = size(lines) - context
      displayLines(List.drop(&2,String,lines,skip),Same{},number + skip,width,
        Bool.pick(List<&2,String>,Nat.is_gt(skip,0n),(" " ++ spaces(width) ++ " ...") <> output,output))

def display(changes: List<&2,Change>, +context: Nat, +width: Nat, +old: Nat, +newer: Nat, before: Bool, first: Maybe<&2,Nat>, output: List<&2,String>) -> DiffResult:
  match changes:
    case Nil{}: DiffResult{String.join(List.reverse(&2,String,output),"\n"),first}
    case Change{Same{},+lines} <> +rest:
      display(rest,context,width,old + size(lines),newer + size(lines),False{},first,contextDisplay(lines,before,isChange(rest),context,old,width,output))
    case Change{Added{},+lines} <> rest:
      display(rest,context,width,old,newer + size(lines),True{},firstLine(first,newer),displayLines(lines,Added{},newer,width,output))
    case Change{Removed{},+lines} <> rest:
      display(rest,context,width,old + size(lines),newer,True{},firstLine(first,newer),displayLines(lines,Removed{},old,width,output))

def lineCount(text: String, count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{'\n',rest}: lineCount(rest,1n+count)
    case SCon{_,rest}: lineCount(rest,count)

def generateDiffString(+oldContent: String, +newContent: String, contextLines: Nat) -> DiffResult:
  +oldCount = lineCount(oldContent,1n)
  +newCount = lineCount(newContent,1n)
  width = String.length(Nat.show(Bool.pick(Nat,Nat.is_ge(oldCount,newCount),oldCount,newCount)))
  display(diffLines(oldContent,newContent),contextLines,width,1n,1n,False{},None{},Nil{})

# Hunk coordinates count source lines, never the synthetic EOF marker.
type Hunk is Data:
  Hunk{oldStart: Nat, newStart: Nat, oldCount: Nat, newCount: Nat, reversed: List<&2,String>}

def patchLines(lines: List<&2,String>, +kind: ChangeKind, +output: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: output
    case +line <> rest:
      +text = prefix(kind) ++ stripLf(line)
      patchLines(rest,kind,Bool.pick(List<&2,String>,Strings.equal(line,stripLf(line)),"\\ No newline at end of file" <> text <> output,text <> output))

def grow(kind: ChangeKind, +lines: List<&2,String>, hunk: Hunk) -> Hunk:
  match kind hunk:
    case Added{} Hunk{a,b,c,d,output}: Hunk{a,b,c,d + size(lines),patchLines(lines,Added{},output)}
    case Removed{} Hunk{a,b,c,d,output}: Hunk{a,b,c + size(lines),d,patchLines(lines,Removed{},output)}
    case Same{} Hunk{a,b,c,d,output}: Hunk{a,b,c + size(lines),d + size(lines),patchLines(lines,Same{},output)}

def begin(hunk: Maybe<&2,Hunk>, +previous: List<&2,String>, +context: Nat, old: Nat, newer: Nat) -> Hunk:
  match hunk:
    case Some{value}: value
    case None{}:
      +leading = List.drop(&2,String,previous,size(previous) - context)
      grow(Same{},leading,Hunk{old - size(leading),newer - size(leading),0n,0n,Nil{}})

def renderHunk(hunk: Hunk) -> String:
  match hunk:
    case Hunk{a,b,+c,+d,output}:
      "@@ -" ++ Nat.show(a - Bool.pick(Nat,Nat.is_eq(c,0n),1n,0n)) ++ "," ++ Nat.show(c) ++
      " +" ++ Nat.show(b - Bool.pick(Nat,Nat.is_eq(d,0n),1n,0n)) ++ "," ++ Nat.show(d) ++ " @@\n" ++
      String.join(List.reverse(&2,String,output),"\n") ++ "\n"

type PatchState is Data:
  PatchState{active: Maybe<&2,Hunk>, reversed: List<&2,String>}

def close(state: PatchState) -> PatchState:
  match state:
    case PatchState{None{},output}: PatchState{None{},output}
    case PatchState{Some{hunk},output}: PatchState{None{},renderHunk(hunk) <> output}

def changed(kind: ChangeKind, lines: List<&2,String>, previous: List<&2,String>, context: Nat, old: Nat, newer: Nat, state: PatchState) -> PatchState:
  match state:
    case PatchState{hunk,output}: PatchState{Some{grow(kind,lines,begin(hunk,previous,context,old,newer))},output}

def unchanged(+lines: List<&2,String>, more: Bool, +context: Nat, state: PatchState) -> PatchState:
  match state:
    case PatchState{None{},output}: PatchState{None{},output}
    case PatchState{Some{+hunk},+output}:
      Bool.pick(Unit -> PatchState,Bool.and(more,Nat.is_le(size(lines),context + context)),
        unused => PatchState{Some{grow(Same{},lines,hunk)},output},
        unused => close(PatchState{Some{grow(Same{},List.take(&2,String,lines,context),hunk)},output}))(Unit{})

def patch(changes: List<&2,Change>, previous: List<&2,String>, +context: Nat, +old: Nat, +newer: Nat, state: PatchState) -> PatchState:
  match changes:
    case Nil{}: close(state)
    case Change{Same{},+lines} <> +rest:
      patch(rest,lines,context,old + size(lines),newer + size(lines),unchanged(lines,isChange(rest),context,state))
    case Change{Added{},+lines} <> rest:
      patch(rest,Nil{},context,old,newer + size(lines),changed(Added{},lines,previous,context,old,newer,state))
    case Change{Removed{},+lines} <> rest:
      patch(rest,Nil{},context,old + size(lines),newer,changed(Removed{},lines,previous,context,old,newer,state))

def patchText(state: PatchState) -> String:
  match state:
    case PatchState{_,output}: String.concat(List.reverse(&2,String,output))

def generateUnifiedPatch(+path: String, oldContent: String, newContent: String, contextLines: Nat) -> String:
  "--- " ++ path ++ "\n+++ " ++ path ++ "\n" ++ patchText(patch(diffLines(oldContent,newContent),Nil{},contextLines,1n,1n,PatchState{None{},Nil{}}))
