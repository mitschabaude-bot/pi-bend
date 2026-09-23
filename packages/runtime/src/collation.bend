import Base
import ./u32-table.bend as Table
import ./stable-sort.bend as Sort
import ./filesystem.bend as FS

# String.prototype.localeCompare exactly as Node 24 (ICU 78.3, CLDR 48 root,
# en-US default options: tertiary, non-ignorable, V8's normalization mode).
# The engine ports ICU's FCDUTF16CollationIterator and contraction matching,
# including its quirks: FCD input is collated unnormalized, and look-ahead
# that backs up across a normalized run re-segments it backwards. Weights are
# dense ranks from packages/runtime/data/icu78-collation.bin.
type Weight is Data: Weight{primary: U32,lower: U32}
type Suffix is Data: Suffix{codes: List<&2,U32>,weights: List<&2,Weight>}
type Prefix is Data: Prefix{code: U32,weights: List<&2,Weight>}
type Mapping is Data:
  Run{first: U32,last: U32,primary: U32,lower: U32}
  Expansion{code: U32,weights: List<&2,Weight>}
  Contraction{code: U32,trailing: Bool,single: Bool,fallback: List<&2,Weight>,suffixes: List<&2,Suffix>}
  Prefixed{code: U32,fallback: List<&2,Weight>,prefixes: List<&2,Prefix>}
type Span is Data: Span{first: U32,last: U32,value: U32}
type Collator is Data: Collator{mappings: Table.Table<Mapping>,han: Table.Table<Span>,classes: Table.Table<Span>,fcd: Table.Table<Span>,decompositions: Table.Table<List<&2,U32>>,leads: Table.Table<U32>,hanBase: U32,unassignedBase: U32,common: U32}

# A comparison key: the collation elements, possibly ending in a cycle that
# repeats forever (ICU's iterator can loop on pathological non-FCD input).
type Key is Data: Key{prefix: List<&2,Weight>,cycle: List<&2,Weight>}

# ---- Code point properties

def spanHit(found: Maybe<&2,Span>,+code: U32) -> U32:
  match found:
    case None{}: 0
    case Some{Span{_,last,value}}: Bool.pick(U32,U32.is_le(code,last),value,0)
def spanAt(table: Table.Table<Span>,+code: U32) -> U32: spanHit(Table.floor(Span,table,code),code)
def fcdOf(collator: Collator,+code: U32) -> U32:
  match collator:
    case Collator{_,_,_,table,_,_,_,_,_}: spanAt(table,code)
def classOf(collator: Collator,+code: U32) -> U32:
  match collator:
    case Collator{_,_,table,_,_,_,_,_,_}: spanAt(table,code)
def leadFlags(collator: Collator,unit: U32) -> U32:
  match collator:
    case Collator{_,_,_,_,_,table,_,_,_}: Maybe.default(&2,U32,Table.get(U32,table,unit),0)
def isLead(+unit: U32) -> Bool: U32.is_ge(unit,55296) && U32.is_lt(unit,56320)
def isTrail(+unit: U32) -> Bool: U32.is_ge(unit,56320) && U32.is_lt(unit,57344)
def firstUnit(+code: U32) -> U32: Bool.pick(U32,U32.is_gt(code,65535),(55232 + code / 1024 : U32),code)
def lastUnit(+code: U32) -> U32: Bool.pick(U32,U32.is_gt(code,65535),(56320 + code % 1024 : U32),code)

# ICU's CollationFCD unit predicates: exact for BMP units, per lead surrogate
# block for supplementary code points, all trail units lccc, none tccc.
# (Selections go through match rather than Bool.pick: native C mishandles a
# boxed Bool.pick result inside && / ||, docs/bend-issues.md.)
def leadsByKind(+collator: Collator,+unit: U32,trail: Bool,lead: Bool) -> Bool:
  match trail lead:
    case True{} _: True{}
    case False{} True{}: U32.is_ne(U32.and(leadFlags(collator,unit),1),0)
    case False{} False{}: U32.is_ge(fcdOf(collator,unit),256)
def unitLeads(+collator: Collator,+unit: U32) -> Bool: U32.is_ge(unit,768) && leadsByKind(collator,unit,isTrail(unit),isLead(unit))
def trailsByKind(+collator: Collator,+unit: U32,trail: Bool,lead: Bool) -> Bool:
  match trail lead:
    case True{} _: False{}
    case False{} True{}: U32.is_ne(U32.and(leadFlags(collator,unit),2),0)
    case False{} False{}: U32.is_ne(U32.and(fcdOf(collator,unit),255),0)
def unitTrails(+collator: Collator,+unit: U32) -> Bool: U32.is_ge(unit,192) && trailsByKind(collator,unit,isTrail(unit),isLead(unit))
def tibetanUnit(unit: U32) -> Bool: U32.is_eq(U32.and(unit,2096897),3841)
def tibetanFcd(+value: U32) -> Bool: U32.is_eq(value,33154) || U32.is_eq(value,33156)

# ---- Text cursors (code points; UTF-16 structure is modelled by the unit predicates)

type Cursor is Data: Cursor{index: U32,before: List<&2,U32>,after: List<&2,U32>}
def headOr(values: List<&2,U32>) -> U32:
  match values:
    case Nil{}: 4294967295
    case code <> _: code
def ahead(cursor: Cursor) -> U32:
  match cursor:
    case Cursor{_,_,after}: headOr(after)
def behind(cursor: Cursor) -> U32:
  match cursor:
    case Cursor{_,before,_}: headOr(before)
def indexOf(cursor: Cursor) -> U32:
  match cursor:
    case Cursor{index,_,_}: index
def stepAhead(cursor: Cursor) -> Cursor:
  match cursor:
    case Cursor{index,before,code <> after}: Cursor{(index + 1 : U32),code <> before,after}
    case other: other
def stepBehind(cursor: Cursor) -> Cursor:
  match cursor:
    case Cursor{index,code <> before,after}: Cursor{(index - 1 : U32),before,code <> after}
    case other: other
def takeReversed(count: Nat,values: List<&2,U32>,reversed: List<&2,U32>) -> List<&2,U32>:
  match count values:
    case Succ{left} value <> rest: takeReversed(left,rest,value <> reversed)
    case _ _: reversed
def prependAll(reversed: List<&2,U32>,values: List<&2,U32>) -> List<&2,U32>:
  match reversed:
    case Nil{}: values
    case value <> rest: prependAll(rest,value <> values)
def seekAhead(steps: Nat,cursor: Cursor) -> Cursor:
  match steps:
    case Zero{}: cursor
    case Succ{left}: seekAhead(left,stepAhead(cursor))
def seekBehind(steps: Nat,cursor: Cursor) -> Cursor:
  match steps:
    case Zero{}: cursor
    case Succ{left}: seekBehind(left,stepBehind(cursor))
def seekChosen(forward: Bool,cursor: Cursor,+index: U32,+target: U32) -> Cursor:
  match forward:
    case True{}: seekAhead(U32.to_nat((target - index : U32)),cursor)
    case False{}: seekBehind(U32.to_nat((index - target : U32)),cursor)
def seek(cursor: Cursor,+target: U32) -> Cursor:
  match cursor:
    case Cursor{+index,before,after}: seekChosen(U32.is_lt(index,target),Cursor{index,before,after},index,target)

# ---- Canonical decomposition of a non-FCD segment (NFD)

def hangulTail(index: U32) -> List<&2,U32>:
  match index:
    case 0: Nil{}
    case other: (4519 + other : U32) <> Nil{}
def hangul(+index: U32) -> List<&2,U32>: (4352 + index / 588 : U32) <> (4449 + index % 588 / 28 : U32) <> hangulTail((index % 28 : U32))
def isSyllable(+code: U32) -> Bool: U32.is_ge(code,44032) && U32.is_lt(code,55204)
def decomposition(collator: Collator,+code: U32) -> List<&2,U32>:
  match collator:
    case Collator{_,_,_,_,table,_,_,_,_}:
      Bool.pick(Unit -> List<&2,U32>,isSyllable(code),_ => hangul((code - 44032 : U32)),
        _ => Maybe.default(&2,List<&2,U32>,Table.get(List<&2,U32>,table,code),code <> Nil{}))(Unit{})
type Mark is Data: Mark{code: U32,class: U32}
def classLe(left: Mark,right: Mark) -> Bool:
  match left right:
    case Mark{_,a} Mark{_,b}: U32.is_le(a,b)
def marked(+collator: Collator,codes: List<&2,U32>,reversed: List<&2,Mark>) -> List<&2,Mark>:
  match codes:
    case Nil{}: reversed
    case +code <> rest: marked(collator,rest,Mark{code,classOf(collator,code)} <> reversed)
def decomposedAll(+collator: Collator,codes: List<&2,U32>,reversed: List<&2,Mark>) -> List<&2,Mark>:
  match codes:
    case Nil{}: List.reverse(&2,Mark,reversed)
    case +code <> rest: decomposedAll(collator,rest,marked(collator,decomposition(collator,code),reversed))
def prependCodes(marks: List<&2,Mark>,cursor: Cursor) -> Cursor:
  match marks cursor:
    case Nil{} cursor: cursor
    case Mark{code,_} <> rest Cursor{index,before,after}: prependCodes(rest,Cursor{(index + 1 : U32),code <> before,after})
def flushRun(run: List<&2,Mark>,cursor: Cursor) -> Cursor:
  match run:
    case Nil{}: cursor
    case mark <> Nil{}: prependCodes(mark <> Nil{},cursor)
    case run: prependCodes(Sort.sort(~Mark,~classLe,List.reverse(&2,Mark,run)),cursor)
# Canonical ordering: a stable sort by class of each run of non-starters.
# The result is a cursor positioned after the last code point.
def ordered(marks: List<&2,Mark>,run: List<&2,Mark>,cursor: Cursor) -> Cursor:
  match marks:
    case Nil{}: flushRun(run,cursor)
    case Mark{code,0} <> rest: ordered(rest,Nil{},prependCodes(Mark{code,0} <> Nil{},flushRun(run,cursor)))
    case mark <> rest: ordered(rest,mark <> run,cursor)

# ---- ICU's FCD iterator. Ahead/Behind check FCD while moving; Stay reads a
# checked raw segment [start, limit); Normal reads the NFD of a non-FCD segment.

type Mode is Data:
  Ahead{segmentStart: U32}
  Behind{segmentLimit: U32}
  Stay{start: U32,limit: U32}
  Normal{buffer: Cursor,length: U32,segmentStart: U32,segmentLimit: U32}
type Iter is Data: Iter{raw: Cursor,rawLimit: U32,mode: Mode}
type Read is Data: Read{iter: Iter,code: U32}
type Turn is Data: Got{read: Read} Again{iter: Iter}

