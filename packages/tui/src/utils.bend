import Base
import ../../runtime/src/string.bend as Strings
import ../../runtime/src/grapheme.bend as Grapheme
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
# ECMA-48 CSI parameters precede intermediates and one final byte.
def csi(text: String,+reversed: String,+length: Nat,+intermediate: Bool) -> Scan:
  match text:
    case SNil{}: scanned(reversed,False{},"",length)
    case SCon{+char,+rest}:
      +point = Char.to_u32(char)
      Bool.pick(Unit -> Scan,range(point,64,126),
        _ => scanned(SCon{char,reversed},True{},rest,length + 1n),
        _ => Bool.pick(Unit -> Scan,range(point,32,47) || (Bool.not(intermediate) && range(point,48,63)),
          _ => csi(rest,SCon{char,reversed},length + 1n,intermediate || range(point,32,47)),
          _ => scanned(reversed,False{},SCon{char,rest},length))(Unit{}))(Unit{})
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
    case SCon{Chr{27},SCon{'[',rest}}: csi(rest,"[\u{1b}",2n,False{})
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
def graphemeWidth(+text: String) -> Nat:
  Bool.pick(Unit -> Nat,Strings.equal(text,"\t"),_ => 3n,_ => selectedWidth(spacingRun(text,0n),text))(Unit{})
def asciiWidth(text: String,width: Nat) -> Maybe<&2,Nat>:
  match text:
    case SNil{}: Some{width}
    case SCon{char,rest}: Bool.pick(Unit -> Maybe<&2,Nat>,range(Char.to_u32(char),32,126),_ => asciiWidth(rest,width + 1n),_ => None{})(Unit{})
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
def visibleClean(+text: String) -> Nat: measuredText(asciiWidth(text,0n),text)
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
def visibleMeasured(value: Maybe<&2,Nat>,text: String) -> Nat:
  match value:
    case Some{width}: width
    case None{}: visibleClean(widthText(tokens(text),""))
def visibleWidth(+text: String) -> Nat: visibleMeasured(asciiWidth(text,0n),text)
