import Base

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
      List.reverse(&2,String,Bool.pick(List<&2,String>,String.eq(reversed,""),lines,String.reverse(reversed) <> lines))
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
      Bool.pick(Unit -> Path,String.eq(left,right),
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
def diffLines(old: String, newer: String) -> List<&2,Change>:
  +left = tokenize(old,"",Nil{})
  +right = tokenize(newer,"",Nil{})
  +paths = {Some{common(left,right,0n,Nil{})} <> Nil{} : List<&2,Maybe<&2,Path>>}
  ordered(search(List.length(&2,String,left) + List.length(&2,String,right),paths,finished(paths)),Nil{})

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
      patchLines(rest,kind,Bool.pick(List<&2,String>,String.eq(line,stripLf(line)),"\\ No newline at end of file" <> text <> output,text <> output))

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