def normalized(+collator: Collator,region: List<&2,U32>) -> Cursor: ordered(decomposedAll(collator,region,Nil{}),Nil{},Cursor{0,Nil{},Nil{}})
def rewound(cursor: Cursor) -> Cursor:
  match cursor:
    case Cursor{+length,before,after}: seekBehind(U32.to_nat(length),Cursor{length,before,after})

type Scan is Data: Scan{rest: List<&2,U32>,position: U32,previous: U32}
type Decision is Data: Boundary{at: U32} Violation{after: U32,rest: List<&2,U32>} Continue{scan: Scan}
def forwardCase(boundary: Bool,violation: Bool,finished: Bool,rest: List<&2,U32>,+position: U32,trail: U32) -> Decision:
  match boundary violation finished:
    case True{} _ _: Boundary{position}
    case False{} True{} _: Violation{(position + 1 : U32),rest}
    case False{} False{} True{}: Boundary{(position + 1 : U32)}
    case False{} False{} False{}: Continue{Scan{rest,(position + 1 : U32),trail}}
def forwardDecision(+collator: Collator,+start: U32,+rawLimit: U32,scan: Scan) -> Decision:
  match scan:
    case Scan{Nil{},position,_}: Boundary{position}
    case Scan{code <> rest,+position,+previous}:
      +value = fcdOf(collator,code)
      +lead = (value / 256 : U32)
      +trail = (value % 256 : U32)
      forwardCase(U32.is_eq(lead,0) && U32.is_ne(position,start),U32.is_ne(lead,0) && (U32.is_gt(previous,lead) || tibetanFcd(value)),
        U32.is_eq((position + 1 : U32),rawLimit) || U32.is_eq(trail,0),rest,position,trail)
def extendAhead(fuel: Nat,+collator: Collator,values: List<&2,U32>,+end: U32) -> U32:
  match fuel values:
    case Succ{left} code <> rest:
      Bool.pick(Unit -> U32,U32.is_gt(fcdOf(collator,code),255),_ => extendAhead(left,collator,rest,(end + 1 : U32)),_ => end)(Unit{})
    case _ _: end
def forwardScan(fuel: Nat,+collator: Collator,+start: U32,+rawLimit: U32,+segmentStart: U32,+region: List<&2,U32>,decision: Decision) -> Mode:
  match fuel decision:
    case _ Boundary{at}: Stay{segmentStart,at}
    case _ Violation{after,rest}:
      +end = extendAhead(U32.to_nat(rawLimit),collator,rest,after)
      +buffer = normalized(collator,List.reverse(&2,U32,takeReversed(U32.to_nat((end - start : U32)),region,Nil{})))
      Normal{rewound(buffer),indexOf(buffer),start,end}
    case Succ{left} Continue{scan}: forwardScan(left,collator,start,rawLimit,segmentStart,region,forwardDecision(collator,start,rawLimit,scan))
    case Zero{} Continue{_}: Stay{segmentStart,rawLimit}
# FCDUTF16CollationIterator::nextSegment from the raw position.
def nextSegment(+collator: Collator,raw: Cursor,+rawLimit: U32,+segmentStart: U32) -> Mode:
  match raw:
    case Cursor{+index,_,+after}:
      forwardScan(U32.to_nat((rawLimit - index + 1 : U32)),collator,index,rawLimit,segmentStart,after,forwardDecision(collator,index,rawLimit,Scan{after,index,0}))

type BackDecision is Data: Start{at: U32} Region{at: U32,value: U32,rest: List<&2,U32>} Onward{scan: Scan}
def backwardCase(boundary: Bool,violation: Bool,finished: Bool,rest: List<&2,U32>,+position: U32,value: U32,lead: U32) -> BackDecision:
  match boundary violation finished:
    case True{} _ _: Start{position}
    case False{} True{} _: Region{(position - 1 : U32),value,rest}
    case False{} False{} True{}: Start{(position - 1 : U32)}
    case False{} False{} False{}: Onward{Scan{rest,(position - 1 : U32),lead}}
def backwardDecision(+collator: Collator,+end: U32,scan: Scan) -> BackDecision:
  match scan:
    case Scan{Nil{},position,_}: Start{position}
    case Scan{code <> rest,+position,+next}:
      +value = fcdOf(collator,code)
      +lead = (value / 256 : U32)
      +trail = (value % 256 : U32)
      backwardCase(U32.is_eq(trail,0) && U32.is_ne(position,end),U32.is_ne(trail,0) && ((U32.is_ne(next,0) && U32.is_gt(trail,next)) || tibetanFcd(value)),
        U32.is_eq(position,1) || U32.is_eq(lead,0),rest,position,value,lead)
def extendBehind(fuel: Nat,+collator: Collator,values: List<&2,U32>,+start: U32,+value: U32) -> U32:
  match fuel values:
    case Succ{left} +code <> rest:
      Bool.pick(Unit -> U32,U32.is_gt(value,255) && U32.is_ne(start,0) && U32.is_ne(fcdOf(collator,code),0),
        _ => extendBehind(left,collator,rest,(start - 1 : U32),fcdOf(collator,code)),_ => start)(Unit{})
    case _ _: start
def backwardScan(fuel: Nat,+collator: Collator,+end: U32,+segmentLimit: U32,+region: List<&2,U32>,decision: BackDecision) -> Mode:
  match fuel decision:
    case _ Start{at}: Stay{at,segmentLimit}
    case _ Region{at,value,rest}:
      +start = extendBehind(U32.to_nat(end),collator,rest,at,value)
      +buffer = normalized(collator,takeReversed(U32.to_nat((end - start : U32)),region,Nil{}))
      Normal{buffer,indexOf(buffer),start,end}
    case Succ{left} Onward{scan}: backwardScan(left,collator,end,segmentLimit,region,backwardDecision(collator,end,scan))
    case Zero{} Onward{_}: Stay{0,segmentLimit}
# FCDUTF16CollationIterator::previousSegment; a normalized buffer starts at its end.
def previousSegment(+collator: Collator,raw: Cursor,+segmentLimit: U32) -> Mode:
  match raw:
    case Cursor{+index,+before,_}:
      backwardScan(U32.to_nat((index + 1 : U32)),collator,index,segmentLimit,before,backwardDecision(collator,index,Scan{before,index,0}))

def readForward(+raw: Cursor,+rawLimit: U32,mode: Mode) -> Read:
  match mode:
    case Normal{+buffer,length,segmentStart,segmentLimit}: Read{Iter{raw,rawLimit,Normal{stepAhead(buffer),length,segmentStart,segmentLimit}},ahead(buffer)}
    case Stay{start,limit}: Read{Iter{stepAhead(raw),rawLimit,Stay{start,limit}},ahead(raw)}
    case other: Read{Iter{raw,rawLimit,other},4294967295}
def aheadTriggered(trigger: Bool,+collator: Collator,+raw: Cursor,+rawLimit: U32,+segmentStart: U32,code: U32) -> Read:
  match trigger:
    case True{}: readForward(raw,rawLimit,nextSegment(collator,raw,rawLimit,segmentStart))
    case False{}: Read{Iter{stepAhead(raw),rawLimit,Ahead{segmentStart}},code}
def followerLeads(supplementary: Bool,+collator: Collator,+moved: Cursor,+rawLimit: U32) -> Bool:
  match supplementary:
    case True{}: True{}
    case False{}: U32.is_ne(indexOf(moved),rawLimit) && unitLeads(collator,firstUnit(ahead(moved)))
def aheadNext(+collator: Collator,+raw: Cursor,+rawLimit: U32,+segmentStart: U32) -> Read:
  +code = ahead(raw)
  +unit = firstUnit(code)
  +moved = stepAhead(raw)
  +nextLeads = followerLeads(U32.is_gt(code,65535),collator,moved,rawLimit)
  aheadTriggered(unitTrails(collator,unit) && (tibetanUnit(unit) || nextLeads),collator,raw,rawLimit,segmentStart,code)
def nextTurn(+collator: Collator,iter: Iter) -> Turn:
  match iter:
    case Iter{+raw,+rawLimit,Ahead{+segmentStart}}:
      Bool.pick(Unit -> Turn,U32.is_eq(indexOf(raw),rawLimit),_ => Got{Read{Iter{raw,rawLimit,Ahead{segmentStart}},4294967295}},_ => Got{aheadNext(collator,raw,rawLimit,segmentStart)})(Unit{})
    case Iter{+raw,+rawLimit,Stay{+start,+limit}}:
      Bool.pick(Unit -> Turn,U32.is_ne(indexOf(raw),limit),_ => Got{Read{Iter{stepAhead(raw),rawLimit,Stay{start,limit}},ahead(raw)}},_ => Again{Iter{raw,rawLimit,Ahead{start}}})(Unit{})
    case Iter{+raw,+rawLimit,Normal{+buffer,+length,segmentStart,+segmentLimit}}:
      Bool.pick(Unit -> Turn,U32.is_ne(indexOf(buffer),length),_ => Got{Read{Iter{raw,rawLimit,Normal{stepAhead(buffer),length,segmentStart,segmentLimit}},ahead(buffer)}},
        _ => Again{Iter{seek(raw,segmentLimit),rawLimit,Ahead{segmentLimit}}})(Unit{})
    case Iter{+raw,+rawLimit,Behind{+segmentLimit}}:
      +index = indexOf(raw)
      Bool.pick(Turn,U32.is_eq(index,segmentLimit),Again{Iter{raw,rawLimit,Ahead{index}}},Again{Iter{raw,rawLimit,Stay{index,segmentLimit}}})

def readBackward(+raw: Cursor,+rawLimit: U32,mode: Mode) -> Read:
  match mode:
    case Normal{+buffer,length,segmentStart,segmentLimit}: Read{Iter{raw,rawLimit,Normal{stepBehind(buffer),length,segmentStart,segmentLimit}},behind(buffer)}
    case Stay{start,limit}: Read{Iter{stepBehind(raw),rawLimit,Stay{start,limit}},behind(raw)}
    case other: Read{Iter{raw,rawLimit,other},4294967295}
def behindTriggered(trigger: Bool,+collator: Collator,+raw: Cursor,+rawLimit: U32,+segmentLimit: U32,code: U32) -> Read:
  match trigger:
    case True{}: readBackward(raw,rawLimit,previousSegment(collator,raw,segmentLimit))
    case False{}: Read{Iter{stepBehind(raw),rawLimit,Behind{segmentLimit}},code}
def predecessorTrails(supplementary: Bool,+collator: Collator,code: U32,+moved: Cursor) -> Bool:
  match supplementary:
    case True{}: unitTrails(collator,(55232 + code / 1024 : U32))
    case False{}: U32.is_ne(indexOf(moved),0) && unitTrails(collator,lastUnit(behind(moved)))
