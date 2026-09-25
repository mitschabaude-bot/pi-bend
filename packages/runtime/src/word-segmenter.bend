import Base
import ./word-rules.bend as Rules
import ./cjk-dictionary.bend as Dictionary
import ./cjk-word-break.bend as Cjk
import ./sea-word-break.bend as Sea
import ./sea-word-data.bend as SeaData
import ./filesystem.bend as FS

# ICU78 word rules with preloaded CJK and Southeast Asian dictionaries.
# The pinned reference runtime has no Thai/Myanmar LSTM model resources.
# Dictionaries are optional: an engine is loaded when text of its script is
# first segmented (see `readyFor`), as ICU loads dictionary data lazily.
type Context is Data: Context{rules: Rules.Rules,cjk: Maybe<&2,Cjk.Context>,khmer: Maybe<&2,Sea.Context>,lao: Maybe<&2,Sea.Context>,thai: Maybe<&2,Sea.Context>,myanmar: Maybe<&2,Sea.Context>}
type Segment is Data: Segment{text: String,isWordLike: Bool,status: U32}
type Error is Data: MissingEngine{language: String} InvalidState{}
def ResultOf(-A: Data) -> Data: Result<&2,&2,Error,A>
def create(rules: Rules.Rules,dictionary: Dictionary.Trie,khmer: Dictionary.Trie,lao: Dictionary.Trie,thai: Dictionary.Trie,myanmar: Dictionary.Trie) -> Context:
  Context{rules,Some{Cjk.create(dictionary)},Some{Sea.Context{SeaData.Khmer{},khmer}},Some{Sea.Context{SeaData.Lao{},lao}},Some{Sea.Context{SeaData.Thai{},thai}},Some{Sea.Context{SeaData.Myanmar{},myanmar}}}
def rulesOnly(rules: Rules.Rules) -> Context: Context{rules,None{},None{},None{},None{},None{}}

type LoadError is Data:
  ReadFailed{path: String,cause: FS.Error}
  InvalidAsset{path: String}
def Loaded(-A: Data) -> Data: Result<&2,&2,LoadError,A>
def checkedTrie(path: String,result: Dictionary.Parsed(Dictionary.Trie)) -> Loaded(Dictionary.Trie):
  match result:
    case Done{trie}: Done{trie}
    case Fail{_}: Fail{InvalidAsset{path}}
def decodedTrie(path: String,decode: List<&2,U32> -> Dictionary.Parsed(Dictionary.Trie),read: Result<&2,&2,FS.Error,List<&2,U32>>) -> Loaded(Dictionary.Trie):
  match read:
    case Fail{cause}: Fail{ReadFailed{path,cause}}
    case Done{bytes}: checkedTrie(path,decode(bytes))
def loadTrie(+path: String,decode: List<&2,U32> -> Dictionary.Parsed(Dictionary.Trie)) -> IO(Loaded(Dictionary.Trie)):
  do IO<Loaded(Dictionary.Trie)>:
    read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return decodedTrie(path,decode,read)
def checkedRules(path: String,result: Rules.Parsed(Rules.Rules)) -> Loaded(Rules.Rules):
  match result:
    case Done{rules}: Done{rules}
    case Fail{_}: Fail{InvalidAsset{path}}
def decodedRules(path: String,read: Result<&2,&2,FS.Error,List<&2,U32>>) -> Loaded(Rules.Rules):
  match read:
    case Fail{cause}: Fail{ReadFailed{path,cause}}
    case Done{bytes}: checkedRules(path,Rules.decode(bytes))
def loadRules(+path: String) -> IO(Loaded(Rules.Rules)):
  do IO<Loaded(Rules.Rules)>:
    read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
    return decodedRules(path,read)
def assembled(cjk: Loaded(Dictionary.Trie),khmer: Loaded(Dictionary.Trie),lao: Loaded(Dictionary.Trie),thai: Loaded(Dictionary.Trie),myanmar: Loaded(Dictionary.Trie),rules: Loaded(Rules.Rules)) -> Loaded(Context):
  match cjk khmer lao thai myanmar rules:
    case Fail{error} _ _ _ _ _: Fail{error}
    case _ Fail{error} _ _ _ _: Fail{error}
    case _ _ Fail{error} _ _ _: Fail{error}
    case _ _ _ Fail{error} _ _: Fail{error}
    case _ _ _ _ Fail{error} _: Fail{error}
    case _ _ _ _ _ Fail{error}: Fail{error}
    case Done{cjk} Done{khmer} Done{lao} Done{thai} Done{myanmar} Done{rules}: Done{create(rules,cjk,khmer,lao,thai,myanmar)}
