import Base
import ../../../../runtime/src/string.bend as Strings
import ../../../../runtime/src/stable-sort.bend as Sort
import ../../../../runtime/src/unicode-17-compatibility.bend as Unicode

# Positions count Bend characters, not UTF-16 code units. All matching and
# replacement offsets refer to the same immutable content snapshot.
type Edit is Data:
  Edit{oldText: String, newText: String}
type AppliedEditsResult is Data:
  AppliedEditsResult{baseContent: String, newContent: String}
type FuzzyMatchResult is Data:
  Missing{contentForReplacement: String}
  Found{index: Nat, matchLength: Nat, usedFuzzyMatch: Bool, contentForReplacement: String}
type TextReplacement is Data:
  TextReplacement{matchIndex: Nat, matchLength: Nat, newText: String}
type Error is Data:
  EmptyOldText{editIndex: Nat}
  NotFound{editIndex: Nat}
  Duplicate{editIndex: Nat, occurrences: Nat}
  Overlap{previous: Nat, current: Nat}
  NoChange{}
  LineCountMismatch{}
  OutOfRange{}

def detectLineEnding(+content: String) -> String:
  match content:
    case SCon{'\r',SCon{'\n',_}}: "\r\n"
    case SCon{'\n',_}: "\n"
    case SCon{_,rest}: detectLineEnding(rest)
    case SNil{}: "\n"