def behindPrevious(+collator: Collator,+raw: Cursor,+rawLimit: U32,+segmentLimit: U32) -> Read:
  +code = behind(raw)
  +unit = lastUnit(code)
  +moved = stepBehind(raw)
  +previousTrails = predecessorTrails(U32.is_gt(code,65535),collator,code,moved)
  behindTriggered(unitLeads(collator,unit) && (tibetanUnit(unit) || previousTrails),collator,raw,rawLimit,segmentLimit,code)
def previousTurn(+collator: Collator,iter: Iter) -> Turn:
  match iter:
    case Iter{+raw,+rawLimit,Behind{+segmentLimit}}:
      Bool.pick(Unit -> Turn,U32.is_eq(indexOf(raw),0),_ => Got{Read{Iter{raw,rawLimit,Behind{segmentLimit}},4294967295}},_ => Got{behindPrevious(collator,raw,rawLimit,segmentLimit)})(Unit{})
    case Iter{+raw,+rawLimit,Stay{+start,+limit}}:
      Bool.pick(Unit -> Turn,U32.is_ne(indexOf(raw),start),_ => Got{Read{Iter{stepBehind(raw),rawLimit,Stay{start,limit}},behind(raw)}},_ => Again{Iter{raw,rawLimit,Behind{limit}}})(Unit{})
    case Iter{+raw,+rawLimit,Normal{+buffer,length,+segmentStart,segmentLimit}}:
      Bool.pick(Unit -> Turn,U32.is_ne(indexOf(buffer),0),_ => Got{Read{Iter{raw,rawLimit,Normal{stepBehind(buffer),length,segmentStart,segmentLimit}},behind(buffer)}},
        _ => Again{Iter{seek(raw,segmentStart),rawLimit,Behind{segmentStart}}})(Unit{})
    case Iter{+raw,+rawLimit,Ahead{+segmentStart}}:
      +index = indexOf(raw)
      Bool.pick(Turn,U32.is_eq(index,segmentStart),Again{Iter{raw,rawLimit,Behind{index}}},Again{Iter{raw,rawLimit,Stay{segmentStart,index}}})

def nextLoop(fuel: Nat,+collator: Collator,turn: Turn) -> Read:
  match fuel turn:
    case _ Got{read}: read
    case Succ{left} Again{iter}: nextLoop(left,collator,nextTurn(collator,iter))
    case Zero{} Again{iter}: Read{iter,4294967295}
def readNext(+collator: Collator,iter: Iter) -> Read: nextLoop(5n,collator,Again{iter})
def previousLoop(fuel: Nat,+collator: Collator,turn: Turn) -> Read:
  match fuel turn:
    case _ Got{read}: read
    case Succ{left} Again{iter}: previousLoop(left,collator,previousTurn(collator,iter))
    case Zero{} Again{iter}: Read{iter,4294967295}
def readPrior(+collator: Collator,iter: Iter) -> Read: previousLoop(5n,collator,Again{iter})
# backwardNumCodePoints / forwardNumCodePoints: stop early at a text boundary.
def backLoop(steps: Nat,+collator: Collator,read: Read) -> Iter:
  match steps read:
    case Zero{} Read{iter,_}: iter
    case Succ{left} Read{+iter,code}:
      Bool.pick(Unit -> Iter,U32.is_eq(code,4294967295),_ => iter,_ => backLoop(left,collator,readPrior(collator,iter)))(Unit{})
def moveBack(+collator: Collator,count: U32,iter: Iter) -> Iter: backLoop(U32.to_nat(count),collator,Read{iter,0})
def forwardLoop(steps: Nat,+collator: Collator,read: Read) -> Iter:
  match steps read:
    case Zero{} Read{iter,_}: iter
    case Succ{left} Read{+iter,code}:
      Bool.pick(Unit -> Iter,U32.is_eq(code,4294967295),_ => iter,_ => forwardLoop(left,collator,readNext(collator,iter)))(Unit{})
def moveForward(+collator: Collator,count: U32,iter: Iter) -> Iter: forwardLoop(U32.to_nat(count),collator,Read{iter,0})

# ---- Weights of a code point without context

def implicitHan(found: Maybe<&2,Span>,+code: U32,hanBase: U32,unassignedBase: U32,+common: U32) -> List<&2,Weight>:
  match found:
    case Some{Span{+first,+last,rank}}:
      Bool.pick(Unit -> List<&2,Weight>,U32.is_ge(code,first) && U32.is_le(code,last),_ => Weight{(hanBase + rank + code - first : U32),common} <> Nil{},
        _ => Weight{(unassignedBase + code : U32),common} <> Nil{})(Unit{})
    case None{}: Weight{(unassignedBase + code : U32),common} <> Nil{}
def implicitWeights(collator: Collator,+code: U32) -> List<&2,Weight>:
  match collator:
    case Collator{_,han,_,_,_,_,hanBase,unassignedBase,+common}:
      implicitHan(Table.floor(Span,han,code),code,hanBase,unassignedBase,common)
def runWeight(+code: U32,first: U32,+primary: U32,lower: U32) -> Weight:
  Weight{Bool.pick(U32,U32.is_eq(primary,0),0,(primary + code - first : U32)),lower}
type Lookup is Data: Plain{weights: List<&2,Weight>} Starter{trailing: Bool,single: Bool,fallback: List<&2,Weight>,suffixes: List<&2,Suffix>} Context{fallback: List<&2,Weight>,prefixes: List<&2,Prefix>}
def lookupFound(+collator: Collator,+code: U32,found: Maybe<&2,Mapping>) -> Lookup:
  match found:
    case Some{Run{first,+last,primary,lower}}:
      Bool.pick(Unit -> Lookup,U32.is_le(code,last),_ => Plain{runWeight(code,first,primary,lower) <> Nil{}},_ => Plain{implicitWeights(collator,code)})(Unit{})
    case Some{Expansion{+owner,weights}}: Bool.pick(Unit -> Lookup,U32.is_eq(owner,code),_ => Plain{weights},_ => Plain{implicitWeights(collator,code)})(Unit{})
    case Some{Contraction{+owner,trailing,single,fallback,suffixes}}:
      Bool.pick(Unit -> Lookup,U32.is_eq(owner,code),_ => Starter{trailing,single,fallback,suffixes},_ => Plain{implicitWeights(collator,code)})(Unit{})
    case Some{Prefixed{+owner,fallback,prefixes}}: Bool.pick(Unit -> Lookup,U32.is_eq(owner,code),_ => Context{fallback,prefixes},_ => Plain{implicitWeights(collator,code)})(Unit{})
    case None{}: Plain{implicitWeights(collator,code)}
def lookupDirect(+collator: Collator,+code: U32) -> Lookup:
  match collator:
    case Collator{mappings,_,_,_,_,_,_,_,_}: lookupFound(collator,code,Table.floor(Mapping,mappings,code))
def plainOf(lookup: Lookup) -> List<&2,Weight>:
  match lookup:
    case Plain{weights}: weights
    case Starter{_,_,fallback,_}: fallback
    case Context{fallback,_}: fallback
def appendWeights(weights: List<&2,Weight>,reversed: List<&2,Weight>) -> List<&2,Weight>:
  match weights:
    case Nil{}: reversed
    case weight <> rest: appendWeights(rest,weight <> reversed)
def jamo(+collator: Collator,codes: List<&2,U32>,reversed: List<&2,Weight>) -> List<&2,Weight>:
  match codes:
    case Nil{}: List.reverse(&2,Weight,reversed)
    case +code <> rest: jamo(collator,rest,appendWeights(plainOf(lookupDirect(collator,code)),reversed))
# Hangul syllables collate as their conjoining jamo (root has no jamo contexts).
def lookup(+collator: Collator,+code: U32) -> Lookup:
  Bool.pick(Unit -> Lookup,isSyllable(code),_ => Plain{jamo(collator,hangul((code - 44032 : U32)),Nil{})},_ => lookupDirect(collator,code))(Unit{})

# ---- Contraction matching (CollationIterator::nextCE32FromContraction et al.)

type Trie is Data: Trie{candidates: List<&2,Suffix>}
type Sift is Data: Sift{kept: List<&2,Suffix>,value: Maybe<&2,List<&2,Weight>>,more: Bool}
def keep(rest: List<&2,U32>,weights: List<&2,Weight>,sift: Sift) -> Sift:
  match rest sift:
    case Nil{} Sift{kept,_,more}: Sift{kept,Some{weights},more}
    case rest Sift{kept,value,_}: Sift{Suffix{rest,weights} <> kept,value,True{}}
def siftOne(codes: List<&2,U32>,weights: List<&2,Weight>,+code: U32,+sift: Sift) -> Sift:
  match codes:
    case Nil{}: sift
    case head <> rest: Bool.pick(Unit -> Sift,U32.is_eq(head,code),_ => keep(rest,weights,sift),_ => sift)(Unit{})
def siftAll(candidates: List<&2,Suffix>,+code: U32,sift: Sift) -> Sift:
  match candidates:
    case Nil{}: sift
    case Suffix{codes,weights} <> rest: siftAll(rest,code,siftOne(codes,weights,code,sift))
type Step is Data: Step{trie: Trie,value: Maybe<&2,List<&2,Weight>>,more: Bool}
def stepped(sift: Sift) -> Step:
  match sift:
    case Sift{kept,value,more}: Step{Trie{List.reverse(&2,Suffix,kept)},value,more}
def advance(trie: Trie,+code: U32) -> Step:
  match trie:
    case Trie{candidates}: stepped(siftAll(candidates,code,Sift{Nil{},None{},False{}}))
def trieOf(step: Step) -> Trie:
  match step:
    case Step{trie,_,_}: trie

# Marks skipped by discontiguous matching (ICU's SkippedState): `old` holds
# marks to reread (its index is ICU's position, `beyond` counts code points read
# past its end), `fresh` (reversed) the marks skipped by the current match.
type Skipped is Data: Skipped{old: Cursor,count: U32,beyond: U32,fresh: List<&2,U32>,freshCount: U32,atMatch: U32,saved: Trie}
def emptySkipped() -> Skipped: Skipped{Cursor{0,Nil{},Nil{}},0,0,Nil{},0,0,Trie{Nil{}}}
type Engine is Data: Engine{iter: Iter,skipped: Skipped,out: List<&2,Weight>,size: U32}
type Pulled is Data: Pulled{engine: Engine,code: U32}
def pulledText(read: Read,skipped: Skipped,out: List<&2,Weight>,size: U32) -> Pulled:
  match read skipped:
    case Read{iter,+code} Skipped{old,+count,beyond,fresh,freshCount,atMatch,saved}:
      +more = Bool.pick(U32,U32.is_ne(count,0) && U32.is_ne(code,4294967295),1,0)
      Pulled{Engine{iter,Skipped{old,count,(beyond + more : U32),fresh,freshCount,atMatch,saved},out,size},code}