# The caller supplies the installed data directory. All six versioned assets
# are required; a missing or corrupt engine is an initialization error.
def loadDefault(+directory: String) -> IO(Loaded(Context)):
  do IO<Loaded(Context)>:
    cjk : Loaded(Dictionary.Trie) <- loadTrie(directory ++ "/icu78-cjk.bin",Dictionary.decode)
    khmer : Loaded(Dictionary.Trie) <- loadTrie(directory ++ "/icu78-khmer.bin",SeaData.decodeKhmer)
    lao : Loaded(Dictionary.Trie) <- loadTrie(directory ++ "/icu78-lao.bin",SeaData.decodeLao)
    thai : Loaded(Dictionary.Trie) <- loadTrie(directory ++ "/icu78-thai.bin",SeaData.decodeThai)
    myanmar : Loaded(Dictionary.Trie) <- loadTrie(directory ++ "/icu78-burmese.bin",SeaData.decodeMyanmar)
    rules : Loaded(Rules.Rules) <- loadRules(directory ++ "/icu78-word-rules.bin")
    return assembled(cjk,khmer,lao,thai,myanmar,rules)

# Word data is read when a word command first needs it, as ICU loads its data
# lazily: the rules first, and each dictionary when text of its script is
# segmented (decoding all of them costs about as much as the rest of startup).
type Source is Data:
  Pending{directory: String}
  Ready{context: Context,directory: String}
  Unavailable{error: LoadError}
def rulesSource(+directory: String,loaded: Loaded(Rules.Rules)) -> Source:
  match loaded:
    case Done{rules}: Ready{rulesOnly(rules),directory}
    case Fail{error}: Unavailable{error}
def ready(source: Source) -> IO(Source):
  match source:
    case Pending{+directory}:
      do IO<Source>:
        loaded : Loaded(Rules.Rules) <- loadRules(directory ++ "/icu78-word-rules.bin")
        return rulesSource(directory,loaded)
    case source: IO.pure(Source,source)

# The dictionary engines text needs: rules route dictionary characters to CJK
# (kinds 1, 2, 7), Thai (3), Lao (4), Myanmar (5) or Khmer (6).
type Needs is Data: Needs{cjk: Bool,khmer: Bool,lao: Bool,thai: Bool,myanmar: Bool}
def needed(needs: Needs,+properties: U32) -> Needs:
  match needs:
    case Needs{cjk,khmer,lao,thai,myanmar}:
      +dictionary = U32.is_ge((properties % 256: U32),24)
      +kind = (properties / 256: U32)
      Needs{cjk || (dictionary && (U32.is_eq(kind,1) || U32.is_eq(kind,2) || U32.is_eq(kind,7))),khmer || (dictionary && U32.is_eq(kind,6)),lao || (dictionary && U32.is_eq(kind,4)),thai || (dictionary && U32.is_eq(kind,3)),myanmar || (dictionary && U32.is_eq(kind,5))}
def needsIn(text: String,+rules: Rules.Rules,needs: Needs) -> Needs:
  match text:
    case SNil{}: needs
    case SCon{char,rest}: needsIn(rest,rules,needed(needs,Rules.properties(rules,char)))
def loadedCjk(+wanted: Bool,current: Maybe<&2,Cjk.Context>,+directory: String) -> IO(Loaded(Maybe<&2,Cjk.Context>)):
  match current:
    case Some{value}: IO.pure(Loaded(Maybe<&2,Cjk.Context>),Done{Some{value}})
    case None{}:
      Bool.pick(Unit -> IO(Loaded(Maybe<&2,Cjk.Context>)),wanted,
        _ => do IO<Loaded(Maybe<&2,Cjk.Context>)>:
          trie : Loaded(Dictionary.Trie) <- loadTrie(directory ++ "/icu78-cjk.bin",Dictionary.decode)
          return Result.map(&2,&2,LoadError,Dictionary.Trie,Maybe<&2,Cjk.Context>,value => Some{Cjk.create(value)},trie),
        _ => IO.pure(Loaded(Maybe<&2,Cjk.Context>),Done{None{}}))(Unit{})
def seaFile(language: SeaData.Language) -> String:
  match language:
    case SeaData.Khmer{}: "/icu78-khmer.bin"
    case SeaData.Lao{}: "/icu78-lao.bin"
    case SeaData.Thai{}: "/icu78-thai.bin"
    case SeaData.Myanmar{}: "/icu78-burmese.bin"