def normalizeLines(+text: String, +reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\r',SCon{'\n',rest}}: normalizeLines(rest,SCon{'\n',reversed})
    case SCon{'\r',rest}: normalizeLines(rest,SCon{'\n',reversed})
    case SCon{char,rest}: normalizeLines(rest,SCon{char,reversed})

def normalizeToLF(+text: String) -> String: normalizeLines(text,"")

def restore(+text: String, +ending: String, +reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\n',rest}: restore(rest,ending,String.reverse(ending) ++ reversed)
    case SCon{char,rest}: restore(rest,ending,SCon{char,reversed})

def restoreLineEndings(text: String, ending: String) -> String:
  match ending:
    case "\r\n": restore(text,"\r\n","")
    case _: text

# ECMAScript trimEnd's whitespace set; NFKC precedes trimming and punctuation.
def whitespace(+code: U32) -> Bool:
  (U32.is_ge(code,9) && U32.is_le(code,13)) || U32.is_eq(code,32) || U32.is_eq(code,160) || U32.is_eq(code,5760) ||
  (U32.is_ge(code,8192) && U32.is_le(code,8202)) || U32.is_eq(code,8232) || U32.is_eq(code,8233) ||
  U32.is_eq(code,8239) || U32.is_eq(code,8287) || U32.is_eq(code,12288) || U32.is_eq(code,65279)

def punctuation(+code: U32) -> U32:
  Bool.pick(U32,U32.is_ge(code,8216) && U32.is_le(code,8219),39,
    Bool.pick(U32,U32.is_ge(code,8220) && U32.is_le(code,8223),34,
      Bool.pick(U32,(U32.is_ge(code,8208) && U32.is_le(code,8213)) || U32.is_eq(code,8722),45,
        Bool.pick(U32,U32.is_eq(code,160) || (U32.is_ge(code,8194) && U32.is_le(code,8202)) || U32.is_eq(code,8239) || U32.is_eq(code,8287) || U32.is_eq(code,12288),32,code))))

# Pending whitespace is flushed only when another character follows on its line.
# This avoids splitting/joining the whole document just to trim line endings.
type FuzzyState is Data:
  FuzzyState{pending: String, reversed: String}

def fuzzyStep(+newline: Bool, +space: Bool, +code: U32, +pending: String, +reversed: String) -> FuzzyState:
  match newline space:
    case True{} _: FuzzyState{"",SCon{'\n',reversed}}
    case False{} True{}: FuzzyState{SCon{Chr{punctuation(code)},pending},reversed}
    case False{} False{}: FuzzyState{"",SCon{Chr{punctuation(code)},pending ++ reversed}}

def fuzzyScan(+text: String, +state: FuzzyState) -> String:
  match text state:
    case SNil{} FuzzyState{_,reversed}: String.reverse(reversed)
    case SCon{Chr{+code},rest} FuzzyState{pending,reversed}: fuzzyScan(rest,fuzzyStep(U32.is_eq(code,10),whitespace(code),code,pending,reversed))

def normalizeForFuzzyMatch(+text: String) -> String: fuzzyScan(Unicode.nfkc(text),FuzzyState{"",""})

def length(+text: String, +count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{_,rest}: length(rest,Succ{count})

def find(+text: String, +needle: String, +index: Nat, +found: Maybe<&2,Nat>) -> Maybe<&2,Nat>:
  match text found:
    case _ Some{offset}: Some{offset}
    case SNil{} None{}: Bool.pick(Maybe<&2,Nat>,String.is_empty(needle),Some{index},None{})
    case SCon{+char,+rest} None{}:
      find(rest,needle,Succ{index},Bool.pick(Maybe<&2,Nat>,String.starts_with(SCon{char,rest},needle),Some{index},None{}))

def fuzzyFound(+index: Maybe<&2,Nat>, +needle: String, +base: String, +original: String) -> FuzzyMatchResult:
  match index:
    case None{}: Missing{original}
    case Some{offset}: Found{offset,length(needle,0n),True{},base}

def fuzzySearch(+empty: Bool, +base: String, +needle: String, +original: String) -> FuzzyMatchResult:
  match empty:
    case True{}: Missing{original}
    case False{}: fuzzyFound(find(base,needle,0n,None{}),needle,base,original)

def exactFound(+index: Maybe<&2,Nat>, +content: String, +oldText: String) -> FuzzyMatchResult:
  match index:
    case Some{offset}: Found{offset,length(oldText,0n),False{},content}
    case None{}:
      +needle = normalizeForFuzzyMatch(oldText)
      fuzzySearch(String.is_empty(needle),normalizeForFuzzyMatch(content),needle,content)

def fuzzyFindText(+content: String, +oldText: String) -> FuzzyMatchResult:
  exactFound(find(content,oldText,0n,None{}),content,oldText)

# Non-overlapping occurrences, as in pi's uniqueness check. A whitespace-only
# exact needle is counted literally; an empty fuzzy needle never inserts text.
def occurrences(+text: String, +needle: String, +size: Nat, +skip: Nat, +count: Nat) -> Nat:
  match text skip:
    case SNil{} _: count
    case SCon{_,rest} Succ{remaining}: occurrences(rest,needle,size,remaining,count)
    case SCon{+char,+rest} Zero{}:
      +found = String.starts_with(SCon{char,rest},needle)
      occurrences(rest,needle,size,Bool.pick(Nat,found,Nat.sub(size,1n),0n),Bool.pick(Nat,found,Succ{count},count))

def countChoice(+empty: Bool, +content: String, +oldText: String, +base: String, +needle: String) -> Nat:
  match empty:
    case True{}: occurrences(content,oldText,length(oldText,0n),0n,0n)
    case False{}: occurrences(base,needle,length(needle,0n),0n,0n)

def countOccurrences(+content: String, +oldText: String) -> Nat:
  +needle = normalizeForFuzzyMatch(oldText)
  countChoice(String.is_empty(needle),content,oldText,normalizeForFuzzyMatch(content),needle)

# Tail-recursive output construction keeps large untouched spans off the machine
# stack and copies each source segment only once before the final reversal.
def prepend(text: String, reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{char,rest}: prepend(rest,SCon{char,reversed})

def prefix(text: String, count: Nat, reversed: String) -> String:
  match text count:
    case SNil{} _: reversed
    case _ Zero{}: reversed
    case SCon{char,rest} Succ{remaining}: prefix(rest,remaining,SCon{char,reversed})

# Replacements are sorted and disjoint. Replacement text never becomes a target
# for a subsequent edit: offsets always address the immutable source snapshot.
def applyReplacements(replacements: List<&2,TextReplacement>, +content: String, offset: Nat, reversed: String) -> String:
  match replacements:
    case Nil{}: String.reverse(prepend(content,reversed))
    case TextReplacement{+index,+size,newText} <> rest:
      +gap = Nat.sub(index,offset)
      applyReplacements(rest,String.drop(content,Nat.add(gap,size)),Nat.add(index,size),prepend(newText,prefix(content,gap,reversed)))

type Line is Data:
  Line{start: Nat, end: Nat, text: String}
type Range is Data:
  Range{startLine: Nat, endLine: Nat, start: Nat, end: Nat}
type Group is Data:
  Group{range: Range, reversed: List<&2,TextReplacement>}

def lines(+text: String, +start: Nat, +offset: Nat, +reversed: String, +result: List<&2,Line>) -> List<&2,Line>:
  match text reversed:
    case SNil{} SNil{}: List.reverse(&2,Line,result)
    case SNil{} value: List.reverse(&2,Line,Line{start,offset,String.reverse(value)} <> result)
    case SCon{'\n',rest} value: lines(rest,Succ{offset},Succ{offset},"",Line{start,Succ{offset},String.reverse(SCon{'\n',value})} <> result)
    case SCon{char,rest} value: lines(rest,start,Succ{offset},SCon{char,value},result)

type RangeState is Data:
  Seeking{}
  Started{first: Nat, start: Nat}
  Complete{range: Range}

def rangeStep(+contains: Bool, +reaches: Bool, +index: Nat, +start: Nat, +end: Nat, +state: RangeState) -> RangeState:
  match contains reaches state:
    case True{} True{} Seeking{}: Complete{Range{index,Succ{index},start,end}}
    case True{} False{} Seeking{}: Started{index,start}
    case False{} _ Seeking{}: Seeking{}
    case _ True{} Started{first,offset}: Complete{Range{first,Succ{index},offset,end}}
    case _ False{} Started{first,offset}: Started{first,offset}
    case _ _ Complete{range}: Complete{range}

def lineRange(+lines: List<&2,Line>, +start: Nat, +stop: Nat, +index: Nat, +state: RangeState) -> Result<&2,&2,Error,Range>:
  match lines state:
    case _ Complete{range}: Done{range}
    case Nil{} _: Fail{OutOfRange{}}
    case Line{+a,+b,_} <> rest previous:
      lineRange(rest,start,stop,Succ{index},rangeStep(Nat.is_ge(start,a) && Nat.is_lt(start,b),Nat.is_ge(b,stop),index,a,b,previous))

def grouped(+overlaps: Bool, +replacement: TextReplacement, +range: Range, +current: Group, +rest: List<&2,Group>) -> List<&2,Group>:
  match overlaps range current:
    case True{} Range{_,+last,_,+end} Group{Range{first,+previous,start,+stop},values}:
      Group{Range{first,Bool.pick(Nat,Nat.is_gt(last,previous),last,previous),start,Bool.pick(Nat,Nat.is_gt(end,stop),end,stop)},replacement <> values} <> rest
    case False{} range group: Group{range,replacement <> Nil{}} <> group <> rest

def addGroup(+replacement: TextReplacement, +range: Range, +groups: List<&2,Group>) -> List<&2,Group>:
  match range groups:
    case range Nil{}: Group{range,replacement <> Nil{}} <> Nil{}
    case Range{+first,last,start,end} Group{Range{a,+b,c,d},values} <> rest:
      grouped(Nat.is_lt(first,b),replacement,Range{first,last,start,end},Group{Range{a,b,c,d},values},rest)

def groupResult(+result: Result<&2,&2,Error,Range>, +replacement: TextReplacement, +groups: List<&2,Group>) -> Result<&2,&2,Error,List<&2,Group>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{range}: Done{addGroup(replacement,range,groups)}

def groupReplacements(+replacements: List<&2,TextReplacement>, +lines: List<&2,Line>, +result: Result<&2,&2,Error,List<&2,Group>>) -> Result<&2,&2,Error,List<&2,Group>>:
  match replacements result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{groups}: Done{List.reverse(&2,Group,groups)}
    case TextReplacement{+index,+size,text} <> rest Done{groups}:
      groupReplacements(rest,lines,groupResult(lineRange(lines,index,Nat.add(index,size),0n,Seeking{}),TextReplacement{index,size,text},groups))

def joinLines(lines: List<&2,Line>, reversed: String) -> String:
  match lines:
    case Nil{}: reversed
    case Line{_,_,text} <> rest: joinLines(rest,prepend(text,reversed))

def prefixLines(lines: List<&2,Line>, count: Nat, reversed: String) -> String:
  match lines count:
    case Nil{} _: reversed
    case _ Zero{}: reversed
    case Line{_,_,text} <> rest Succ{remaining}: prefixLines(rest,remaining,prepend(text,reversed))

def preserve(groups: List<&2,Group>, +original: List<&2,Line>, +base: String, +previous: Nat, reversed: String) -> String:
  match groups:
    case Nil{}: String.reverse(joinLines(original,reversed))
    case Group{Range{first,+last,+start,end},changes} <> rest:
      unchanged = prefixLines(original,Nat.sub(first,previous),reversed)
      block = String.reverse(prefix(String.drop(base,start),Nat.sub(end,start),""))
      updated = applyReplacements(List.reverse(&2,TextReplacement,changes),block,start,"")
      preserve(rest,List.drop(&2,Line,original,Nat.sub(last,previous)),base,last,prepend(updated,unchanged))

def preserved(+result: Result<&2,&2,Error,List<&2,Group>>, +original: List<&2,Line>, +base: String) -> Result<&2,&2,Error,String>:
  match result:
    case Fail{error}: Fail{error}
    case Done{groups}: Done{preserve(groups,original,base,0n,"")}

def replacementBefore(left: TextReplacement, right: TextReplacement) -> Bool:
  match left right:
    case TextReplacement{a,_,_} TextReplacement{b,_,_}: Nat.is_le(a,b)

def preserveChecked(+sameLines: Bool, +original: List<&2,Line>, +baseLines: List<&2,Line>, +base: String, +replacements: List<&2,TextReplacement>) -> Result<&2,&2,Error,String>:
  match sameLines:
    case False{}: Fail{LineCountMismatch{}}
    case True{}: preserved(groupReplacements(Sort.sort(~TextReplacement,~replacementBefore,replacements),baseLines,Done{Nil{}}),original,base)

def applyReplacementsPreservingUnchangedLines(+originalContent: String, +baseContent: String, +replacements: List<&2,TextReplacement>) -> Result<&2,&2,Error,String>:
  +original = lines(originalContent,0n,0n,"",Nil{})
  +base = lines(baseContent,0n,0n,"",Nil{})
  preserveChecked(Nat.is_eq(Sort.length(Line,original,0n),Sort.length(Line,base,0n)),original,base,baseContent,replacements)

type MatchedEdit is Data:
  MatchedEdit{editIndex: Nat, replacement: TextReplacement}

def normalizedEdits(+edits: List<&2,Edit>) -> List<&2,Edit>:
  match edits:
    case Nil{}: Nil{}
    case Edit{oldText,newText} <> rest: Edit{normalizeToLF(oldText),normalizeToLF(newText)} <> normalizedEdits(rest)

def emptyEdit(+edits: List<&2,Edit>, +index: Nat) -> Maybe<&2,Nat>:
  match edits:
    case Nil{}: None{}
    case Edit{SNil{},_} <> _: Some{index}
    case _ <> rest: emptyEdit(rest,Succ{index})

def usedFuzzy(+result: FuzzyMatchResult) -> Bool:
  match result:
    case Found{_,_,fuzzy,_}: fuzzy
    case Missing{_}: False{}

def anyFuzzy(+edits: List<&2,Edit>, +content: String, +found: Bool) -> Bool:
  match edits found:
    case _ True{}: True{}
    case Nil{} False{}: False{}
    case Edit{oldText,_} <> rest False{}: anyFuzzy(rest,content,usedFuzzy(fuzzyFindText(content,oldText)))

def unique(+duplicate: Bool, +count: Nat, +index: Nat, +replacement: TextReplacement) -> Result<&2,&2,Error,MatchedEdit>:
  match duplicate:
    case True{}: Fail{Duplicate{index,count}}
    case False{}: Done{MatchedEdit{index,replacement}}

def matched(+result: FuzzyMatchResult, +content: String, +oldText: String, +newText: String, +index: Nat) -> Result<&2,&2,Error,MatchedEdit>:
  match result:
    case Missing{_}: Fail{NotFound{index}}
    case Found{offset,size,_,_}:
      +count = countOccurrences(content,oldText)
      unique(Nat.is_gt(count,1n),count,index,TextReplacement{offset,size,newText})

def appendMatched(+result: Result<&2,&2,Error,MatchedEdit>, +previous: List<&2,MatchedEdit>) -> Result<&2,&2,Error,List<&2,MatchedEdit>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{edit}: Done{edit <> previous}

def matchEdits(+edits: List<&2,Edit>, +content: String, +index: Nat, +result: Result<&2,&2,Error,List<&2,MatchedEdit>>) -> Result<&2,&2,Error,List<&2,MatchedEdit>>:
  match edits result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{previous}: Done{List.reverse(&2,MatchedEdit,previous)}
    case Edit{+oldText,newText} <> rest Done{previous}:
      matchEdits(rest,content,Succ{index},appendMatched(matched(fuzzyFindText(content,oldText),content,oldText,newText,index),previous))

def editBefore(left: MatchedEdit, right: MatchedEdit) -> Bool:
  match left right:
    case MatchedEdit{_,a} MatchedEdit{_,b}: replacementBefore(a,b)

def overlapPair(previous: MatchedEdit, next: List<&2,MatchedEdit>) -> Maybe<&2,Error>:
  match previous next:
    case MatchedEdit{a,TextReplacement{start,size,_}} MatchedEdit{b,TextReplacement{offset,_,_}} <> _:
      Bool.pick(Maybe<&2,Error>,Nat.is_gt(Nat.add(start,size),offset),Some{Overlap{a,b}},None{})
    case _ Nil{}: None{}

def firstOverlap(previous: Maybe<&2,Error>, next: Maybe<&2,Error>) -> Maybe<&2,Error>:
  match previous:
    case Some{error}: Some{error}
    case None{}: next

def overlaps(edits: List<&2,MatchedEdit>) -> Maybe<&2,Error>:
  match edits:
    case Nil{}: None{}
    case first <> +rest: firstOverlap(overlapPair(first,rest),overlaps(rest))

def replacements(+edits: List<&2,MatchedEdit>) -> List<&2,TextReplacement>:
  match edits:
    case Nil{}: Nil{}
    case MatchedEdit{_,replacement} <> rest: replacement <> replacements(rest)

def changed(+result: Result<&2,&2,Error,String>, +original: String) -> Result<&2,&2,Error,AppliedEditsResult>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+text}: Bool.pick(Result<&2,&2,Error,AppliedEditsResult>,Strings.equal(original,text),Fail{NoChange{}},Done{AppliedEditsResult{original,text}})

def applyMatched(+fuzzy: Bool, +original: String, +base: String, +edits: List<&2,TextReplacement>) -> Result<&2,&2,Error,AppliedEditsResult>:
  match fuzzy:
    case True{}: changed(applyReplacementsPreservingUnchangedLines(original,base,edits),original)
    case False{}: changed(Done{applyReplacements(edits,base,0n,"")},original)

def disjoint(+error: Maybe<&2,Error>, +fuzzy: Bool, +original: String, +base: String, +edits: List<&2,MatchedEdit>) -> Result<&2,&2,Error,AppliedEditsResult>:
  match error:
    case Some{cause}: Fail{cause}
    case None{}: applyMatched(fuzzy,original,base,replacements(edits))

def ordered(+result: Result<&2,&2,Error,List<&2,MatchedEdit>>, +fuzzy: Bool, +original: String, +base: String) -> Result<&2,&2,Error,AppliedEditsResult>:
  match result:
    case Fail{error}: Fail{error}
    case Done{edits}:
      +sorted = Sort.sort(~MatchedEdit,~editBefore,edits)
      disjoint(overlaps(sorted),fuzzy,original,base,sorted)

def withBase(fuzzy: Bool, +original: String, edits: List<&2,Edit>) -> Result<&2,&2,Error,AppliedEditsResult>:
  match fuzzy:
    case True{}:
      +base = normalizeForFuzzyMatch(original)
      ordered(matchEdits(edits,base,0n,Done{Nil{}}),True{},original,base)
    case False{}: ordered(matchEdits(edits,original,0n,Done{Nil{}}),False{},original,original)

def validated(+empty: Maybe<&2,Nat>, +content: String, +edits: List<&2,Edit>) -> Result<&2,&2,Error,AppliedEditsResult>:
  match empty:
    case Some{index}: Fail{EmptyOldText{index}}
    case None{}: withBase(anyFuzzy(edits,content,False{}),content,edits)

# Match every edit before applying any, and report the first invalid edit in
# caller order. Path rendering is separate from this typed, transactional core.
def applyEditsToNormalizedContent(+content: String, +edits: List<&2,Edit>) -> Result<&2,&2,Error,AppliedEditsResult>:
  +normalized = normalizedEdits(edits)
  validated(emptyEdit(normalized,0n),content,normalized)

def errorMessage(+error: Error, +path: String, +totalEdits: Nat) -> String:
  match error:
    case EmptyOldText{index}: Bool.pick(String,Nat.is_eq(totalEdits,1n),"oldText", "edits[" ++ Nat.show(index) ++ "].oldText") ++ " must not be empty in " ++ path ++ "."
    case NotFound{index}: Bool.pick(String,Nat.is_eq(totalEdits,1n),
      "Could not find the exact text in " ++ path ++ ". The old text must match exactly including all whitespace and newlines.",
      "Could not find edits[" ++ Nat.show(index) ++ "] in " ++ path ++ ". The oldText must match exactly including all whitespace and newlines.")
    case Duplicate{index,+count}: Bool.pick(String,Nat.is_eq(totalEdits,1n),
      "Found " ++ Nat.show(count) ++ " occurrences of the text in " ++ path ++ ". The text must be unique. Please provide more context to make it unique.",
      "Found " ++ Nat.show(count) ++ " occurrences of edits[" ++ Nat.show(index) ++ "] in " ++ path ++ ". Each oldText must be unique. Please provide more context to make it unique.")
    case Overlap{previous,current}: "edits[" ++ Nat.show(previous) ++ "] and edits[" ++ Nat.show(current) ++ "] overlap in " ++ path ++ ". Merge them into one edit or target disjoint regions."
    case NoChange{}: Bool.pick(String,Nat.is_eq(totalEdits,1n),
      "No changes made to " ++ path ++ ". The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected.",
      "No changes made to " ++ path ++ ". The replacements produced identical content.")
    case LineCountMismatch{}: "Cannot preserve unchanged lines because the base content has a different line count."
    case OutOfRange{}: "Replacement range is outside the base content."