def pullFrom(buffered: Bool,+collator: Collator,iter: Iter,skipped: Skipped,out: List<&2,Weight>,size: U32) -> Pulled:
  match buffered skipped:
    case True{} Skipped{+old,count,beyond,fresh,freshCount,atMatch,saved}: Pulled{Engine{iter,Skipped{stepAhead(old),count,beyond,fresh,freshCount,atMatch,saved},out,size},ahead(old)}
    case False{} skipped: pulledText(readNext(collator,iter),skipped,out,size)
def hasNextSkipped(skipped: Skipped) -> Bool:
  match skipped:
    case Skipped{old,_,_,_,_,_,_}: U32.is_ne(ahead(old),4294967295)
# nextSkippedCodePoint
def pull(+collator: Collator,engine: Engine) -> Pulled:
  match engine:
    case Engine{iter,+skipped,out,size}: pullFrom(hasNextSkipped(skipped),collator,iter,skipped,out,size)
type Backed is Data: Backed{old: Cursor,beyond: U32,text: U32}
# SkippedState::backwardNumCodePoints: `text` code points remain to back up in the text.
def backedSkipped(+old: Cursor,+beyond: U32,+steps: U32) -> Backed:
  Bool.pick(Unit -> Backed,U32.is_gt(beyond,0),
    _ => Bool.pick(Unit -> Backed,U32.is_ge(beyond,steps),_ => Backed{old,(beyond - steps : U32),steps},_ => Backed{seekBehind(U32.to_nat((steps - beyond : U32)),old),0,beyond})(Unit{}),
    _ => Backed{seekBehind(U32.to_nat(U32.min(steps,indexOf(old))),old),0,0})(Unit{})
def backedEngine(+collator: Collator,backed: Backed,iter: Iter,count: U32,fresh: List<&2,U32>,freshCount: U32,atMatch: U32,saved: Trie,out: List<&2,Weight>,size: U32) -> Engine:
  match backed:
    case Backed{old,beyond,text}: Engine{moveBack(collator,text,iter),Skipped{old,count,beyond,fresh,freshCount,atMatch,saved},out,size}
# backwardNumSkipped
def pushBack(+collator: Collator,+steps: U32,engine: Engine) -> Engine:
  match engine:
    case Engine{iter,Skipped{+old,+count,+beyond,fresh,freshCount,atMatch,saved},out,size}:
      backedEngine(collator,Bool.pick(Unit -> Backed,U32.is_eq(count,0),_ => Backed{old,beyond,steps},_ => backedSkipped(old,beyond,steps))(Unit{}),iter,count,fresh,freshCount,atMatch,saved,out,size)
def skippedEmpty(engine: Engine) -> Bool:
  match engine:
    case Engine{_,Skipped{_,count,_,_,_,_,_},_,_}: U32.is_eq(count,0)
def savedTrie(engine: Engine) -> Trie:
  match engine:
    case Engine{_,Skipped{_,_,_,_,_,_,saved},_,_}: saved
def withSaved(engine: Engine,trie: Trie) -> Engine:
  match engine:
    case Engine{iter,Skipped{old,count,beyond,fresh,freshCount,atMatch,_},out,size}: Engine{iter,Skipped{old,count,beyond,fresh,freshCount,atMatch,trie},out,size}
def saveIfSkipping(+engine: Engine,trie: Trie) -> Engine: Bool.pick(Unit -> Engine,skippedEmpty(engine),_ => engine,_ => withSaved(engine,trie))(Unit{})
def withFirstSkipped(engine: Engine,code: U32) -> Engine:
  match engine:
    case Engine{iter,Skipped{old,count,beyond,_,_,_,saved},out,size}: Engine{iter,Skipped{old,count,beyond,code <> Nil{},1,0,saved},out,size}
def withSkip(engine: Engine,code: U32) -> Engine:
  match engine:
    case Engine{iter,Skipped{old,count,beyond,fresh,freshCount,atMatch,saved},out,size}: Engine{iter,Skipped{old,count,beyond,code <> fresh,(freshCount + 1 : U32),atMatch,saved},out,size}
def withMatchRecorded(engine: Engine) -> Engine:
  match engine:
    case Engine{iter,Skipped{old,count,beyond,fresh,+freshCount,_,saved},out,size}: Engine{iter,Skipped{old,count,beyond,fresh,freshCount,freshCount,saved},out,size}
def replacedOld(old: Cursor,fresh: List<&2,U32>,atMatch: U32) -> Cursor:
  match old:
    case Cursor{_,_,after}: Cursor{0,Nil{},prependAll(takeReversed(U32.to_nat(atMatch),List.reverse(&2,U32,fresh),Nil{}),after)}
# SkippedState::replaceMatch: the matched marks' place goes to the newly skipped ones.
def withReplacedMatch(engine: Engine) -> Engine:
  match engine:
    case Engine{iter,Skipped{+old,+count,_,fresh,_,+atMatch,saved},out,size}:
      Engine{iter,Skipped{replacedOld(old,fresh,atMatch),(atMatch + count - indexOf(old) : U32),0,Nil{},0,0,saved},out,size}
def withCleared(engine: Engine) -> Engine:
  match engine:
    case Engine{iter,Skipped{_,_,_,fresh,freshCount,atMatch,saved},out,size}: Engine{iter,Skipped{Cursor{0,Nil{},Nil{}},0,0,fresh,freshCount,atMatch,saved},out,size}
def withIter(engine: Engine,iter: Iter) -> Engine:
  match engine:
    case Engine{_,skipped,out,size}: Engine{iter,skipped,out,size}
def iterOf(engine: Engine) -> Iter:
  match engine:
    case Engine{iter,_,_,_}: iter
def countWeights(weights: List<&2,Weight>,+count: U32) -> U32:
  match weights:
    case Nil{}: count
    case _ <> rest: countWeights(rest,(count + 1 : U32))
def emit(engine: Engine,+weights: List<&2,Weight>) -> Engine:
  match engine:
    case Engine{iter,skipped,out,size}: Engine{iter,skipped,appendWeights(weights,out),countWeights(weights,size)}

type Outcome is Data: Outcome{engine: Engine,weights: List<&2,Weight>,top: Bool}

# Replay the partial match after backing up (discontiguous, lookAhead > 2).
def replaySteps(steps: Nat,+collator: Collator,read: Read,trie: Trie) -> Engine & Trie:
  match steps read:
    case Zero{} Read{iter,code}: (Engine{iter,emptySkipped(),Nil{},0},trieOf(advance(trie,code)))
    case Succ{left} Read{iter,+code}: replaySteps(left,collator,readNext(collator,iter),trieOf(advance(trie,code)))
def replayedWith(state: Engine & Trie,+collator: Collator,skipped: Skipped,out: List<&2,Weight>,size: U32) -> Engine:
  match state:
    case (Engine{iter,_,_,_},trie): withSaved(Engine{moveForward(collator,2,iter),skipped,out,size},trie)

def replayed(+collator: Collator,+lookAhead: U32,engine: Engine,root: Trie) -> Engine:
  match engine:
    case Engine{iter,skipped,out,size}:
      +moved = readNext(collator,moveBack(collator,lookAhead,iter))
      replayedWith(replaySteps(U32.to_nat((lookAhead - 3 : U32)),collator,moved,root),collator,skipped,out,size)
type Disc is Data: Disc{engine: Engine,trie: Trie,previous: U32,value: U32,code: U32,sinceMatch: U32,weights: List<&2,Weight>}
type DiscStep is Data: DiscMore{state: Disc} DiscDone{engine: Engine,sinceMatch: U32,weights: List<&2,Weight>}
def discRead(+collator: Collator,pulled: Pulled,trie: Trie,previous: U32,+sinceMatch: U32,+weights: List<&2,Weight>) -> DiscStep:
  match pulled:
    case Pulled{+engine,+code}:
      +value = fcdOf(collator,code)
      Bool.pick(Unit -> DiscStep,U32.is_eq(code,4294967295),_ => DiscDone{engine,sinceMatch,weights},
        _ => Bool.pick(Unit -> DiscStep,U32.is_le(value,255),_ => DiscDone{engine,(sinceMatch + 1 : U32),weights},
          _ => DiscMore{Disc{engine,trie,previous,value,code,(sinceMatch + 1 : U32),weights}})(Unit{}))(Unit{})
def discMatched(+collator: Collator,step: Step,engine: Engine,+previous: U32,+value: U32,+code: U32,+sinceMatch: U32,weights: List<&2,Weight>) -> DiscStep:
  match step:
    case Step{+trie,Some{+found},more}:
      +recorded = withMatchRecorded(engine)
      Bool.pick(Unit -> DiscStep,more,_ => discRead(collator,pull(collator,withSaved(recorded,trie)),trie,previous,0,found),_ => DiscDone{recorded,0,found})(Unit{})
    case Step{_,None{},_}:
      +skipped = withSkip(engine,code)
      +trie = savedTrie(skipped)
      discRead(collator,pull(collator,skipped),trie,(value % 256 : U32),sinceMatch,weights)
def discStep(+collator: Collator,state: Disc) -> DiscStep:
  match state:
    case Disc{+engine,+trie,+previous,+value,+code,+sinceMatch,+weights}:
      Bool.pick(Unit -> DiscStep,U32.is_lt(previous,(value / 256 : U32)),_ => discMatched(collator,advance(trie,code),engine,previous,value,code,sinceMatch,weights),
        _ => discMatched(collator,Step{trie,None{},False{}},engine,previous,value,code,sinceMatch,weights))(Unit{})
def discLoop(fuel: Nat,+collator: Collator,step: DiscStep) -> DiscStep:
  match fuel step:
    case Succ{left} DiscMore{state}: discLoop(left,collator,discStep(collator,state))
    case _ step: step
def discFinished(+collator: Collator,step: DiscStep) -> Outcome:
  match step:
    case DiscDone{engine,sinceMatch,weights}:
      +backed = pushBack(collator,sinceMatch,engine)
      +top = skippedEmpty(backed)
      +replaced = withReplacedMatch(backed)
      Outcome{replaced,weights,top && Bool.not(skippedEmpty(replaced))}
    case DiscMore{Disc{engine,_,_,_,_,_,weights}}: Outcome{engine,weights,False{}}
def discPrepared(+collator: Collator,+engine: Engine,+root: Trie,+lookAhead: U32) -> Engine:
  Bool.pick(Unit -> Engine,skippedEmpty(engine),
    _ => Bool.pick(Unit -> Engine,U32.is_gt(lookAhead,2),_ => replayed(collator,lookAhead,engine,root),_ => withSaved(engine,root))(Unit{}),
    _ => engine)(Unit{})