def seaDecoded(language: SeaData.Language,bytes: List<&2,U32>) -> Dictionary.Parsed(Dictionary.Trie):
  match language:
    case SeaData.Khmer{}: SeaData.decodeKhmer(bytes)
    case SeaData.Lao{}: SeaData.decodeLao(bytes)
    case SeaData.Thai{}: SeaData.decodeThai(bytes)
    case SeaData.Myanmar{}: SeaData.decodeMyanmar(bytes)
def seaTrie(+language: SeaData.Language,+path: String,read: Result<&2,&2,FS.Error,List<&2,U32>>) -> Loaded(Dictionary.Trie):
  match read:
    case Fail{cause}: Fail{ReadFailed{path,cause}}
    case Done{bytes}: checkedTrie(path,seaDecoded(language,bytes))
def loadedSea(+language: SeaData.Language,+wanted: Bool,current: Maybe<&2,Sea.Context>,+directory: String) -> IO(Loaded(Maybe<&2,Sea.Context>)):
  match current:
    case Some{value}: IO.pure(Loaded(Maybe<&2,Sea.Context>),Done{Some{value}})
    case None{}:
      Bool.pick(Unit -> IO(Loaded(Maybe<&2,Sea.Context>)),wanted,
        _ => do IO<Loaded(Maybe<&2,Sea.Context>)>:
          +path : String <- IO.pure(String,directory ++ seaFile(language))
          read : Result<&2,&2,FS.Error,List<&2,U32>> <- FS.readFile(path)
          return Result.map(&2,&2,LoadError,Dictionary.Trie,Maybe<&2,Sea.Context>,value => Some{Sea.Context{language,value}},seaTrie(language,path,read)),
        _ => IO.pure(Loaded(Maybe<&2,Sea.Context>),Done{None{}}))(Unit{})
def withEngines(rules: Rules.Rules,+directory: String,cjk: Loaded(Maybe<&2,Cjk.Context>),khmer: Loaded(Maybe<&2,Sea.Context>),lao: Loaded(Maybe<&2,Sea.Context>),thai: Loaded(Maybe<&2,Sea.Context>),myanmar: Loaded(Maybe<&2,Sea.Context>)) -> Source:
  match cjk khmer lao thai myanmar:
    case Fail{error} _ _ _ _: Unavailable{error}
    case _ Fail{error} _ _ _: Unavailable{error}
    case _ _ Fail{error} _ _: Unavailable{error}
    case _ _ _ Fail{error} _: Unavailable{error}
    case _ _ _ _ Fail{error}: Unavailable{error}
    case Done{cjk} Done{khmer} Done{lao} Done{thai} Done{myanmar}: Ready{Context{rules,cjk,khmer,lao,thai,myanmar},directory}
def withNeeds(context: Context,+directory: String,needs: Needs) -> IO(Source):
  match context needs:
    case Context{+rules,cjk,khmer,lao,thai,myanmar} Needs{wantCjk,wantKhmer,wantLao,wantThai,wantMyanmar}:
      do IO<Source>:
        cjk : Loaded(Maybe<&2,Cjk.Context>) <- loadedCjk(wantCjk,cjk,directory)
        khmer : Loaded(Maybe<&2,Sea.Context>) <- loadedSea(SeaData.Khmer{},wantKhmer,khmer,directory)
        lao : Loaded(Maybe<&2,Sea.Context>) <- loadedSea(SeaData.Lao{},wantLao,lao,directory)
        thai : Loaded(Maybe<&2,Sea.Context>) <- loadedSea(SeaData.Thai{},wantThai,thai,directory)
        myanmar : Loaded(Maybe<&2,Sea.Context>) <- loadedSea(SeaData.Myanmar{},wantMyanmar,myanmar,directory)
        return withEngines(rules,directory,cjk,khmer,lao,thai,myanmar)
def rulesOf(context: Context) -> Rules.Rules:
  match context: case Context{rules,_,_,_,_,_}: rules
def readiedFor(source: Source,+text: String) -> IO(Source):
  match source:
    case Ready{+context,+directory}: withNeeds(context,directory,needsIn(text,rulesOf(context),Needs{False{},False{},False{},False{},False{}}))
    case source: IO.pure(Source,source)
def loadedFor(need: Bool,present: Bool) -> Bool: Bool.not(need) || present
def coveredBy(needs: Needs,cjk: Maybe<&2,Cjk.Context>,khmer: Maybe<&2,Sea.Context>,lao: Maybe<&2,Sea.Context>,thai: Maybe<&2,Sea.Context>,myanmar: Maybe<&2,Sea.Context>) -> Bool:
  match needs:
    case Needs{a,b,c,d,e}: loadedFor(a,Maybe.is_some(&2,Cjk.Context,cjk)) && loadedFor(b,Maybe.is_some(&2,Sea.Context,khmer)) && loadedFor(c,Maybe.is_some(&2,Sea.Context,lao)) && loadedFor(d,Maybe.is_some(&2,Sea.Context,thai)) && loadedFor(e,Maybe.is_some(&2,Sea.Context,myanmar))
