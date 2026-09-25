import Base
import ../../runtime/src/string.bend as Strings
import ../../runtime/src/grapheme.bend as Grapheme
import ../../runtime/src/callback.bend as Callback
import ../../runtime/src/unicode-17-display.bend as Display

# Complete terminal controls are distinct from visible text. Offsets count
# Unicode scalars, matching Bend strings rather than UTF-16 code units.
type AnsiCode is Data: AnsiCode{code: String,length: Nat}
type Token is Data: Token{text: String,control: Bool}
type Scan is Data: Scan{token: Token,rest: String,length: Nat}
def prependReversed(text: String,reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{char,rest}: prependReversed(rest,SCon{char,reversed})
def reverseInto(text: String,result: String) -> String:
  match text:
    case SNil{}: result
    case SCon{char,rest}: reverseInto(rest,SCon{char,result})
def scanned(reversed: String,control: Bool,rest: String,length: Nat) -> Scan:
  Scan{Token{reverseInto(reversed,""),control},rest,length}
def range(+point: U32,low: U32,high: U32) -> Bool: U32.is_ge(point,low) && U32.is_le(point,high)
# ECMA-48 CSI parameters precede intermediates and one final byte. `step`
# classifies the next character: 0 parameter/intermediate, 1 final, 2 other.
def csiStep(text: String,intermediate: Bool) -> U32:
  match text:
    case SNil{}: 2
    case SCon{char,_}:
      +point = Char.to_u32(char)
      Bool.pick(U32,range(point,64,126),1,Bool.pick(U32,range(point,32,47) || (Bool.not(intermediate) && range(point,48,63)),0,2))
def csi(text: String,step: U32,+reversed: String,+length: Nat,+intermediate: Bool) -> Scan:
  match text step:
    case SCon{+char,+rest} 0:
      +next = intermediate || range(Char.to_u32(char),32,47)
      csi(rest,csiStep(rest,next),SCon{char,reversed},length + 1n,next)
    case SCon{char,rest} 1: scanned(SCon{char,reversed},True{},rest,length + 1n)
    case text _: scanned(reversed,False{},text,length)
def stringControl(text: String,reversed: String,length: Nat) -> Scan:
  match text:
    case SNil{}: scanned(reversed,False{},"",length)
    case SCon{Chr{7},rest}: scanned(SCon{Chr{7},reversed},True{},rest,length + 1n)
    case SCon{Chr{27},SCon{'\\',rest}}: scanned(SCon{'\\',SCon{Chr{27},reversed}},True{},rest,length + 2n)
    case SCon{char,rest}: stringControl(rest,SCon{char,reversed},length + 1n)
def scanPlain(text: String,reversed: String,length: Nat) -> Scan:
  match text:
    case SNil{}: scanned(reversed,False{},"",length)
    case SCon{Chr{27},rest}: scanned(reversed,False{},SCon{Chr{27},rest},length)
    case SCon{char,rest}: scanPlain(rest,SCon{char,reversed},length + 1n)
def scan(text: String) -> Scan:
  match text:
    case SCon{Chr{27},SCon{'[',+rest}}: csi(rest,csiStep(rest,False{}),"[\u{1b}",2n,False{})
    case SCon{Chr{27},SCon{']',rest}}: stringControl(rest,"]\u{1b}",2n)
    case SCon{Chr{27},SCon{'_',rest}}: stringControl(rest,"_\u{1b}",2n)
    case SCon{char,rest}: scanPlain(rest,SCon{char,SNil{}},1n)
    case SNil{}: Scan{Token{"",False{}},"",0n}
def extracted(value: Scan) -> Maybe<&2,AnsiCode>:
  match value:
    case Scan{Token{code,True{}},_,length}: Some{AnsiCode{code,length}}
    case _: None{}
def extractFirst(text: String) -> Maybe<&2,AnsiCode>:
  match text:
    case SCon{Chr{27},rest}: extracted(scan(SCon{Chr{27},rest}))
    case _: None{}
def extractAnsiCode(text: String,position: Nat) -> Maybe<&2,AnsiCode>:
  match text position:
    case text Zero{}: extractFirst(text)
    case SCon{_,rest} Succ{position}: extractAnsiCode(rest,position)
    case _ _: None{}
@unsafe def scanTokens(value: Scan,reversed: List<&2,Token>) -> List<&2,Token>:
  match value:
    case Scan{_,_,Zero{}}: List.reverse(&2,Token,reversed)
    case Scan{token,rest,_}: scanTokens(scan(rest),token <> reversed)
def tokens(text: String) -> List<&2,Token>: scanTokens(scan(text),Nil{})
def visibleNormalized(text: String,reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{'\t',rest}: visibleNormalized(rest,prependReversed("   ",reversed))
    case SCon{Chr{3635},rest}: visibleNormalized(rest,SCon{Chr{3634},SCon{Chr{3661},reversed}})
    case SCon{Chr{3763},rest}: visibleNormalized(rest,SCon{Chr{3762},SCon{Chr{3789},reversed}})
    case SCon{char,rest}: visibleNormalized(rest,SCon{char,reversed})
def renderToken(value: Token,strip: Bool,+reversed: String) -> String:
  match value:
    case Token{+text,False{}}: Bool.pick(Unit -> String,strip,_ => prependReversed(text,reversed),_ => visibleNormalized(text,reversed))(Unit{})
    case Token{text,True{}}: Bool.pick(Unit -> String,strip,_ => reversed,_ => prependReversed(text,reversed))(Unit{})
def renderTokens(items: List<&2,Token>,+strip: Bool,reversed: String) -> String:
  match items:
    case Nil{}: reverseInto(reversed,"")
    case item <> rest: renderTokens(rest,strip,renderToken(item,strip,reversed))
def stripTerminalSequences(text: String) -> String: renderTokens(tokens(text),True{},"")
def normalizeTerminalOutput(text: String) -> String: renderTokens(tokens(text),False{},"")

# Style state is immutable; SGR reset leaves an OSC-8 link open.
type Osc8Terminator is Data: Bell{} StringTerminator{}
type ActiveHyperlink is Data: ActiveHyperlink{params: String,url: String,terminator: Osc8Terminator}
type HyperlinkChange is Data: Unchanged{} Closed{} Opened{link: ActiveHyperlink}
type AnsiCodeTracker is Data:
  AnsiCodeTracker{attributes: U32,foreground: Maybe<&2,String>,background: Maybe<&2,String>,hyperlink: Maybe<&2,ActiveHyperlink>}
def emptyTracker() -> AnsiCodeTracker: AnsiCodeTracker{0,None{},None{},None{}}
def terminator(value: Osc8Terminator) -> String:
  match value:
    case Bell{}: "\u{7}"
    case StringTerminator{}: "\u{1b}\\"
def formatOsc8Hyperlink(value: ActiveHyperlink) -> String:
  match value:
    case ActiveHyperlink{params,url,ending}: "\u{1b}]8;" ++ params ++ ";" ++ url ++ terminator(ending)
def formatOsc8Close(ending: Osc8Terminator) -> String: "\u{1b}]8;;" ++ terminator(ending)
def hyperlink(params: String,url: String,ending: Osc8Terminator) -> HyperlinkChange:
  match url:
    case SNil{}: Closed{}
    case url: Opened{ActiveHyperlink{params,url,ending}}
def hyperlinkBody(text: String,params: String,url: String) -> HyperlinkChange:
  match text:
    case SCon{Chr{7},SNil{}}: hyperlink(params,reverseInto(url,""),Bell{})
    case SCon{Chr{27},SCon{'\\',SNil{}}}: hyperlink(params,reverseInto(url,""),StringTerminator{})
    case SCon{char,rest}: hyperlinkBody(rest,params,SCon{char,url})
    case _: Unchanged{}
def hyperlinkParams(text: String,reversed: String) -> HyperlinkChange:
  match text:
    case SCon{';',rest}: hyperlinkBody(rest,reverseInto(reversed,""),"")
    case SCon{Chr{7},_}: Unchanged{}
    case SCon{Chr{27},_}: Unchanged{}
    case SCon{char,rest}: hyperlinkParams(rest,SCon{char,reversed})
    case _: Unchanged{}
def parseOsc8Hyperlink(text: String) -> HyperlinkChange:
  match text:
    case SCon{Chr{27},SCon{']',SCon{'8',SCon{';',rest}}}}: hyperlinkParams(rest,"")
    case _: Unchanged{}
def withLink(change: HyperlinkChange,state: AnsiCodeTracker) -> AnsiCodeTracker:
  match change state:
    case Unchanged{} state: state
    case Closed{} AnsiCodeTracker{flags,fg,bg,_}: AnsiCodeTracker{flags,fg,bg,None{}}
    case Opened{link} AnsiCodeTracker{flags,fg,bg,_}: AnsiCodeTracker{flags,fg,bg,Some{link}}
def reset(state: AnsiCodeTracker) -> AnsiCodeTracker:
  match state:
    case AnsiCodeTracker{_,_,_,link}: AnsiCodeTracker{0,None{},None{},link}
def clear(state: AnsiCodeTracker) -> AnsiCodeTracker: emptyTracker()
def decimal(text: String,+value: U32) -> Maybe<&2,U32>:
  match text:
    case SNil{}: Some{value}
    case SCon{+char,rest}:
      Bool.pick(Unit -> Maybe<&2,U32>,Char.is_digit(char) && (U32.is_lt(value,429496729) || (U32.is_eq(value,429496729) && U32.is_le(Char.to_u32(char),53))),
        _ => decimal(rest,U32.add(U32.mul(value,10),U32.sub(Char.to_u32(char),48))),_ => None{})(Unit{})
type Parameter is Data: Parameter{value: U32,text: String}
def parameters(values: List<&2,String>,reversed: List<&2,Parameter>) -> Maybe<&2,List<&2,Parameter>>:
  match values:
    case Nil{}: Some{List.reverse(&2,Parameter,reversed)}
    case +value <> rest: Maybe.bind(&2,U32,List<&2,Parameter>,decimal(value,0),number => parameters(rest,Parameter{number,value} <> reversed))
def sgrBody(text: String,+reversed: String) -> Maybe<&2,String>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,String>,Char.is_eq(char,'m') && String.is_empty(rest),
        _ => Some{reverseInto(reversed,"")},
        _ => Bool.pick(Unit -> Maybe<&2,String>,Char.is_digit(char) || Char.is_eq(char,';'),_ => sgrBody(rest,SCon{char,reversed}),_ => None{})(Unit{}))(Unit{})
def sgrParameters(text: String) -> Maybe<&2,List<&2,Parameter>>:
  match text:
    case SCon{Chr{27},SCon{'[',rest}}: Maybe.bind(&2,String,List<&2,Parameter>,sgrBody(rest,""),body => parameters(Strings.split(body,';'),Nil{}))
    case _: None{}
def setAttribute(+bit: U32,enabled: Bool,state: AnsiCodeTracker) -> AnsiCodeTracker:
  match state:
    case AnsiCodeTracker{+flags,fg,bg,link}: AnsiCodeTracker{Bool.pick(U32,enabled,U32.or(flags,bit),U32.and(flags,U32.xor(bit,4294967295))),fg,bg,link}
def setColor(background: Bool,color: Maybe<&2,String>,state: AnsiCodeTracker) -> AnsiCodeTracker:
  match background state:
    case True{} AnsiCodeTracker{flags,fg,_,link}: AnsiCodeTracker{flags,fg,color,link}
    case False{} AnsiCodeTracker{flags,_,bg,link}: AnsiCodeTracker{flags,color,bg,link}
def simpleSgr(+code: U32,+state: AnsiCodeTracker) -> AnsiCodeTracker:
  match code:
    case 0: reset(state)
    case 1: setAttribute(1,True{},state)
    case 2: setAttribute(2,True{},state)
    case 3: setAttribute(4,True{},state)
    case 4: setAttribute(8,True{},state)
    case 5: setAttribute(16,True{},state)
    case 7: setAttribute(32,True{},state)
    case 8: setAttribute(64,True{},state)
    case 9: setAttribute(128,True{},state)
    case 21: setAttribute(1,False{},state)
    case 22: setAttribute(3,False{},state)
    case 23: setAttribute(4,False{},state)
    case 24: setAttribute(8,False{},state)
    case 25: setAttribute(16,False{},state)
    case 27: setAttribute(32,False{},state)
    case 28: setAttribute(64,False{},state)
    case 29: setAttribute(128,False{},state)
    case 39: setColor(False{},None{},state)
    case 49: setColor(True{},None{},state)
    case code:
      Bool.pick(Unit -> AnsiCodeTracker,range(code,30,37) || range(code,90,97),
        _ => setColor(False{},Some{U32.show(code)},state),
        _ => Bool.pick(Unit -> AnsiCodeTracker,range(code,40,47) || range(code,100,107),_ => setColor(True{},Some{U32.show(code)},state),_ => state)(Unit{}))(Unit{})
# Incomplete/invalid extended color groups reject the whole SGR update. They
# cannot accidentally turn an RGB component into an unrelated style flag.
type SgrStep is Data: SgrStep{remaining: List<&2,Parameter>,state: AnsiCodeTracker}
def extendedSgr(background: Bool,prefix: String,values: List<&2,Parameter>,state: AnsiCodeTracker) -> Maybe<&2,SgrStep>:
  match values:
    case Parameter{5,mode} <> Parameter{+index,value} <> rest:
      Bool.pick(Unit -> Maybe<&2,SgrStep>,U32.is_le(index,255),_ => Some{SgrStep{rest,setColor(background,Some{prefix ++ ";" ++ mode ++ ";" ++ value},state)}},_ => None{})(Unit{})
    case Parameter{2,mode} <> Parameter{+r,red} <> Parameter{+g,green} <> Parameter{+b,blue} <> rest:
      Bool.pick(Unit -> Maybe<&2,SgrStep>,U32.is_le(r,255) && U32.is_le(g,255) && U32.is_le(b,255),_ => Some{SgrStep{rest,setColor(background,Some{prefix ++ ";" ++ mode ++ ";" ++ red ++ ";" ++ green ++ ";" ++ blue},state)}},_ => None{})(Unit{})
    case _: None{}
def nextSgr(values: List<&2,Parameter>,+state: AnsiCodeTracker) -> Maybe<&2,SgrStep>:
  match values:
    case Nil{}: Some{SgrStep{Nil{},state}}
    case Parameter{+code,raw} <> +rest:
      Bool.pick(Unit -> Maybe<&2,SgrStep>,U32.is_eq(code,38) || U32.is_eq(code,48),
        _ => extendedSgr(U32.is_eq(code,48),raw,rest,state),
        _ => Some{SgrStep{rest,simpleSgr(code,state)}})(Unit{})
@unsafe def applySgr(step: Maybe<&2,SgrStep>) -> Maybe<&2,AnsiCodeTracker>:
  match step:
    case None{}: None{}
    case Some{SgrStep{Nil{},state}}: Some{state}
    case Some{SgrStep{values,state}}: applySgr(nextSgr(values,state))
def processedSgr(+state: AnsiCodeTracker,values: Maybe<&2,List<&2,Parameter>>) -> AnsiCodeTracker:
  match values:
    case None{}: state
    case Some{values}: Maybe.default(&2,AnsiCodeTracker,applySgr(Some{SgrStep{values,state}}),state)
def process(state: AnsiCodeTracker,+code: String) -> AnsiCodeTracker:
  processedSgr(withLink(parseOsc8Hyperlink(code),state),sgrParameters(code))
def enabled(+flags: U32,bit: U32) -> Bool: U32.is_ne(U32.and(flags,bit),0)
def prefixCode(active: Bool,code: String,+rest: String) -> String: Bool.pick(String,active,code ++ ";" ++ rest,rest)
def optionalColor(color: Maybe<&2,String>,rest: String) -> String:
  match color:
    case None{}: rest
    case Some{color}: color ++ ";" ++ rest
def sgrCodes(+flags: U32,fg: Maybe<&2,String>,bg: Maybe<&2,String>) -> String:
  prefixCode(enabled(flags,1),"1",prefixCode(enabled(flags,2),"2",prefixCode(enabled(flags,4),"3",prefixCode(enabled(flags,8),"4",prefixCode(enabled(flags,16),"5",prefixCode(enabled(flags,32),"7",prefixCode(enabled(flags,64),"8",prefixCode(enabled(flags,128),"9",optionalColor(fg,optionalColor(bg,""))))))))))
def terminateReversed(text: String,reversed: String) -> String:
  match text:
    case SCon{';',SNil{}}: reverseInto(reversed,"m")
    case SCon{char,rest}: terminateReversed(rest,SCon{char,reversed})
    case SNil{}: reverseInto(reversed,"m")
def terminateCodes(text: String) -> String: terminateReversed(text,"")
def wrappedCodes(text: String) -> String:
  match text:
    case SNil{}: ""
    case text: "\u{1b}[" ++ terminateCodes(text)
def getActiveCodes(state: AnsiCodeTracker) -> String:
  match state:
    case AnsiCodeTracker{flags,fg,bg,link}: wrappedCodes(sgrCodes(flags,fg,bg)) ++ Maybe.default(&2,String,Maybe.map(&2,ActiveHyperlink,String,formatOsc8Hyperlink,link),"")
def getActiveBackgroundCode(state: AnsiCodeTracker) -> String:
  match state:
    case AnsiCodeTracker{_,_,bg,_}: wrappedCodes(optionalColor(bg,""))
def hasActiveCodes(state: AnsiCodeTracker) -> Bool:
  match state:
    case AnsiCodeTracker{flags,fg,bg,link}: U32.is_ne(flags,0) || Maybe.is_some(&2,String,fg) || Maybe.is_some(&2,String,bg) || Maybe.is_some(&2,ActiveHyperlink,link)
def hyperlinkClose(value: ActiveHyperlink) -> String:
  match value:
    case ActiveHyperlink{_,_,ending}: formatOsc8Close(ending)
def getLineEndReset(state: AnsiCodeTracker) -> String:
  match state:
    case AnsiCodeTracker{flags,_,_,link}: Bool.pick(String,enabled(flags,8),"\u{1b}[24m","") ++ Maybe.default(&2,String,Maybe.map(&2,ActiveHyperlink,String,hyperlinkClose,link),"")
def trackTokens(items: List<&2,Token>,state: AnsiCodeTracker) -> AnsiCodeTracker:
  match items:
    case Nil{}: state
    case Token{text,True{}} <> rest: trackTokens(rest,process(state,text))
    case _ <> rest: trackTokens(rest,state)
def updateTrackerFromText(text: String,state: AnsiCodeTracker) -> AnsiCodeTracker: trackTokens(tokens(text),state)
def getActiveBackgroundAnsi(text: String) -> String: getActiveBackgroundCode(updateTrackerFromText(text,emptyTracker()))
def activeOsc8Close(state: AnsiCodeTracker) -> String:
  match state:
    case AnsiCodeTracker{_,_,_,link}: Maybe.default(&2,String,Maybe.map(&2,ActiveHyperlink,String,hyperlinkClose,link),"")

def getActiveOsc8Close(text: String) -> String: activeOsc8Close(updateTrackerFromText(text,emptyTracker()))

# Scans check each character at the following step, so the recursion branches
# on a parameter instead of allocating a pair of lazy `Bool.pick` closures.
def asciiScan(text: String,ascii: Bool,width: Nat) -> Maybe<&2,Nat>:
  match text ascii:
    case _ False{}: None{}
    case SNil{} True{}: Some{width}
    case SCon{char,rest} True{}: asciiScan(rest,range(Char.to_u32(char),32,126),width + 1n)
def asciiWidth(text: String,width: Nat) -> Maybe<&2,Nat>: asciiScan(text,True{},width)
# A character that is its own grapheme cluster whatever its neighbours
# (Grapheme_Cluster_Break=Other, not Extended_Pictographic, no InCB) and has no
# display property but Wide or CJK script takes 1 or 2 cells, exactly as
# graphemeWidth measures it; 0 marks any other character.
def plainCells(+point: U32,+flags: U32) -> Nat:
  Bool.pick(Nat,U32.is_eq(U32.and(flags,4294967007),0) && U32.is_eq(Grapheme.packed(point),0),Bool.pick(Nat,enabled(flags,32),2n,1n),0n)
def cellsOf(ascii: Bool,+point: U32) -> Nat:
  match ascii:
    case True{}: 1n
    case False{}: plainCells(point,Display.properties(point))
def plainScan(text: String,cells: Nat,width: Nat) -> Maybe<&2,Nat>:
  match text cells:
    case _ Zero{}: None{}
    case SNil{} _: Some{width}
    case SCon{char,rest} _:
      +point = Char.to_u32(char)
      +next = cellsOf(range(point,32,126),point)
      plainScan(rest,next,width + next)
# Text of such characters needs no segmentation.
def plainWidth(text: String) -> Maybe<&2,Nat>: plainScan(text,1n,0n)
# Terminal cell widths follow pinned Pi's display policy, rather than treating
# all graphemes as one cell. Unicode properties and RGI membership are exact.
def terminalSpacingMark(+point: U32,flags: U32) -> Bool:
  (enabled(flags,2) && Bool.not(U32.is_eq(point,5940) || U32.is_eq(point,12334) || U32.is_eq(point,12335))) || U32.is_eq(point,1631) || U32.is_eq(point,3967) || range(point,4139,4140) || U32.is_eq(point,4145) || range(point,4147,4149) || U32.is_eq(point,4152) || range(point,4154,4158)
def spacingRun(text: String,+count: Nat) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: Bool.pick(Maybe<&2,Nat>,Nat.is_gt(count,0n),Some{count},None{})
    case SCon{char,rest}:
      +point = Char.to_u32(char)
      Bool.pick(Unit -> Maybe<&2,Nat>,terminalSpacingMark(point,Display.properties(point)),_ => spacingRun(rest,count + 1n),_ => None{})(Unit{})
def zeroWidthRun(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{char,rest}: Bool.pick(Unit -> Bool,U32.is_ne(U32.and(Display.properties(Char.to_u32(char)),21),0),_ => zeroWidthRun(rest),_ => False{})(Unit{})
def eastAsianWidth(point: U32) -> Nat: Bool.pick(Nat,enabled(Display.properties(point),32),2n,1n)
def trailingWidth(text: String,+followsMark: Bool,+width: Nat) -> Nat:
  match text:
    case SNil{}: width
    case SCon{char,+rest}:
      +point = Char.to_u32(char)
      +flags = Display.properties(point)
      Bool.pick(Unit -> Nat,terminalSpacingMark(point,flags),
        _ => trailingWidth(rest,False{},width + 1n),
        _ => Bool.pick(Unit -> Nat,enabled(flags,1),
          _ => trailingWidth(rest,True{},width),
          _ => Bool.pick(Unit -> Nat,U32.is_ne(U32.and(flags,29),0),
            _ => trailingWidth(rest,followsMark,width),
            _ => trailingWidth(rest,False{},width + Bool.pick(Nat,followsMark || range(point,65280,65519),eastAsianWidth(point),Bool.pick(Nat,U32.is_eq(point,3635) || U32.is_eq(point,3763),1n,0n))))(Unit{}))(Unit{}))(Unit{})
def baseWidth(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{char,+rest}:
      +point = Char.to_u32(char)
      Bool.pick(Unit -> Nat,U32.is_ne(U32.and(Display.properties(point),29),0),_ => baseWidth(rest),
        _ => Bool.pick(Unit -> Nat,range(point,127462,127487),_ => 2n,_ => trailingWidth(rest,False{},eastAsianWidth(point)))(Unit{}))(Unit{})
def nonSpacingWidth(+text: String) -> Nat:
  Bool.pick(Unit -> Nat,zeroWidthRun(text),_ => 0n,_ => Bool.pick(Unit -> Nat,Display.isRgiEmoji(text),_ => 2n,_ => baseWidth(text))(Unit{}))(Unit{})
def selectedWidth(value: Maybe<&2,Nat>,text: String) -> Nat:
  match value:
    case Some{width}: width
    case None{}: nonSpacingWidth(text)
def clusterWidth(+text: String) -> Nat:
  Bool.pick(Unit -> Nat,Strings.equal(text,"\t"),_ => 3n,_ => selectedWidth(spacingRun(text,0n),text))(Unit{})
def plainOr(width: Maybe<&2,Nat>,text: String) -> Nat:
  match width:
    case Some{cells}: cells
    case None{}: clusterWidth(text)
# Two plain characters never share a cluster, so a plain cluster is a single
# character and plainWidth measures it exactly.
def graphemeWidth(+text: String) -> Nat: plainOr(plainWidth(text),text)
# Grapheme.next always consumes a nonempty cluster; the state machine returns
# an affine pair so no list of every cluster is needed just to measure width.
@unsafe def measuredClusters(value: Maybe<&1,String & String>,width: Nat) -> Nat:
  match value:
    case None{}: width
    case Some{(cluster,rest)}: measuredClusters(Grapheme.next(rest),width + graphemeWidth(cluster))
def measuredText(value: Maybe<&2,Nat>,text: String) -> Nat:
  match value:
    case Some{width}: width
    case None{}: measuredClusters(Grapheme.next(text),0n)
def visibleClean(+text: String) -> Nat: measuredText(plainWidth(text),text)
# Tabs must become spaces before segmentation: a following spacing-mark cluster
# then has a visible base, which affects Pi's terminal-spacing mark accounting.
def expandedTabs(text: String,reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{'\t',rest}: expandedTabs(rest,prependReversed("   ",reversed))
    case SCon{char,rest}: expandedTabs(rest,SCon{char,reversed})
def widthText(items: List<&2,Token>,reversed: String) -> String:
  match items:
    case Nil{}: reverseInto(reversed,"")
    case Token{text,False{}} <> rest: widthText(rest,expandedTabs(text,reversed))
    case _ <> rest: widthText(rest,reversed)
# Styled text of plain characters: controls are skipped in place and cells
# summed, without building the stripped string. `cells` is one more than the
# previous step's width; 0 means a character or sequence needing the general
# path (a non-control escape, a tab, a non-plain character).
type Visible is Data: Visible{rest: String,cells: Nat}
def controlStep(value: Scan) -> Visible:
  match value:
    case Scan{Token{_,True{}},rest,_}: Visible{rest,1n}
    case Scan{_,rest,_}: Visible{rest,0n}
def visibleStep(text: String) -> Visible:
  match text:
    case SNil{}: Visible{"",1n}
    case SCon{Chr{27},rest}: controlStep(scan(SCon{Chr{27},rest}))
    case SCon{char,rest}:
      +point = Char.to_u32(char)
      +cells = cellsOf(range(point,32,126),point)
      Visible{rest,Bool.pick(Nat,Nat.is_eq(cells,0n),0n,cells + 1n)}
@unsafe
def visibleScan(step: Visible,width: Nat) -> Maybe<&2,Nat>:
  match step:
    case Visible{_,Zero{}}: None{}
    case Visible{SNil{},Succ{cells}}: Some{width + cells}
    case Visible{rest,Succ{cells}}: visibleScan(visibleStep(rest),width + cells)
def visibleGeneral(value: Maybe<&2,Nat>,text: String) -> Nat:
  match value:
    case Some{width}: width
    case None{}: visibleClean(widthText(tokens(text),""))
def visibleMeasured(value: Maybe<&2,Nat>,+text: String) -> Nat:
  match value:
    case Some{width}: width
    case None{}: visibleGeneral(visibleScan(visibleStep(text),0n),text)
def visibleWidth(+text: String) -> Nat: visibleMeasured(asciiWidth(text,0n),text)

# Layout retains controls as zero-cell tokens and segments each visible run.
# Column counts are natural numbers; no UTF-16 offsets enter this interface.
type WidthResult is Data: WidthResult{text: String,width: Nat}
type Segments is Data: Segments{before: String,beforeWidth: Nat,after: String,afterWidth: Nat}
def cellRun(items: List<&2,String>,reversed: List<&2,Token>) -> List<&2,Token>:
  match items:
    case Nil{}: reversed
    case text <> rest: cellRun(rest,Token{text,False{}} <> reversed)
def cellTokens(items: List<&2,Token>,+reversed: List<&2,Token>) -> List<&2,Token>:
  match items:
    case Nil{}: List.reverse(&2,Token,reversed)
    case Token{+text,+control} <> rest:
      cellTokens(rest,Bool.pick(List<&2,Token>,control,Token{text,control} <> reversed,cellRun(Grapheme.segments(text),reversed)))
def cells(text: String) -> List<&2,Token>: cellTokens(tokens(text),Nil{})
# A cursor visits only the columns a slice/truncation needs. It never builds
# a grapheme list for the unconsumed suffix of a long terminal line.
type CellCursor is Data: CellCursor{run: String,rest: String}
type CellStep is Data:
  CellEnd{}
  CellNext{cell: Token,rest: CellCursor}
def clusterCell(value: Maybe<&1,String & String>,after: String) -> CellStep:
  match value:
    case None{}: CellEnd{}
    case Some{(text,rest)}: CellNext{Token{text,False{}},CellCursor{rest,after}}
def rawCluster(value: Maybe<&1,String & String>) -> CellStep:
  match value:
    case None{}: CellEnd{}
    case Some{(text,rest)}: CellNext{Token{text,False{}},CellCursor{"",rest}}
def scannedCell(value: Scan) -> CellStep:
  match value:
    case Scan{Token{text,True{}},rest,_}: CellNext{Token{text,True{}},CellCursor{"",rest}}
    case Scan{Token{text,False{}},rest,_}: clusterCell(Grapheme.next(text),rest)
def nextCell(cursor: CellCursor) -> CellStep:
  match cursor:
    case CellCursor{SNil{},SNil{}}: CellEnd{}
    case CellCursor{SNil{},SCon{Chr{27},rest}}: scannedCell(scan(SCon{Chr{27},rest}))
    case CellCursor{SNil{},text}: rawCluster(Grapheme.next(text))
    case CellCursor{run,rest}: clusterCell(Grapheme.next(run),rest)
def spaces(count: Nat,result: String) -> String:
  match count:
    case Zero{}: result
    case Succ{rest}: spaces(rest,SCon{' ',result})
def padResult(text: String,width: Nat,maxWidth: Nat,pad: Bool) -> String:
  text ++ Bool.pick(String,pad,spaces(maxWidth - width,""),"")
# `stop` says the previous cell reached the end column. Deciding it at the
# next call keeps the recursion free of closures; the one cursor step taken
# past the end is discarded.
@unsafe
def sliceCells(stop: Bool,items: CellStep,+start: Nat,+end: Nat,+strict: Bool,+column: Nat,+reversed: String,+pending: String,width: Nat) -> WidthResult:
  match stop items:
    case True{} _: WidthResult{reverseInto(reversed,""),width}
    case False{} CellEnd{}: WidthResult{reverseInto(reversed,""),width}
    case False{} CellNext{Token{+text,True{}},rest}:
      sliceCells(False{},nextCell(rest),start,end,strict,column,Bool.pick(String,Nat.is_ge(column,start) && Nat.is_lt(column,end),prependReversed(text,reversed),reversed),Bool.pick(String,Nat.is_lt(column,start),prependReversed(text,pending),pending),width)
    case False{} CellNext{Token{+text,False{}},rest}:
      +size = graphemeWidth(text)
      +keep = Nat.is_ge(column,start) && Nat.is_lt(column,end) && (Bool.not(strict) || Nat.is_le(column + size,end))
      sliceCells(Nat.is_ge(column + size,end),nextCell(rest),start,end,strict,column + size,Bool.pick(String,keep,prependReversed(text,(pending ++ reversed)),reversed),Bool.pick(String,keep,"",pending),width + Bool.pick(Nat,keep,size,0n))
def sliceWithWidth(line: String,+startCol: Nat,+length: Nat,strict: Bool) -> WidthResult:
  Bool.pick(Unit -> WidthResult,Nat.is_eq(length,0n),_ => WidthResult{"",0n},_ => sliceCells(False{},nextCell(CellCursor{"",line}),startCol,startCol + length,strict,0n,"","",0n))(Unit{})
def resultText(value: WidthResult) -> String:
  match value:
    case WidthResult{text,_}: text
def sliceByColumn(line: String,startCol: Nat,length: Nat,strict: Bool) -> String:
  resultText(sliceWithWidth(line,startCol,length,strict))
# A contiguous prefix cannot resume after a wide grapheme misses the budget.
@unsafe
def fragmentCells(items: CellStep,+limit: Nat,+width: Nat,+reversed: String,pending: String) -> WidthResult:
  match items:
    case CellEnd{}: WidthResult{reverseInto(reversed,""),width}
    case CellNext{Token{text,True{}},rest}: fragmentCells(nextCell(rest),limit,width,reversed,prependReversed(text,pending))
    case CellNext{Token{+text,False{}},rest}:
      +size = graphemeWidth(text)
      Bool.pick(Unit -> WidthResult,Nat.is_gt(width + size,limit),
        _ => WidthResult{reverseInto(reversed,""),width},
        _ => fragmentCells(nextCell(rest),limit,width + size,prependReversed(text,(pending ++ reversed)),""))(Unit{})
def truncateFragmentToWidth(text: String,+maxWidth: Nat) -> WidthResult:
  Bool.pick(Unit -> WidthResult,Nat.is_eq(maxWidth,0n),_ => WidthResult{"",0n},_ => fragmentCells(nextCell(CellCursor{"",text}),maxWidth,0n,"",""))(Unit{})
def finalizeTruncatedResult(+prefix: String,prefixWidth: Nat,+ellipsis: String,ellipsisWidth: Nat,maxWidth: Nat,pad: Bool) -> String:
  padResult(prefix ++ getActiveOsc8Close(prefix) ++ "\u{1b}[0m" ++ ellipsis ++ Bool.pick(String,Strings.equal(ellipsis,""),"","\u{1b}[0m"),prefixWidth + ellipsisWidth,maxWidth,pad)
def finishPrefix(prefix: WidthResult,ellipsis: String,ellipsisWidth: Nat,maxWidth: Nat,pad: Bool) -> String:
  match prefix:
    case WidthResult{text,width}: finalizeTruncatedResult(text,width,ellipsis,ellipsisWidth,maxWidth,pad)
def finishEllipsis(value: WidthResult,+maxWidth: Nat,+pad: Bool) -> String:
  match value:
    case WidthResult{+text,+width}:
      Bool.pick(Unit -> String,Nat.is_eq(width,0n),_ => padResult("",0n,maxWidth,pad),_ => finalizeTruncatedResult("",0n,text,width,maxWidth,pad))(Unit{})
@unsafe
def layoutWidth(items: CellStep,+limit: Nat,+width: Nat) -> Nat:
  match items:
    case CellEnd{}: width
    case CellNext{Token{_,True{}},rest}: layoutWidth(nextCell(rest),limit,width)
    case CellNext{Token{text,False{}},rest}:
      +total = width + graphemeWidth(text)
      Bool.pick(Unit -> Nat,Nat.is_gt(total,limit),_ => total,_ => layoutWidth(nextCell(rest),limit,total))(Unit{})
def truncateMeasured(+text: String,+maxWidth: Nat,+ellipsis: String,+pad: Bool,+ellipsisWidth: Nat,+textWidth: Nat) -> String:
  Bool.pick(Unit -> String,Nat.is_le(textWidth,maxWidth),
    _ => padResult(text,textWidth,maxWidth,pad),
    _ => Bool.pick(Unit -> String,Nat.is_ge(ellipsisWidth,maxWidth),
      _ => finishEllipsis(truncateFragmentToWidth(ellipsis,maxWidth),maxWidth,pad),
      _ => finishPrefix(truncateFragmentToWidth(text,maxWidth - ellipsisWidth),ellipsis,ellipsisWidth,maxWidth,pad))(Unit{}))(Unit{})
def truncateToWidth(+text: String,+maxWidth: Nat,+ellipsis: String,pad: Bool) -> String:
  Bool.pick(Unit -> String,Nat.is_eq(maxWidth,0n),_ => "",_ => truncateMeasured(text,maxWidth,ellipsis,pad,visibleWidth(ellipsis),Bool.pick(Unit -> Nat,Nat.is_ge(visibleWidth(ellipsis),maxWidth),_ => visibleWidth(text),_ => layoutWidth(nextCell(CellCursor{"",text}),maxWidth,0n))(Unit{})))(Unit{})

type OverlayState is Data: OverlayState{before: String,beforeWidth: Nat,after: String,afterWidth: Nat,pending: String,started: Bool,tracker: AnsiCodeTracker}
def overlayResult(state: OverlayState) -> Segments:
  match state:
    case OverlayState{before,beforeWidth,after,afterWidth,_,_,_}: Segments{reverseInto(before,""),beforeWidth,reverseInto(after,""),afterWidth}
def overlayControl(state: OverlayState,+code: String,+column: Nat,beforeEnd: Nat,afterStart: Nat,afterEnd: Nat) -> OverlayState:
  match state:
    case OverlayState{before,beforeWidth,+after,afterWidth,+pending,+started,tracker}:
      +isBefore = Nat.is_lt(column,beforeEnd)
      +isAfter = Bool.not(isBefore) && Nat.is_ge(column,afterStart) && Nat.is_lt(column,afterEnd) && started
      OverlayState{before,beforeWidth,Bool.pick(String,isAfter,prependReversed(code,after),after),afterWidth,Bool.pick(String,isBefore,prependReversed(code,pending),pending),started,process(tracker,code)}
def overlayVisible(state: OverlayState,+text: String,+size: Nat,+column: Nat,+beforeEnd: Nat,afterStart: Nat,+afterEnd: Nat,strict: Bool) -> OverlayState:
  match state:
    case OverlayState{+before,+beforeWidth,+after,+afterWidth,+pending,+started,+tracker}:
      +isBefore = Nat.is_lt(column,beforeEnd) && Nat.is_le(column + size,beforeEnd)
      +isAfter = Bool.not(isBefore) && Nat.is_ge(column,afterStart) && Nat.is_lt(column,afterEnd) && (Bool.not(strict) || Nat.is_le(column + size,afterEnd))
      OverlayState{Bool.pick(String,isBefore,prependReversed(text,(pending ++ before)),before),beforeWidth + Bool.pick(Nat,isBefore,size,0n),Bool.pick(String,isAfter,prependReversed(text,prependReversed(Bool.pick(String,started,"",getActiveCodes(tracker)),after)),after),afterWidth + Bool.pick(Nat,isAfter,size,0n),Bool.pick(String,isBefore,"",pending),started || isAfter,tracker}
@unsafe
def overlayCells(items: CellStep,+beforeEnd: Nat,+afterStart: Nat,+afterEnd: Nat,+stop: Nat,+strict: Bool,+column: Nat,state: OverlayState) -> Segments:
  match items:
    case CellEnd{}: overlayResult(state)
    case CellNext{Token{text,True{}},rest}: overlayCells(nextCell(rest),beforeEnd,afterStart,afterEnd,stop,strict,column,overlayControl(state,text,column,beforeEnd,afterStart,afterEnd))
    case CellNext{Token{+text,False{}},rest}:
      +size = graphemeWidth(text)
      +next = overlayVisible(state,text,size,column,beforeEnd,afterStart,afterEnd,strict)
      Bool.pick(Unit -> Segments,Nat.is_ge(column + size,stop),_ => overlayResult(next),_ => overlayCells(nextCell(rest),beforeEnd,afterStart,afterEnd,stop,strict,column + size,next))(Unit{})
def extractSegments(line: String,+beforeEnd: Nat,+afterStart: Nat,+afterLen: Nat,strictAfter: Bool) -> Segments:
  overlayCells(nextCell(CellCursor{"",line}),beforeEnd,afterStart,afterStart + afterLen,Bool.pick(Nat,Nat.is_eq(afterLen,0n),beforeEnd,afterStart + afterLen),strictAfter,0n,OverlayState{"",0n,"",0n,"",False{},emptyTracker()})

# The source deliberately groups literal spaces, not locale word boundaries.
def whitespaceScalar(+point: U32) -> Bool:
  range(point,9,13) || U32.is_eq(point,32) || U32.is_eq(point,160) || U32.is_eq(point,5760) || range(point,8192,8202) || range(point,8232,8233) || U32.is_eq(point,8239) || U32.is_eq(point,8287) || U32.is_eq(point,12288) || U32.is_eq(point,65279)
def allWhitespace(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{char,rest}:
      Bool.pick(Unit -> Bool,whitespaceScalar(Char.to_u32(char)),
        _ => allWhitespace(rest),_ => False{})(Unit{})
def dropWhitespace(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{+char,+rest}: Bool.pick(Unit -> String,whitespaceScalar(Char.to_u32(char)),_ => dropWhitespace(rest),_ => SCon{char,rest})(Unit{})
def trimEnd(text: String) -> String: reverseInto(dropWhitespace(reverseInto(text,"")),"")
def cjkBreak(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{char,rest}:
      isCjk = U32.is_ne(U32.and(Display.properties(Char.to_u32(char)),256),0)
      Bool.pick(Unit -> Bool,isCjk,_ => True{},_ => cjkBreak(rest))(Unit{})
# upstream cjkPunctuationRegex and autocompleteSeparatorRegex: CJK letters
# stay part of words and paths; only whitespace and punctuation separate
# prose from completions. Property bit 512 is punctuation in a CJK script.
def cjkPunctuation(+point: U32) -> Bool:
  U32.is_ne(U32.and(Display.properties(point),512),0) || String.contains("，．：；！？（）［］｛｝“”‘’…—",SCon{Chr{point},""})
def autocompleteSeparator(+point: U32) -> Bool: whitespaceScalar(point) || cjkPunctuation(point)
def flushGroup(+current: String,+done: List<&2,String>) -> List<&2,String>:
  Bool.pick(List<&2,String>,Strings.equal(current,""),done,reverseInto(current,"") <> done)
def finishGroups(+current: String,+pending: String,done: List<&2,String>) -> List<&2,String>:
  match done:
    case Nil{}: List.reverse(&2,String,flushGroup(pending ++ current,Nil{}))
    case +last <> +rest:
      trailingControl = {(last ++ reverseInto(pending,"")) <> rest : List<&2,String>}
      trailingGroup = {reverseInto(pending ++ current,"") <> (last <> rest) : List<&2,String>}
      groups = Bool.pick(List<&2,String>,Strings.equal(current,""),trailingControl,trailingGroup)
      List.reverse(&2,String,groups)
def groupCells(items: List<&2,Token>,+current: String,+pending: String,+currentIsSpace: Bool,+done: List<&2,String>) -> List<&2,String>:
  match items:
    case Nil{}: finishGroups(current,pending,done)
    case Token{text,True{}} <> rest: groupCells(rest,current,prependReversed(text,pending),currentIsSpace,done)
    case Token{+text,False{}} <> +rest:
      +isSpace = Strings.equal(text," ")
      +changesKind = (currentIsSpace && Bool.not(isSpace)) || (Bool.not(currentIsSpace) && isSpace)
      groupPrefix = Bool.pick(String,changesKind,"",current)
      precedingGroups = Bool.pick(Unit -> List<&2,String>,changesKind,
        _ => flushGroup(current,done),_ => done)(Unit{})
      nextGroup = prependReversed(text,pending ++ groupPrefix)
      cjkToken = reverseInto(prependReversed(text,pending),"")
      Bool.pick(Unit -> List<&2,String>,Bool.not(isSpace) && cjkBreak(text),
        _ => groupCells(rest,"","",False{},cjkToken <> flushGroup(current,done)),
        _ => groupCells(rest,nextGroup,"",isSpace,precedingGroups))(Unit{})
def splitIntoTokensWithAnsi(text: String) -> List<&2,String>: groupCells(cells(text),"","",False{},Nil{})
# line and lines are reversed accumulators; tracker describes emitted controls.
type WrapState is Data: WrapState{line: String,width: Nat,tracker: AnsiCodeTracker,lines: List<&2,String>}
def breakCells(items: List<&2,Token>,+limit: Nat,state: WrapState) -> WrapState:
  match items:
    case Nil{}: state
    case Token{+text,+control} <> rest:
      match state:
        case WrapState{+line,+width,+tracker,+lines}:
          +size = Bool.pick(Nat,control,0n,visibleWidth(text))
          +overflow = Bool.not(control) && Nat.is_gt(width + size,limit)
          +nextTracker = Bool.pick(Unit -> AnsiCodeTracker,control,
            _ => process(tracker,text),_ => tracker)(Unit{})
          nextState = Bool.pick(Unit -> WrapState,overflow,
            _ => WrapState{
              prependReversed(text,prependReversed(getActiveCodes(tracker),"")),
              size,nextTracker,
              (reverseInto(line,"") ++ getLineEndReset(tracker)) <> lines},
            _ => WrapState{prependReversed(text,line),width + size,nextTracker,lines})(Unit{})
          breakCells(rest,limit,nextState)
def longWordState(state: WrapState) -> WrapState:
  match state:
    case WrapState{+line,_,+tracker,+lines}:
      completedLine = reverseInto(line,"") ++ getLineEndReset(tracker)
      completedLines = Bool.pick(List<&2,String>,Strings.equal(line,""),lines,completedLine <> lines)
      continuation = prependReversed(getActiveCodes(tracker),"")
      WrapState{continuation,0n,tracker,completedLines}
def wordState(state: WrapState,+token: String,+size: Nat,+limit: Nat) -> WrapState:
  match state:
    case WrapState{+line,+width,+tracker,+lines}:
      +overflow = Nat.is_gt(width + size,limit) && Nat.is_gt(width,0n)
      +whitespaceToken = allWhitespace(token)
      +nextTracker = updateTrackerFromText(token,tracker)
      Bool.pick(Unit -> WrapState,overflow,
        _ => WrapState{
          prependReversed(getActiveCodes(tracker) ++ Bool.pick(String,whitespaceToken,"",token),""),
          Bool.pick(Nat,whitespaceToken,0n,size),nextTracker,
          (trimEnd(reverseInto(line,"")) ++ getLineEndReset(tracker)) <> lines},
        _ => WrapState{prependReversed(token,line),width + size,nextTracker,lines})(Unit{})
def wrapTokens(items: List<&2,String>,+limit: Nat,+state: WrapState) -> WrapState:
  match items:
    case Nil{}: state
    case +token <> rest:
      +size = visibleWidth(token)
      breakWord = Nat.is_gt(size,limit) && Bool.not(allWhitespace(token))
      nextState = Bool.pick(Unit -> WrapState,breakWord,
        _ => breakCells(cells(token),limit,longWordState(state)),
        _ => wordState(state,token,size,limit))(Unit{})
      wrapTokens(rest,limit,nextState)
def trimLines(items: List<&2,String>,result: List<&2,String>) -> List<&2,String>:
  match items:
    case Nil{}: result
    case text <> rest: trimLines(rest,trimEnd(text) <> result)
def finishWrap(state: WrapState) -> List<&2,String>:
  match state:
    case WrapState{+line,_,_,+lines}:
      +result = flushGroup(line,lines)
      Bool.pick(List<&2,String>,List.is_empty(&2,String,result),"" <> Nil{},trimLines(result,Nil{}))
def wrapSingleLine(+line: String,+width: Nat) -> List<&2,String>:
  fits = Nat.is_le(visibleWidth(line),width)
  Bool.pick(Unit -> List<&2,String>,fits,
    _ => line <> Nil{},
    _ => finishWrap(wrapTokens(splitIntoTokensWithAnsi(line),width,WrapState{"",0n,emptyTracker(),Nil{}})))(Unit{})
def physicalLines(text: String,current: String,done: List<&2,String>) -> List<&2,String>:
  match text:
    case SNil{}: List.reverse(&2,String,reverseInto(current,"") <> done)
    case SCon{Chr{13},SCon{Chr{10},rest}}: physicalLines(rest,"",reverseInto(current,"") <> done)
    case SCon{Chr{13},rest}: physicalLines(rest,"",reverseInto(current,"") <> done)
    case SCon{Chr{10},rest}: physicalLines(rest,"",reverseInto(current,"") <> done)
    case SCon{char,rest}: physicalLines(rest,SCon{char,current},done)
def addLines(items: List<&2,String>,done: List<&2,String>) -> List<&2,String>:
  match items:
    case Nil{}: done
    case text <> rest: addLines(rest,text <> done)
def wrapPhysicalLines(items: List<&2,String>,+width: Nat,+tracker: AnsiCodeTracker,done: List<&2,String>) -> List<&2,String>:
  match items:
    case Nil{}: List.reverse(&2,String,done)
    case +text <> rest:
      wrapped = wrapSingleLine(getActiveCodes(tracker) ++ text,width)
      nextTracker = updateTrackerFromText(text,tracker)
      wrapPhysicalLines(rest,width,nextTracker,addLines(wrapped,done))
def wrapTextWithAnsi(text: String,width: Nat) -> List<&2,String>: wrapPhysicalLines(physicalLines(text,"",Nil{}),width,emptyTracker(),Nil{})

# The component retains callback ownership; rendering only borrows its handle.
def applyBackgroundToLine(+line: String,+width: Nat,bg: Callback.Callback<String,String>) -> IO(String):
  Callback.call(String,String,bg,padResult(line,visibleWidth(line),width,True{}))