def discStarted(+collator: Collator,engine: Engine,root: Trie,+lookAhead: U32,+first: U32,+firstValue: U32,+code: U32,+value: U32,+budget: Nat,weights: List<&2,Weight>) -> Outcome:
  +prepared = withFirstSkipped(discPrepared(collator,engine,root,lookAhead),first)
  discFinished(collator,discLoop(budget,collator,DiscMore{Disc{prepared,savedTrie(prepared),(firstValue % 256 : U32),value,code,2,weights}}))
def discSecond(+collator: Collator,pulled: Pulled,root: Trie,+lookAhead: U32,+first: U32,+firstValue: U32,+budget: Nat,+weights: List<&2,Weight>) -> Outcome:
  match pulled:
    case Pulled{+engine,+code}:
      +value = fcdOf(collator,code)
      Bool.pick(Unit -> Outcome,U32.is_eq(code,4294967295),_ => Outcome{pushBack(collator,1,engine),weights,False{}},
        _ => Bool.pick(Unit -> Outcome,U32.is_le(value,255),_ => Outcome{pushBack(collator,2,engine),weights,False{}},
          _ => discStarted(collator,engine,root,(lookAhead + 1 : U32),first,firstValue,code,value,budget,weights))(Unit{}))(Unit{})
# nextCE32FromDiscontiguousContraction: `first` is the unmatched non-starter.
def discontiguous(+collator: Collator,engine: Engine,root: Trie,+lookAhead: U32,+first: U32,+budget: Nat,weights: List<&2,Weight>) -> Outcome:
  discSecond(collator,pull(collator,engine),root,lookAhead,first,fcdOf(collator,first),budget,weights)

type Contract is Data: Contract{engine: Engine,step: Step,code: U32,lookAhead: U32,sinceMatch: U32,weights: List<&2,Weight>}
type ContractStep is Data: ContractMore{state: Contract} ContractBreak{engine: Engine,sinceMatch: U32,weights: List<&2,Weight>} ContractFinal{outcome: Outcome} ContractDisc{engine: Engine,lookAhead: U32,code: U32,weights: List<&2,Weight>}
def contractValueNext(+collator: Collator,pulled: Pulled,+trie: Trie,+lookAhead: U32,+found: List<&2,Weight>) -> ContractStep:
  match pulled:
    case Pulled{+engine,+code}:
      Bool.pick(Unit -> ContractStep,U32.is_eq(code,4294967295),_ => ContractFinal{Outcome{engine,found,False{}}},
        _ => ContractMore{Contract{saveIfSkipping(engine,trie),advance(trie,code),code,(lookAhead + 1 : U32),1,found}})(Unit{})
def contractValue(+collator: Collator,more: Bool,trie: Trie,engine: Engine,+lookAhead: U32,found: List<&2,Weight>) -> ContractStep:
  match more:
    case False{}: ContractFinal{Outcome{engine,found,False{}}}
    case True{}: contractValueNext(collator,pull(collator,engine),trie,lookAhead,found)
def contractRewound(+collator: Collator,pulled: Pulled,+lookAhead: U32,+weights: List<&2,Weight>) -> ContractStep:
  match pulled:
    case Pulled{+engine,+code}:
      Bool.pick(Unit -> ContractStep,U32.is_gt(fcdOf(collator,code),255),_ => ContractDisc{engine,lookAhead,code,weights},_ => ContractBreak{engine,1,weights})(Unit{})
def contractFallout(+collator: Collator,trailing: Bool,single: Bool,+engine: Engine,+code: U32,+lookAhead: U32,+sinceMatch: U32,+weights: List<&2,Weight>) -> ContractStep:
  Bool.pick(Unit -> ContractStep,trailing && (Bool.not(single) || U32.is_lt(sinceMatch,lookAhead)),
    _ => contractRewound(collator,Bool.pick(Unit -> Pulled,U32.is_gt(sinceMatch,1),_ => pull(collator,pushBack(collator,sinceMatch,engine)),_ => Pulled{engine,code})(Unit{}),
      Bool.pick(U32,U32.is_gt(sinceMatch,1),(lookAhead - sinceMatch + 1 : U32),lookAhead),weights),
    _ => ContractBreak{engine,sinceMatch,weights})(Unit{})
def contractPartial(+collator: Collator,trailing: Bool,single: Bool,pulled: Pulled,trie: Trie,+code: U32,+lookAhead: U32,+sinceMatch: U32,+weights: List<&2,Weight>) -> ContractStep:
  match pulled:
    case Pulled{+engine,+next}:
      Bool.pick(Unit -> ContractStep,U32.is_eq(next,4294967295),_ => contractFallout(collator,trailing,single,engine,code,lookAhead,sinceMatch,weights),
        _ => ContractMore{Contract{engine,advance(trie,next),next,(lookAhead + 1 : U32),(sinceMatch + 1 : U32),weights}})(Unit{})
def contractOn(+collator: Collator,trailing: Bool,single: Bool,step: Step,engine: Engine,code: U32,lookAhead: U32,sinceMatch: U32,weights: List<&2,Weight>) -> ContractStep:
  match step:
    case Step{trie,Some{found},more}: contractValue(collator,more,trie,engine,lookAhead,found)
    case Step{Trie{Nil{}},None{},_}: contractFallout(collator,trailing,single,engine,code,lookAhead,sinceMatch,weights)
    case Step{trie,None{},_}: contractPartial(collator,trailing,single,pull(collator,engine),trie,code,lookAhead,sinceMatch,weights)
def contractStep(+collator: Collator,trailing: Bool,single: Bool,state: Contract) -> ContractStep:
  match state:
    case Contract{engine,step,code,lookAhead,sinceMatch,weights}: contractOn(collator,trailing,single,step,engine,code,lookAhead,sinceMatch,weights)
def contractLoop(fuel: Nat,+collator: Collator,+trailing: Bool,+single: Bool,step: ContractStep) -> ContractStep:
  match fuel step:
    case Succ{left} ContractMore{state}: contractLoop(left,collator,trailing,single,contractStep(collator,trailing,single,state))
    case _ step: step
def contractEnded(+collator: Collator,root: Trie,+budget: Nat,step: ContractStep) -> Outcome:
  match step:
    case ContractFinal{outcome}: outcome
    case ContractBreak{engine,sinceMatch,weights}: Outcome{pushBack(collator,sinceMatch,engine),weights,False{}}
    case ContractDisc{engine,lookAhead,code,weights}: discontiguous(collator,engine,root,lookAhead,code,budget,weights)
    case ContractMore{Contract{engine,_,_,_,_,weights}}: Outcome{engine,weights,False{}}
def contraction(+collator: Collator,trailing: Bool,single: Bool,+fallback: List<&2,Weight>,+suffixes: List<&2,Suffix>,pulled: Pulled,+budget: Nat) -> Outcome:
  match pulled:
    case Pulled{+engine,+code}:
      Bool.pick(Unit -> Outcome,U32.is_eq(code,4294967295),_ => Outcome{engine,fallback,False{}},
        _ => contractEnded(collator,Trie{suffixes},budget,contractLoop(budget,collator,trailing,single,
          ContractMore{Contract{saveIfSkipping(engine,Trie{suffixes}),advance(Trie{suffixes},code),code,1,1,fallback}})))(Unit{})

# Prefix context (root: U+00B7/U+0387 after L or l): look one code point back.
def prefixWeights(prefixes: List<&2,Prefix>,+code: U32,fallback: List<&2,Weight>) -> List<&2,Weight>:
  match prefixes:
    case Nil{}: fallback
    case Prefix{+owner,+weights} <> rest: Bool.pick(Unit -> List<&2,Weight>,U32.is_eq(owner,code),_ => weights,_ => prefixWeights(rest,code,fallback))(Unit{})
def prefixRead(+collator: Collator,read: Read,+skipped: Skipped,+out: List<&2,Weight>,+size: U32,+fallback: List<&2,Weight>,prefixes: List<&2,Prefix>) -> Outcome:
  match read:
    case Read{+iter,+code}:
      Bool.pick(Unit -> Outcome,U32.is_eq(code,4294967295),_ => Outcome{Engine{moveForward(collator,1,iter),skipped,out,size},fallback,False{}},
        _ => Outcome{Engine{moveForward(collator,1,moveForward(collator,1,iter)),skipped,out,size},prefixWeights(prefixes,code,fallback),False{}})(Unit{})

def prefixed(+collator: Collator,engine: Engine,fallback: List<&2,Weight>,prefixes: List<&2,Prefix>) -> Outcome:
  match engine:
    case Engine{iter,skipped,out,size}:
      prefixRead(collator,readPrior(collator,moveBack(collator,1,iter)),skipped,out,size,fallback,prefixes)
# appendCEsFromCE32 for one code point.
def appendLookup(+collator: Collator,engine: Engine,+budget: Nat,found: Lookup) -> Outcome:
  match found:
    case Plain{weights}: Outcome{engine,weights,False{}}
    case Context{fallback,prefixes}: prefixed(collator,engine,fallback,prefixes)
    case Starter{trailing,single,fallback,suffixes}: contraction(collator,trailing,single,fallback,suffixes,pull(collator,engine),budget)
def appendOne(+collator: Collator,engine: Engine,+code: U32,+budget: Nat) -> Outcome: appendLookup(collator,engine,budget,lookup(collator,code))
def emitted(outcome: Outcome) -> Engine:
  match outcome:
    case Outcome{engine,weights,_}: emit(engine,weights)
# Top-level discontiguous matches append the contraction, then reread the
# skipped marks (each may itself start a nested contraction).
type Drain is Data: Draining{engine: Engine} Drained{engine: Engine}
def drainFrom(buffered: Bool,+collator: Collator,+budget: Nat,engine: Engine) -> Drain:
  match buffered engine:
    case True{} Engine{iter,Skipped{+old,count,beyond,fresh,freshCount,atMatch,saved},out,size}:
      Draining{emitted(appendOne(collator,Engine{iter,Skipped{stepAhead(old),count,beyond,fresh,freshCount,atMatch,saved},out,size},ahead(old),budget))}
    case False{} engine: Drained{withCleared(engine)}
def skippedOf(engine: Engine) -> Skipped:
  match engine:
    case Engine{_,skipped,_,_}: skipped
def drain(fuel: Nat,+collator: Collator,+budget: Nat,state: Drain) -> Engine:
  match fuel state:
    case _ Drained{engine}: engine
    case Succ{left} Draining{+engine}: drain(left,collator,budget,drainFrom(hasNextSkipped(skippedOf(engine)),collator,budget,engine))
    case Zero{} Draining{engine}: withCleared(engine)