# Whether every dictionary `text` needs is loaded.
def covers(context: Context,text: String) -> Bool:
  match context:
    case Context{+rules,cjk,khmer,lao,thai,myanmar}: coveredBy(needsIn(text,rules,Needs{False{},False{},False{},False{},False{}}),cjk,khmer,lao,thai,myanmar)
# The source ready to segment `text`: rules, and the dictionaries its scripts use.
def readyFor(source: Source,text: String) -> IO(Source):
  do IO<Source>:
    +loaded : Source <- ready(source)
    readiedFor(loaded,text)

type Mode is Data: Outside{} CjkRange{} KoreanRange{} KhmerRange{} LaoRange{} ThaiRange{} MyanmarRange{}
type DictionaryScan is Data:
  Active{position: Nat,start: Nat,mode: Mode,reversed: String,breaks: List<&2,Nat>}
  Failed{error: Error}
def internalBreaks(ends: List<&2,Nat>,+start: Nat,reversed: List<&2,Nat>) -> List<&2,Nat>:
  match ends:
    case Nil{}: reversed
    case _ <> Nil{}: reversed
    case endpoint <> rest: internalBreaks(rest,start,(start + endpoint) <> reversed)
# An engine not loaded for this text leaves the range whole.
def seaEnds(engine: Maybe<&2,Sea.Context>,text: String) -> List<&2,Nat>:
  match engine:
    case Some{value}: Sea.boundaries(value,text)
    case None{}: Nil{}
def cjkEnds(engine: Maybe<&2,Cjk.Context>,text: String) -> List<&2,Nat>:
  match engine:
    case Some{value}: Cjk.boundaries(value,text)
    case None{}: Nil{}
def rangeEnds(context: Context,mode: Mode,text: String) -> List<&2,Nat>:
  match context mode:
    case Context{_,_,khmer,_,_,_} KhmerRange{}: seaEnds(khmer,text)
    case Context{_,_,_,lao,_,_} LaoRange{}: seaEnds(lao,text)
    case Context{_,_,_,_,thai,_} ThaiRange{}: seaEnds(thai,text)
    case Context{_,_,_,_,_,myanmar} MyanmarRange{}: seaEnds(myanmar,text)
    case Context{_,cjk,_,_,_,_} _: cjkEnds(cjk,text)
def flush(context: Context,mode: Mode,start: Nat,reversed: String,breaks: List<&2,Nat>) -> List<&2,Nat>:
  match reversed:
    case SNil{}: breaks
    case SCon{char,rest}: internalBreaks(rangeEnds(context,mode,String.reverse(SCon{char,rest})),start,breaks)
def continues(mode: Mode,char: Char) -> Bool:
  match mode:
    case Outside{}: False{}
    case CjkRange{}: Cjk.handles(char)
    case KoreanRange{}: Cjk.hangul(char)
    case KhmerRange{}: SeaData.handles(SeaData.Khmer{},char)
    case LaoRange{}: SeaData.handles(SeaData.Lao{},char)
    case ThaiRange{}: SeaData.handles(SeaData.Thai{},char)
    case MyanmarRange{}: SeaData.handles(SeaData.Myanmar{},char)
def engine(kind: U32,char: Char,+position: Nat,breaks: List<&2,Nat>) -> DictionaryScan:
  match kind:
    case 1: Active{Succ{position},position,CjkRange{},SCon{char,""},breaks}
    case 2: Active{Succ{position},position,KoreanRange{},SCon{char,""},breaks}
    case 3: Active{Succ{position},position,ThaiRange{},SCon{char,""},breaks}
    case 4: Active{Succ{position},position,LaoRange{},SCon{char,""},breaks}
    case 5: Active{Succ{position},position,MyanmarRange{},SCon{char,""},breaks}
    case 6: Active{Succ{position},position,KhmerRange{},SCon{char,""},breaks}
    case 7: Active{Succ{position},position,CjkRange{},SCon{char,""},breaks}
    case _: Active{Succ{position},Succ{position},Outside{},"",breaks}
def begin(+properties: U32,+char: Char,+position: Nat,+breaks: List<&2,Nat>) -> DictionaryScan:
  Bool.pick(Unit -> DictionaryScan,U32.is_ge((properties % 256: U32),24),
    _ => engine((properties / 256: U32),char,position,breaks),
    _ => Active{Succ{position},Succ{position},Outside{},"",breaks})(Unit{})