def appendTop(+collator: Collator,+budget: Nat,outcome: Outcome) -> Engine:
  match outcome:
    case Outcome{+engine,+weights,top}:
      Bool.pick(Unit -> Engine,top,_ => drain(budget,collator,budget,Draining{emit(engine,weights)}),_ => emit(engine,weights))(Unit{})

# Iterator states at CE boundaries determine the rest of the stream; a repeat
# (Brent's cycle detection) means ICU would produce the cycle forever.
type Place is Data: Place{kind: U32,a: U32,b: U32,c: U32}
def placeOf(iter: Iter) -> Place:
  match iter:
    case Iter{raw,_,Ahead{segmentStart}}: Place{0,indexOf(raw),segmentStart,0}
    case Iter{raw,_,Behind{segmentLimit}}: Place{1,indexOf(raw),segmentLimit,0}
    case Iter{raw,_,Stay{start,limit}}: Place{2,indexOf(raw),start,limit}
    case Iter{_,_,Normal{buffer,_,segmentStart,segmentLimit}}: Place{3,indexOf(buffer),segmentStart,segmentLimit}
def samePlace(left: Place,right: Place) -> Bool:
  match left right:
    case Place{k,a,b,c} Place{l,d,e,f}: U32.is_eq(k,l) && U32.is_eq(a,d) && U32.is_eq(b,e) && U32.is_eq(c,f)
type Walk is Data: Walk{engine: Engine,check: Place,power: U32,steps: U32,mark: U32}
def finiteKey(engine: Engine) -> Key:
  match engine:
    case Engine{_,_,out,_}: Key{List.reverse(&2,Weight,out),Nil{}}
def takeWeights(count: Nat,values: List<&2,Weight>,reversed: List<&2,Weight>) -> List<&2,Weight>:
  match count values:
    case Succ{left} value <> rest: takeWeights(left,rest,value <> reversed)
    case _ _: reversed
def cycleKey(engine: Engine,+mark: U32) -> Key:
  match engine:
    case Engine{_,_,+out,+size}:
      +cycle = U32.to_nat((size - mark : U32))
      Key{List.reverse(&2,Weight,List.drop(&2,Weight,out,cycle)),takeWeights(cycle,out,Nil{})}
type WalkStep is Data: WalkOn{walk: Walk} WalkDone{key: Key}
def walked(+engine: Engine,+check: Place,+power: U32,+steps: U32,+mark: U32) -> WalkStep:
  match engine:
    case Engine{+iter,_,_,+size}:
      +place = placeOf(iter)
      Bool.pick(Unit -> WalkStep,samePlace(place,check),_ => WalkDone{cycleKey(engine,mark)},
        _ => Bool.pick(WalkStep,U32.is_eq(power,steps),WalkOn{Walk{engine,place,(power * 2 : U32),1,size}},WalkOn{Walk{engine,check,power,(steps + 1 : U32),mark}}))(Unit{})
def walkRead(+collator: Collator,+budget: Nat,read: Read,+engine: Engine,check: Place,power: U32,steps: U32,mark: U32) -> WalkStep:
  match read:
    case Read{iter,+code}:
      Bool.pick(Unit -> WalkStep,U32.is_eq(code,4294967295),_ => WalkDone{finiteKey(engine)},
        _ => walked(appendTop(collator,budget,appendOne(collator,withIter(engine,iter),code,budget)),check,power,steps,mark))(Unit{})
def walk(fuel: Nat,+collator: Collator,+budget: Nat,step: WalkStep) -> Key:
  match fuel step:
    case _ WalkDone{done}: done
    case Succ{left} WalkOn{Walk{+engine,check,power,steps,mark}}: walk(left,collator,budget,walkRead(collator,budget,readNext(collator,iterOf(engine)),engine,check,power,steps,mark))
    case Zero{} WalkOn{Walk{engine,_,_,_,_}}: finiteKey(engine)

def codesOf(text: String,reversed: List<&2,U32>) -> List<&2,U32>:
  match text:
    case SNil{}: List.reverse(&2,U32,reversed)
    case SCon{Chr{code},rest}: codesOf(rest,code <> reversed)
def flushed(+pending: U32,+reversed: List<&2,U32>) -> List<&2,U32>: Bool.pick(List<&2,U32>,U32.is_eq(pending,4294967295),reversed,pending <> reversed)
# JavaScript strings are UTF-16: a high surrogate followed by a low surrogate
# is the supplementary code point they encode; other surrogates stay lone.
def paired(codes: List<&2,U32>,+pending: U32,+reversed: List<&2,U32>) -> List<&2,U32>:
  match codes:
    case Nil{}: List.reverse(&2,U32,flushed(pending,reversed))
    case +code <> +rest:
      Bool.pick(Unit -> List<&2,U32>,U32.is_ne(pending,4294967295) && isTrail(code),
        _ => paired(rest,4294967295,(65536 + (pending - 55296) * 1024 + code - 56320 : U32) <> reversed),
        _ => Bool.pick(Unit -> List<&2,U32>,isLead(code),_ => paired(rest,code,flushed(pending,reversed)),_ => paired(rest,4294967295,code <> flushed(pending,reversed)))(Unit{}))(Unit{})
def countCodes(codes: List<&2,U32>,+count: U32) -> U32:
  match codes:
    case Nil{}: count
    case _ <> rest: countCodes(rest,(count + 1 : U32))

def initialEngine(codes: List<&2,U32>,length: U32) -> Engine: Engine{Iter{Cursor{0,Nil{},codes},length,Ahead{0}},emptySkipped(),Nil{},0}
def keyOf(+collator: Collator,codes: List<&2,U32>,+length: U32) -> Key:
  +budget = U32.to_nat((length + 8 : U32))
  +engine = initialEngine(codes,length)
  walk(U32.to_nat((length * 8 + 32 : U32)),collator,budget,WalkOn{Walk{engine,placeOf(iterOf(engine)),1,1,0}})
# The collation elements of a string, for repeated comparisons.
# `codes` are UTF-16 code units or code points, as in a JavaScript string;
# this entry point also covers lone surrogates, which Bend strings exclude.
def keyCodes(+collator: Collator,codes: List<&2,U32>) -> Key:
  +scalars = paired(codes,4294967295,Nil{})
  keyOf(collator,scalars,countCodes(scalars,0))
def key(+collator: Collator,text: String) -> Key: keyCodes(collator,codesOf(text,Nil{}))

# ---- Comparison: primary, secondary, tertiary (ICU CollationCompare).

def levelWeight(+level: U32,weight: Weight) -> U32:
  match weight:
    case Weight{primary,+lower}:
      Bool.pick(U32,U32.is_eq(level,0),primary,Bool.pick(U32,U32.is_eq(level,1),(lower / 65536 : U32),(lower % 65536 : U32)))
def project(+level: U32,weights: List<&2,Weight>,+reversed: List<&2,U32>) -> List<&2,U32>:
  match weights:
    case Nil{}: List.reverse(&2,U32,reversed)
    case weight <> rest:
      +value = levelWeight(level,weight)
      project(level,rest,Bool.pick(List<&2,U32>,U32.is_eq(value,0),reversed,value <> reversed))
type Sequence is Data: Sequence{rest: List<&2,U32>,cycle: List<&2,U32>,whole: List<&2,U32>}
type Taken is Data: Taken{value: U32,sequence: Sequence}
# 0 marks the end: real weights are non-zero, and ICU's terminator sorts lowest.
def taken(sequence: Sequence) -> Taken:
  match sequence:
    case Sequence{value <> rest,cycle,whole}: Taken{value,Sequence{rest,cycle,whole}}
    case Sequence{Nil{},value <> cycle,whole}: Taken{value,Sequence{Nil{},cycle,whole}}
    case Sequence{Nil{},Nil{},Nil{}}: Taken{0,Sequence{Nil{},Nil{},Nil{}}}
    case Sequence{Nil{},Nil{},+value <> +cycle}: Taken{value,Sequence{Nil{},cycle,value <> cycle}}
def orderOf(+left: U32,+right: U32) -> Cmp: Bool.pick(Cmp,U32.is_lt(left,right),LT{},Bool.pick(Cmp,U32.is_gt(left,right),GT{},EQ{}))
def compared(fuel: Nat,left: Taken,right: Taken) -> Cmp:
  match fuel left right:
    case Succ{more} Taken{+a,x} Taken{+b,y}:
      Bool.pick(Unit -> Cmp,U32.is_ne(a,b),_ => orderOf(a,b),_ => Bool.pick(Unit -> Cmp,U32.is_eq(a,0),_ => EQ{},_ => compared(more,taken(x),taken(y)))(Unit{}))(Unit{})
    case Zero{} _ _: EQ{}
def sequenceOf(+level: U32,stream: Key) -> Sequence:
  match stream:
    case Key{prefix,cycle}:
      +whole = project(level,cycle,Nil{})
      Sequence{project(level,prefix,Nil{}),whole,whole}
def sequenceLength(sequence: Sequence) -> U32:
  match sequence:
    case Sequence{rest,cycle,_}: countCodes(rest,countCodes(cycle,0))
def cycleLength(sequence: Sequence) -> U32:
  match sequence:
    case Sequence{_,cycle,_}: countCodes(cycle,1)
# Two eventually periodic sequences that agree this long agree forever.
def levelOrder(+level: U32,left: Key,right: Key) -> Cmp:
  +a = sequenceOf(level,left)
  +b = sequenceOf(level,right)
  compared(U32.to_nat((sequenceLength(a) + sequenceLength(b) + cycleLength(a) * cycleLength(b) + 1 : U32)),taken(a),taken(b))
def hasCycle(stream: Key) -> Bool:
  match stream:
    case Key{_,Nil{}}: False{}
    case _: True{}
def secondaryLevel(secondary: Cmp,left: Key,right: Key) -> Cmp:
  match secondary:
    case EQ{}: levelOrder(2,left,right)
    case order: order
def laterLevels(primary: Cmp,+left: Key,+right: Key) -> Cmp:
  match primary:
    case EQ{}:
      Bool.pick(Unit -> Cmp,hasCycle(left) || hasCycle(right),_ => EQ{},_ => secondaryLevel(levelOrder(1,left,right),left,right))(Unit{})
    case order: order
# Streams that stay equal forever at the primary level never terminate in
# ICU (it loops); they compare EQ here.
def compareKeys(+left: Key,+right: Key) -> Cmp: laterLevels(levelOrder(0,left,right),left,right)
def compare(+collator: Collator,left: String,right: String) -> Cmp: compareKeys(key(collator,left),key(collator,right))
# The sign of `left.localeCompare(right)` as -1, 0 or 1 (Node, en-US).
def localeCompare(+collator: Collator,left: String,right: String) -> Cmp: compare(collator,left,right)