def properties(context: Context,char: Char) -> U32:
  match context:
    case Context{rules,_,_,_,_,_}: Rules.properties(rules,char)
def feed(+context: Context,+char: Char,value: DictionaryScan) -> DictionaryScan:
  match value:
    case Failed{error}: Failed{error}
    case Active{+position,+start,+mode,+reversed,+breaks}:
      Bool.pick(Unit -> DictionaryScan,continues(mode,char),
        _ => Active{Succ{position},start,mode,SCon{char,reversed},breaks},
        _ => begin(properties(context,char),char,position,flush(context,mode,start,reversed,breaks)))(Unit{})
def finish(+context: Context,value: DictionaryScan) -> ResultOf(List<&2,Nat>):
  match value:
    case Failed{error}: Fail{error}
    case Active{position,start,mode,reversed,breaks}:
      Done{List.reverse(&2,Nat,position <> flush(context,mode,start,reversed,breaks))}
def dictionaryBreaks(text: String,+context: Context,value: DictionaryScan) -> ResultOf(List<&2,Nat>):
  match text value:
    case _ Failed{error}: Fail{error}
    case SNil{} value: finish(context,value)
    case SCon{char,rest} value: dictionaryBreaks(rest,context,feed(context,char,value))

type Cut is Data: Cut{text: String,rest: String}
type Pieces is Data: Pieces{rest: String,reversed: List<&2,Segment>}
def cut(count: Nat,text: String,reversed: String) -> Cut:
  match count text:
    case Zero{} text: Cut{String.reverse(reversed),text}
    case Succ{left} SCon{char,rest}: cut(left,rest,SCon{char,reversed})
    case _ SNil{}: Cut{String.reverse(reversed),""}
def piece(value: Cut,+status: U32,reversed: List<&2,Segment>) -> Pieces:
  match value:
    case Cut{text,rest}: Pieces{rest,Segment{text,U32.is_ge(status,100) && U32.is_lt(status,500),status} <> reversed}
def take(endpoint: Nat,previous: Nat,status: U32,value: Pieces) -> Pieces:
  match value:
    case Pieces{text,reversed}: piece(cut(endpoint - previous,text,""),status,reversed)
def split(ends: List<&2,Nat>,previous: Nat,+status: U32,value: Pieces) -> Pieces:
  match ends:
    case Nil{}: value
    case +endpoint <> rest: split(rest,endpoint,status,take(endpoint,previous,status,value))

type Work is Data: Work{rest: String,reversed: List<&2,Segment>}
def rejoined(value: Pieces,rest: String) -> ResultOf(Work):
  match value:
    case Pieces{SNil{},reversed}: Done{Work{rest,reversed}}
    case _: Fail{InvalidState{}}
def subdivided(result: ResultOf(List<&2,Nat>),text: String,rest: String,status: U32,reversed: List<&2,Segment>) -> ResultOf(Work):
  match result:
    case Fail{error}: Fail{error}
    case Done{ends}: rejoined(split(ends,0n,status,Pieces{text,reversed}),rest)
def region(context: Context,value: Maybe<&2,Rules.Region>,reversed: List<&2,Segment>) -> ResultOf(Work):
  match value:
    case None{}: Done{Work{"",reversed}}
    case Some{Rules.Region{+text,+rest,+length,+status,dictionary}}:
      +reversed = {reversed: List<&2,Segment>}
      Bool.pick(Unit -> ResultOf(Work),dictionary && Nat.is_gt(length,1n),
        _ => subdivided(dictionaryBreaks(text,context,Active{0n,0n,Outside{},"",Nil{}}),text,rest,status,reversed),
        _ => Done{Work{rest,Segment{text,U32.is_ge(status,100) && U32.is_lt(status,500),status} <> reversed}})(Unit{})
def next(+context: Context,value: Work) -> ResultOf(Work):
  match context value:
    case Context{rules,_,_,_,_,_} Work{text,reversed}: region(context,Rules.next(rules,text),reversed)
def segmentsLoop(fuel: Nat,+context: Context,result: ResultOf(Work)) -> ResultOf(List<&2,Segment>):
  match fuel result:
    case _ Fail{error}: Fail{error}
    case _ Done{Work{SNil{},reversed}}: Done{List.reverse(&2,Segment,reversed)}
    case Succ{left} Done{work}: segmentsLoop(left,context,next(context,work))
    case Zero{} _: Fail{InvalidState{}}
def segments(+context: Context,+text: String) -> ResultOf(List<&2,Segment>):
  segmentsLoop(String.length(text),context,Done{Work{text,Nil{}}})