# Stable sort by collation, keys computed once per string (Array.prototype.sort
# with localeCompare keeps ties in input order too).
type Keyed is Data: Keyed{key: Key,text: String}
def keyedLe(left: Keyed,right: Keyed) -> Bool:
  match left right:
    case Keyed{a,_} Keyed{b,_}: Bool.not(Cmp.is_gt(compareKeys(a,b)))
def keyedAll(+collator: Collator,texts: List<&2,String>,reversed: List<&2,Keyed>) -> List<&2,Keyed>:
  match texts:
    case Nil{}: List.reverse(&2,Keyed,reversed)
    case +text <> rest: keyedAll(collator,rest,Keyed{key(collator,text),text} <> reversed)
def textsOf(values: List<&2,Keyed>,reversed: List<&2,String>) -> List<&2,String>:
  match values:
    case Nil{}: List.reverse(&2,String,reversed)
    case Keyed{_,text} <> rest: textsOf(rest,text <> reversed)
def sort(+collator: Collator,values: List<&2,String>) -> List<&2,String>: textsOf(Sort.sort(~Keyed,~keyedLe,keyedAll(collator,values,Nil{})),Nil{})

# ---- Data: packages/runtime/data/icu78-collation.bin (scripts/generate-collation.py)
# Little-endian records; each loop threads the remaining bytes and a validity flag.

type Bytes is Data: Bytes{rest: List<&2,U32>,ok: Bool}
def broken() -> Bytes: Bytes{Nil{},False{}}
def lowerOf(pairs: Table.Table<U32>,index: U32) -> U32: Maybe.default(&2,U32,Table.get(U32,pairs,index),0)
def word(a: U32,b: U32,c: U32,d: U32) -> U32: (a + b * 256 + c * 65536 + d * 16777216 : U32)
def weightOf(pairs: Table.Table<U32>,+value: U32) -> Weight: Weight{(value / 2048 : U32),lowerOf(pairs,(value % 2048 : U32))}
type Weights is Data: Weights{weights: List<&2,Weight>,bytes: Bytes}
def weightsLoop(count: Nat,+pairs: Table.Table<U32>,state: Weights) -> Weights:
  match count state:
    case Zero{} Weights{reversed,bytes}: Weights{List.reverse(&2,Weight,reversed),bytes}
    case Succ{left} Weights{reversed,Bytes{a <> b <> c <> d <> rest,ok}}: weightsLoop(left,pairs,Weights{weightOf(pairs,word(a,b,c,d)) <> reversed,Bytes{rest,ok}})
    case Succ{_} Weights{reversed,_}: Weights{reversed,broken()}
def readWeights(+pairs: Table.Table<U32>,bytes: Bytes) -> Weights:
  match bytes:
    case Bytes{count <> rest,ok}: weightsLoop(U32.to_nat(count),pairs,Weights{Nil{},Bytes{rest,ok}})
    case _: Weights{Nil{},broken()}
type Codes is Data: Codes{codes: List<&2,U32>,bytes: Bytes}
def codesLoop(count: Nat,state: Codes) -> Codes:
  match count state:
    case Zero{} Codes{reversed,bytes}: Codes{List.reverse(&2,U32,reversed),bytes}
    case Succ{left} Codes{reversed,Bytes{a <> b <> c <> rest,ok}}: codesLoop(left,Codes{word(a,b,c,0) <> reversed,Bytes{rest,ok}})
    case Succ{_} Codes{reversed,_}: Codes{reversed,broken()}

type Suffixes is Data: Suffixes{suffixes: List<&2,Suffix>,bytes: Bytes}
def suffixDone(codes: List<&2,U32>,found: Weights,reversed: List<&2,Suffix>) -> Suffixes:
  match found:
    case Weights{weights,bytes}: Suffixes{Suffix{codes,weights} <> reversed,bytes}
def suffixCodes(+pairs: Table.Table<U32>,found: Codes,reversed: List<&2,Suffix>) -> Suffixes:
  match found:
    case Codes{codes,bytes}: suffixDone(codes,readWeights(pairs,bytes),reversed)
def suffixStep(+pairs: Table.Table<U32>,state: Suffixes) -> Suffixes:
  match state:
    case Suffixes{reversed,Bytes{length <> rest,ok}}: suffixCodes(pairs,codesLoop(U32.to_nat(length),Codes{Nil{},Bytes{rest,ok}}),reversed)
    case Suffixes{reversed,_}: Suffixes{reversed,broken()}
def suffixesLoop(count: Nat,+pairs: Table.Table<U32>,state: Suffixes) -> Suffixes:
  match count state:
    case Zero{} Suffixes{reversed,bytes}: Suffixes{List.reverse(&2,Suffix,reversed),bytes}
    case Succ{left} state: suffixesLoop(left,pairs,suffixStep(pairs,state))
type Prefixes is Data: Prefixes{prefixes: List<&2,Prefix>,bytes: Bytes}
def prefixDone(code: U32,found: Weights,reversed: List<&2,Prefix>) -> Prefixes:
  match found:
    case Weights{weights,bytes}: Prefixes{Prefix{code,weights} <> reversed,bytes}
def prefixStep(+pairs: Table.Table<U32>,state: Prefixes) -> Prefixes:
  match state:
    case Prefixes{reversed,Bytes{a <> b <> c <> rest,ok}}: prefixDone(word(a,b,c,0),readWeights(pairs,Bytes{rest,ok}),reversed)
    case Prefixes{reversed,_}: Prefixes{reversed,broken()}
def prefixesLoop(count: Nat,+pairs: Table.Table<U32>,state: Prefixes) -> Prefixes:
  match count state:
    case Zero{} Prefixes{reversed,bytes}: Prefixes{List.reverse(&2,Prefix,reversed),bytes}
    case Succ{left} state: prefixesLoop(left,pairs,prefixStep(pairs,state))

type Mappings is Data: Mappings{entries: List<&2,Table.Entry<Mapping>>,bytes: Bytes}
def added(+code: U32,mapping: Mapping,reversed: List<&2,Table.Entry<Mapping>>,bytes: Bytes) -> Mappings: Mappings{Table.Entry{code,mapping} <> reversed,bytes}
def expansionBody(+code: U32,found: Weights,reversed: List<&2,Table.Entry<Mapping>>) -> Mappings:
  match found:
    case Weights{weights,bytes}: added(code,Expansion{code,weights},reversed,bytes)
def contractionDone(+code: U32,+flags: U32,fallback: List<&2,Weight>,found: Suffixes,reversed: List<&2,Table.Entry<Mapping>>) -> Mappings:
  match found:
    case Suffixes{suffixes,bytes}: added(code,Contraction{code,U32.is_ne(U32.and(flags,1),0),U32.is_ne(U32.and(flags,2),0),fallback,suffixes},reversed,bytes)
def contractionSuffixes(+pairs: Table.Table<U32>,+code: U32,flags: U32,found: Weights,reversed: List<&2,Table.Entry<Mapping>>) -> Mappings:
  match found:
    case Weights{fallback,Bytes{count <> rest,ok}}: contractionDone(code,flags,fallback,suffixesLoop(U32.to_nat(count),pairs,Suffixes{Nil{},Bytes{rest,ok}}),reversed)
    case _: Mappings{reversed,broken()}
def contractionBody(+pairs: Table.Table<U32>,+code: U32,bytes: Bytes,reversed: List<&2,Table.Entry<Mapping>>) -> Mappings:
  match bytes:
    case Bytes{flags <> rest,ok}: contractionSuffixes(pairs,code,flags,readWeights(pairs,Bytes{rest,ok}),reversed)
    case _: Mappings{reversed,broken()}
def prefixedDone(+code: U32,fallback: List<&2,Weight>,found: Prefixes,reversed: List<&2,Table.Entry<Mapping>>) -> Mappings:
  match found:
    case Prefixes{prefixes,bytes}: added(code,Prefixed{code,fallback,prefixes},reversed,bytes)
def prefixedBody(+pairs: Table.Table<U32>,+code: U32,found: Weights,reversed: List<&2,Table.Entry<Mapping>>) -> Mappings:
  match found:
    case Weights{fallback,Bytes{count <> rest,ok}}: prefixedDone(code,fallback,prefixesLoop(U32.to_nat(count),pairs,Prefixes{Nil{},Bytes{rest,ok}}),reversed)
    case _: Mappings{reversed,broken()}
def runBody(+pairs: Table.Table<U32>,+code: U32,bytes: Bytes,reversed: List<&2,Table.Entry<Mapping>>) -> Mappings:
  match bytes:
    case Bytes{a <> b <> c <> w <> x <> y <> z <> rest,ok}:
      +value = word(w,x,y,z)
      added(code,Run{code,word(a,b,c,0),(value / 2048 : U32),lowerOf(pairs,(value % 2048 : U32))},reversed,Bytes{rest,ok})
    case _: Mappings{reversed,broken()}
def mappingBody(kind: U32,+pairs: Table.Table<U32>,+code: U32,bytes: Bytes,reversed: List<&2,Table.Entry<Mapping>>) -> Mappings:
  match kind:
    case 0: runBody(pairs,code,bytes,reversed)
    case 1: expansionBody(code,readWeights(pairs,bytes),reversed)
    case 2: contractionBody(pairs,code,bytes,reversed)
    case _: prefixedBody(pairs,code,readWeights(pairs,bytes),reversed)
def mappingStep(+pairs: Table.Table<U32>,state: Mappings) -> Mappings:
  match state:
    case Mappings{reversed,Bytes{kind <> a <> b <> c <> rest,ok}}: mappingBody(kind,pairs,word(a,b,c,0),Bytes{rest,ok},reversed)
    case Mappings{reversed,_}: Mappings{reversed,broken()}
def mappingsLoop(count: Nat,+pairs: Table.Table<U32>,state: Mappings) -> Mappings:
  match count state:
    case Zero{} Mappings{reversed,bytes}: Mappings{List.reverse(&2,Table.Entry<Mapping>,reversed),bytes}
    case Succ{left} state: mappingsLoop(left,pairs,mappingStep(pairs,state))

type Values is Data: Values{entries: List<&2,Table.Entry<U32>>,bytes: Bytes}
def pairsLoop(count: Nat,+index: U32,state: Values) -> Values:
  match count state:
    case Zero{} Values{reversed,bytes}: Values{List.reverse(&2,Table.Entry<U32>,reversed),bytes}
    case Succ{left} Values{reversed,Bytes{a <> b <> c <> d <> rest,ok}}: pairsLoop(left,(index + 1 : U32),Values{Table.Entry{index,(c + d * 256 + (a + b * 256) * 65536 : U32)} <> reversed,Bytes{rest,ok}})
    case Succ{_} Values{reversed,_}: Values{reversed,broken()}
def leadsLoop(count: Nat,state: Values) -> Values:
  match count state:
    case Zero{} Values{reversed,bytes}: Values{List.reverse(&2,Table.Entry<U32>,reversed),bytes}
    case Succ{left} Values{reversed,Bytes{a <> b <> flags <> rest,ok}}: leadsLoop(left,Values{Table.Entry{word(a,b,0,0),flags} <> reversed,Bytes{rest,ok}})
    case Succ{_} Values{reversed,_}: Values{reversed,broken()}
type Spans is Data: Spans{entries: List<&2,Table.Entry<Span>>,bytes: Bytes}
def spanEntry(+first: U32,last: U32,value: U32) -> Table.Entry<Span>: Table.Entry{first,Span{first,last,value}}
# Han spans carry a u24 rank, combining classes a u8, FCD values a u16.
def hanLoop(count: Nat,state: Spans) -> Spans:
  match count state:
    case Zero{} Spans{reversed,bytes}: Spans{List.reverse(&2,Table.Entry<Span>,reversed),bytes}
    case Succ{left} Spans{reversed,Bytes{a <> b <> c <> d <> e <> f <> g <> h <> i <> rest,ok}}: hanLoop(left,Spans{spanEntry(word(a,b,c,0),word(d,e,f,0),word(g,h,i,0)) <> reversed,Bytes{rest,ok}})
    case Succ{_} Spans{reversed,_}: Spans{reversed,broken()}
def classLoop(count: Nat,state: Spans) -> Spans:
  match count state:
    case Zero{} Spans{reversed,bytes}: Spans{List.reverse(&2,Table.Entry<Span>,reversed),bytes}
    case Succ{left} Spans{reversed,Bytes{a <> b <> c <> d <> e <> f <> g <> rest,ok}}: classLoop(left,Spans{spanEntry(word(a,b,c,0),word(d,e,f,0),g) <> reversed,Bytes{rest,ok}})
    case Succ{_} Spans{reversed,_}: Spans{reversed,broken()}
def fcdLoop(count: Nat,state: Spans) -> Spans:
  match count state:
    case Zero{} Spans{reversed,bytes}: Spans{List.reverse(&2,Table.Entry<Span>,reversed),bytes}
    case Succ{left} Spans{reversed,Bytes{a <> b <> c <> d <> e <> f <> g <> h <> rest,ok}}: fcdLoop(left,Spans{spanEntry(word(a,b,c,0),word(d,e,f,0),word(g,h,0,0)) <> reversed,Bytes{rest,ok}})
    case Succ{_} Spans{reversed,_}: Spans{reversed,broken()}
type Decompositions is Data: Decompositions{entries: List<&2,Table.Entry<List<&2,U32>>>,bytes: Bytes}
def decompositionDone(code: U32,found: Codes,reversed: List<&2,Table.Entry<List<&2,U32>>>) -> Decompositions:
  match found:
    case Codes{codes,bytes}: Decompositions{Table.Entry{code,codes} <> reversed,bytes}
def decompositionStep(state: Decompositions) -> Decompositions:
  match state:
    case Decompositions{reversed,Bytes{a <> b <> c <> length <> rest,ok}}: decompositionDone(word(a,b,c,0),codesLoop(U32.to_nat(length),Codes{Nil{},Bytes{rest,ok}}),reversed)
    case Decompositions{reversed,_}: Decompositions{reversed,broken()}
def decompositionsLoop(count: Nat,state: Decompositions) -> Decompositions:
  match count state:
    case Zero{} Decompositions{reversed,bytes}: Decompositions{List.reverse(&2,Table.Entry<List<&2,U32>>,reversed),bytes}
    case Succ{left} state: decompositionsLoop(left,decompositionStep(state))

# Header: total size, hanBase, unassignedBase, common pair, then section counts.
type Header is Data: Header{size: U32,hanBase: U32,unassignedBase: U32,common: U32,pairs: U32,mappings: U32,han: U32,classes: U32,fcd: U32,decompositions: U32}
def headerLoop(count: Nat,state: Codes) -> Codes:
  match count state:
    case Zero{} Codes{reversed,bytes}: Codes{List.reverse(&2,U32,reversed),bytes}
    case Succ{left} Codes{reversed,Bytes{a <> b <> c <> d <> rest,ok}}: headerLoop(left,Codes{word(a,b,c,d) <> reversed,Bytes{rest,ok}})
    case Succ{_} Codes{reversed,_}: Codes{reversed,broken()}
def consumedAll(+size: U32,+length: U32,bytes: Bytes) -> Bool:
  match bytes:
    case Bytes{Nil{},ok}: ok && U32.is_eq(size,length)
    case _: False{}
def withLeads(+size: U32,+length: U32,header: Header,pairs: Table.Table<U32>,mappings: Table.Table<Mapping>,han: Table.Table<Span>,classes: Table.Table<Span>,fcd: Table.Table<Span>,decompositions: Table.Table<List<&2,U32>>,leads: Values) -> Maybe<&2,Collator>:
  match header leads:
    case Header{_,hanBase,unassignedBase,common,_,_,_,_,_,_} Values{entries,bytes}:
      Bool.pick(Unit -> Maybe<&2,Collator>,consumedAll(size,length,bytes),
        _ => Some{Collator{mappings,han,classes,fcd,decompositions,Table.fromSortedEntries(U32,entries),hanBase,unassignedBase,lowerOf(pairs,common)}},_ => None{})(Unit{})
def withDecompositions(+size: U32,+length: U32,header: Header,pairs: Table.Table<U32>,mappings: Table.Table<Mapping>,han: Table.Table<Span>,classes: Table.Table<Span>,fcd: Table.Table<Span>,found: Decompositions) -> Maybe<&2,Collator>:
  match found:
    case Decompositions{entries,Bytes{a <> b <> rest,ok}}: withLeads(size,length,header,pairs,mappings,han,classes,fcd,Table.fromSortedEntries(List<&2,U32>,entries),leadsLoop(U32.to_nat(word(a,b,0,0)),Values{Nil{},Bytes{rest,ok}}))
    case _: None{}
def withFcd(+size: U32,+length: U32,header: Header,pairs: Table.Table<U32>,mappings: Table.Table<Mapping>,han: Table.Table<Span>,classes: Table.Table<Span>,found: Spans) -> Maybe<&2,Collator>:
  match header found:
    case Header{a,b,c,d,e,f,g,h,i,+count} Spans{entries,bytes}:
      withDecompositions(size,length,Header{a,b,c,d,e,f,g,h,i,count},pairs,mappings,han,classes,Table.fromSortedEntries(Span,entries),decompositionsLoop(U32.to_nat(count),Decompositions{Nil{},bytes}))
def withClasses(+size: U32,+length: U32,header: Header,pairs: Table.Table<U32>,mappings: Table.Table<Mapping>,han: Table.Table<Span>,found: Spans) -> Maybe<&2,Collator>:
  match header found:
    case Header{a,b,c,d,e,f,g,h,+count,j} Spans{entries,bytes}:
      withFcd(size,length,Header{a,b,c,d,e,f,g,h,count,j},pairs,mappings,han,Table.fromSortedEntries(Span,entries),fcdLoop(U32.to_nat(count),Spans{Nil{},bytes}))
def withHan(+size: U32,+length: U32,header: Header,pairs: Table.Table<U32>,mappings: Table.Table<Mapping>,found: Spans) -> Maybe<&2,Collator>:
  match header found:
    case Header{a,b,c,d,e,f,g,+count,i,j} Spans{entries,bytes}:
      withClasses(size,length,Header{a,b,c,d,e,f,g,count,i,j},pairs,mappings,Table.fromSortedEntries(Span,entries),classLoop(U32.to_nat(count),Spans{Nil{},bytes}))
def withMappings(+size: U32,+length: U32,header: Header,pairs: Table.Table<U32>,found: Mappings) -> Maybe<&2,Collator>:
  match header found:
    case Header{a,b,c,d,e,f,+count,h,i,j} Mappings{entries,bytes}:
      withHan(size,length,Header{a,b,c,d,e,f,count,h,i,j},pairs,Table.fromSortedEntries(Mapping,entries),hanLoop(U32.to_nat(count),Spans{Nil{},bytes}))
def withPairs(+size: U32,+length: U32,header: Header,found: Values) -> Maybe<&2,Collator>:
  match header found:
    case Header{a,b,c,d,e,+count,g,h,i,j} Values{entries,bytes}:
      +pairs = Table.fromSortedEntries(U32,entries)
      withMappings(size,length,Header{a,b,c,d,e,count,g,h,i,j},pairs,mappingsLoop(U32.to_nat(count),pairs,Mappings{Nil{},bytes}))
def withHeader(+length: U32,found: Codes) -> Maybe<&2,Collator>:
  match found:
    case Codes{+size <> b <> c <> d <> +count <> f <> g <> h <> i <> j <> Nil{},bytes}:
      withPairs(size,length,Header{size,b,c,d,count,f,g,h,i,j},pairsLoop(U32.to_nat(count),0,Values{Nil{},bytes}))
    case _: None{}
def byteCount(bytes: List<&2,U32>,+count: U32) -> U32:
  match bytes:
    case Nil{}: count
    case _ <> rest: byteCount(rest,(count + 1 : U32))
# Decode ICUCOL01; None for any structural mismatch (magic, sizes, trailing data).
def decode(+bytes: List<&2,U32>) -> Maybe<&2,Collator>:
  match bytes:
    case 73 <> 67 <> 85 <> 67 <> 79 <> 76 <> 48 <> 49 <> rest: withHeader(byteCount(bytes,0),headerLoop(10n,Codes{Nil{},Bytes{rest,True{}}}))
    case _: None{}

type LoadError is Data: ReadFailed{path: String,cause: FS.Error} InvalidAsset{path: String}
def checkedAsset(path: String,decoded: Maybe<&2,Collator>) -> Result<&2,&2,LoadError,Collator>:
  match decoded:
    case Some{collator}: Done{collator}
    case None{}: Fail{InvalidAsset{path}}
def loaded(path: String,read: Result<&2,&2,FS.Error,List<&2,U32>>) -> Result<&2,&2,LoadError,Collator>:
  match read:
    case Fail{cause}: Fail{ReadFailed{path,cause}}
    case Done{bytes}: checkedAsset(path,decode(bytes))
# The caller supplies the installed data directory (packages/runtime/data).
def load(directory: String) -> IO(Result<&2,&2,LoadError,Collator>):
  +path = directory ++ "/icu78-collation.bin"
  do IO<Result<&2,&2,LoadError,Collator>>:
    read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return loaded(path,read)
