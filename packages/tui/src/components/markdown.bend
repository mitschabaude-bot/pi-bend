import Base
import ../utils.bend as U
import ../latex.bend as Latex
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/string.bend as Strings

def Style() -> Data: C.Callback<String,String>
type HighlightInput is Data: HighlightInput{code: String,lang: Maybe<&2,String>}
type MarkdownTheme is Data:
  MarkdownTheme{heading: Style(),link: Style(),linkUrl: Style(),code: Style(),codeBlock: Style(),codeBlockBorder: Style(),quote: Style(),quoteBorder: Style(),hr: Style(),listBullet: Style(),bold: Style(),italic: Style(),strikethrough: Style(),underline: Style(),highlightCode: Maybe<&2,C.Callback<HighlightInput,List<&2,String>>>,codeBlockIndent: Maybe<&2,String>}
type DefaultTextStyle is Data:
  DefaultTextStyle{color: Maybe<&2,Style()>,bgColor: Maybe<&2,Style()>,bold: Bool,italic: Bool,strikethrough: Bool,underline: Bool}
type MarkdownOptions is Data:
  MarkdownOptions{preserveOrderedListMarkers: Bool,preserveBackslashEscapes: Bool,transform: Maybe<&2,C.Callback<(String & Nat),String>>,renderLatex: Bool,hyperlinks: Bool}
type Cache is Data: Cache{width: Nat,lines: List<&2,String>}
type Markdown is Data:
  Markdown{text: String,paddingX: Nat,paddingY: Nat,theme: MarkdownTheme,defaultTextStyle: Maybe<&2,DefaultTextStyle>,options: MarkdownOptions,cache: Maybe<&2,Cache>}

def defaultOptions() -> MarkdownOptions: MarkdownOptions{False{},False{},None{},True{},False{}}
def new(text: String,paddingX: Nat,paddingY: Nat,theme: MarkdownTheme,style: Maybe<&2,DefaultTextStyle>,options: Maybe<&2,MarkdownOptions>) -> Markdown:
  Markdown{text,paddingX,paddingY,theme,style,Maybe.default(&2,MarkdownOptions,options,defaultOptions()),None{}}
def setText(state: Markdown,text: String) -> Markdown:
  match state: case Markdown{_,x,y,theme,style,options,_}: Markdown{text,x,y,theme,style,options,None{}}
def invalidate(state: Markdown) -> Markdown:
  match state: case Markdown{text,x,y,theme,style,options,_}: Markdown{text,x,y,theme,style,options,None{}}

def applyOptional(text: String,style: Maybe<&2,Style()>) -> IO(String):
  match style:
    case None{}: IO.pure(String,text)
    case Some{callback}: C.call(String,String,callback,text)
def applyIf(+text: String,enabled: Bool,style: Style()) -> IO(String):
  Bool.pick(Unit -> IO(String),enabled,_ => C.call(String,String,style,text),_ => IO.pure(String,text))(Unit{})
def themeBold(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,bold,_,_,_,_,_}: bold
def themeItalic(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,italic,_,_,_,_}: italic
def themeStrike(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,strike,_,_,_}: strike
def themeUnderline(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,_,underline,_,_}: underline

def styleText(text: String,style: Maybe<&2,DefaultTextStyle>,+theme: MarkdownTheme) -> IO(String):
  match style:
    case None{}: IO.pure(String,text)
    case Some{DefaultTextStyle{color,_,bold,italic,strike,underline}}:
      do IO<String>:
        colored : String <- applyOptional(text,color)
        strong : String <- applyIf(colored,bold,themeBold(theme))
        emphasis : String <- applyIf(strong,italic,themeItalic(theme))
        deleted : String <- applyIf(emphasis,strike,themeStrike(theme))
        applyIf(deleted,underline,themeUnderline(theme))
def transformed(source: String,width: Nat,options: MarkdownOptions) -> IO(String):
  match options:
    case MarkdownOptions{_,_,None{},_,_}: IO.pure(String,source)
    case MarkdownOptions{_,_,Some{transform},_,_}: C.call(String & Nat,String,transform,(source,width))
# The options inline rendering reads.
type InlineFlags is Data: InlineFlags{hyperlinks: Bool,renderLatex: Bool}
def inlineFlags(options: MarkdownOptions) -> InlineFlags:
  match options: case MarkdownOptions{_,_,_,latex,enabled}: InlineFlags{enabled,latex}
def hyperlinksOf(flags: InlineFlags) -> Bool:
  match flags: case InlineFlags{enabled,_}: enabled
def latexOf(flags: InlineFlags) -> Bool:
  match flags: case InlineFlags{_,enabled}: enabled
def background(style: Maybe<&2,DefaultTextStyle>) -> Maybe<&2,Style()>:
  match style:
    case None{}: None{}
    case Some{DefaultTextStyle{_,bgFn,_,_,_,_}}: bgFn
def painted(+line: String,width: Nat,bg: Maybe<&2,Style()>) -> IO(String):
  match bg:
    case None{}: IO.pure(String,U.padResult(line,U.visibleWidth(line),width,True{}))
    case Some{callback}: U.applyBackgroundToLine(line,width,callback)
def paint(lines: List<&2,String>,+margin: String,+width: Nat,+bg: Maybe<&2,Style()>,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case +line <> rest:
      do IO<List<&2,String>>:
        result : String <- painted(margin ++ line ++ margin,width,bg)
        paint(rest,margin,width,bg,result <> reversed)
def padding(count: Nat,+width: Nat,+bg: Maybe<&2,Style()>,reversed: List<&2,String>) -> IO(List<&2,String>):
  match count:
    case Zero{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case Succ{count}:
      do IO<List<&2,String>>:
        line : String <- painted(U.spaces(width,""),width,bg)
        padding(count,width,bg,line <> reversed)
def wrap(lines: List<&2,String>,+width: Nat,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case +line <> rest: wrap(rest,width,List.append(&2,String,List.reverse(&2,String,U.wrapTextWithAnsi(line,width)),reversed))

def rendered(state: Markdown,width: Nat,+lines: List<&2,String>) -> Markdown & List<&2,String>:
  match state:
    case Markdown{text,x,y,theme,style,options,_}: (Markdown{text,x,y,theme,style,options,Some{Cache{width,lines}}},lines)
# The body's lines arrive wrapped and painted (see `Frame`); the vertical
# padding is added here.
def finish(+state: Markdown,+width: Nat,body: List<&2,String>) -> IO(Markdown & List<&2,String>):
  match state:
    case Markdown{_,_,y,_,style,_,_}:
      do IO<Markdown & List<&2,String>>:
        +bg : Maybe<&2,Style()> <- IO.pure(Maybe<&2,Style()>,background(style))
        top : List<&2,String> <- padding(y,width,bg,Nil{})
        bottom : List<&2,String> <- padding(y,width,bg,Nil{})
        return rendered(state,width,List.append(&2,String,top,List.append(&2,String,body,bottom)))

# Wrapping and painting treat each rendered line alone, so each block's lines
# are finished as the block is rendered: `inner` is the content width,
# `margin` the horizontal padding, `gap` the finished empty line between
# blocks.
type Frame is Data: Frame{inner: Nat,margin: String,width: Nat,bg: Maybe<&2,Style()>,gap: List<&2,String>}
def finishLines(lines: List<&2,String>,frame: Frame) -> IO(List<&2,String>):
  match frame:
    case Frame{inner,margin,width,bg,_}: paint(wrap(lines,inner,Nil{}),margin,width,bg,Nil{})
def frameGap(frame: Frame) -> List<&2,String>:
  match frame: case Frame{_,_,_,_,gap}: gap
def withGap(frame: Frame,+inner: Nat,+margin: String,+width: Nat,+bg: Maybe<&2,Style()>) -> IO(Frame):
  do IO<Frame>:
    gap : List<&2,String> <- finishLines("" <> Nil{},Frame{inner,margin,width,bg,Nil{}})
    return Frame{inner,margin,width,bg,gap}
def newFrame(+inner: Nat,+margin: String,+width: Nat,+bg: Maybe<&2,Style()>) -> IO(Frame):
  withGap(Frame{inner,margin,width,bg,Nil{}},inner,margin,width,bg)

# Streaming renders a growing text again for every frame, and most of its
# blocks are unchanged. A memo carries the finished lines of the previous
# render's blocks, keyed by their source, into the next render of the same
# component: same theme, style and options, which its owner guarantees. The
# width and padding are checked here. Each render keeps only the blocks it
# used.
def Remembered() -> Data: Maybe<&2,List<&2,String>>
type Memo is Data: Memo{width: Nat,paddingX: Nat,blocks: Map<&2,Remembered()>}
def emptyMemo() -> Memo: Memo{0n,0n,Map.new(&2,Remembered())}
type Memos is Data: Memos{previous: Map<&2,Remembered()>,next: Map<&2,Remembered()>}
type Rendering is Data: Rendering{lines: List<&2,String>,memos: Memos}
def memoFor(memo: Memo,width: Nat,paddingX: Nat) -> Memos:
  match memo:
    case Memo{oldWidth,oldPadding,blocks}:
      Memos{Bool.pick(Map<&2,Remembered()>,Nat.is_eq(oldWidth,width) && Nat.is_eq(oldPadding,paddingX),blocks,Map.new(&2,Remembered())),Map.new(&2,Remembered())}
def memoAfter(memos: Memos,width: Nat,paddingX: Nat) -> Memo:
  match memos: case Memos{_,next}: Memo{width,paddingX,next}
def kept(+key: String,+lines: List<&2,String>,previous: Map<&2,Remembered()>,next: Map<&2,Remembered()>) -> Rendering:
  Rendering{lines,Memos{previous,Map.set(&2,Remembered(),next,key,Some{lines})}}
def recalled(+key: String,compute: Unit -> IO(List<&2,String>),previous: Map<&2,Remembered()> & Remembered(),next: Map<&2,Remembered()> & Remembered()) -> IO(Rendering):
  match previous next:
    case Tuple{earlier,_} Tuple{later,Some{lines}}: IO.pure(Rendering,Rendering{lines,Memos{earlier,later}})
    case Tuple{earlier,Some{lines}} Tuple{later,None{}}: IO.pure(Rendering,kept(key,lines,earlier,later))
    case Tuple{earlier,None{}} Tuple{later,None{}}:
      do IO<Rendering>:
        lines : List<&2,String> <- compute(Unit{})
        return kept(key,lines,earlier,later)
def memoized(+key: String,compute: Unit -> IO(List<&2,String>),memos: Memos) -> IO(Rendering):
  match memos:
    case Memos{previous,next}: recalled(key,compute,Map.get(Remembered(),None{},previous,key),Map.get(Remembered(),None{},next,key))
def linesOf(pair: Rendering) -> List<&2,String>:
  match pair: case Rendering{lines,_}: lines
def memosOf(pair: Rendering) -> Memos:
  match pair: case Rendering{_,memos}: memos

type InlineKind is Data:
  Strong{}
  Emphasis{}
  Strike{}
  Code{}
  Link{href: String}
type InlineStep is Data:
  End{}
  Literal{char: Char,rest: String}
  Styled{kind: InlineKind,content: String,rest: String}
  Math{raw: String,text: String,pending: Bool,rest: String}
type Split is Data: Split{before: String,after: String}
def cut(+source: String,+marker: String,+reversed: String) -> Maybe<&2,Split>:
  match source:
    case SNil{}: None{}
    case SCon{char,+rest}:
      Bool.pick(Unit -> Maybe<&2,Split>,String.starts_with(source,marker),
        _ => Some{Split{String.reverse(reversed),String.drop(source,String.length(marker))}},
        _ => cut(rest,marker,SCon{char,reversed}))(Unit{})
def part(kind: InlineKind,pair: Split) -> InlineStep:
  match pair: case Split{content,rest}: Styled{kind,content,rest}
def styledPart(kind: InlineKind,source: String,+marker: String) -> Maybe<&2,InlineStep>:
  Maybe.map(&2,Split,InlineStep,pair => part(kind,pair),cut(String.drop(source,String.length(marker)),marker,""))
def linked(label: String,second: Split) -> InlineStep:
  match second: case Split{href,rest}: Styled{Link{href},label,rest}
def linkClose(first: Split) -> Maybe<&2,InlineStep>:
  match first:
    case Split{label,tail}: Maybe.map(&2,Split,InlineStep,second => linked(label,second),cut(tail,")",""))
def linkAfter(candidate: Maybe<&2,Split>) -> Maybe<&2,InlineStep>:
  match candidate:
    case None{}: None{}
    case Some{first}: linkClose(first)
def linkStep(+source: String) -> Maybe<&2,InlineStep>:
  Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"["),
    _ => linkAfter(cut(String.drop(source,1n),"](","")),
    _ => None{})(Unit{})
def marker(+source: String) -> Maybe<&2,InlineStep>:
  Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"**"),_ => styledPart(Strong{},source,"**"),
    _ => Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"__"),_ => styledPart(Strong{},source,"__"),
    _ => Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"~~"),_ => styledPart(Strike{},source,"~~"),
    _ => Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"`"),_ => styledPart(Code{},source,"`"),
    _ => Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"*"),_ => styledPart(Emphasis{},source,"*"),
    _ => Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"_"),_ => styledPart(Emphasis{},source,"_"),_ => None{})(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{}))(Unit{})
def literalInline(input: String) -> InlineStep:
  match input:
    case SNil{}: End{}
    case SCon{char,+rest}: Literal{char,rest}
def fallbackInline(input: String,candidate: Maybe<&2,InlineStep>) -> InlineStep:
  match candidate:
    case Some{step}: step
    case None{}: literalInline(input)
def preferredInline(+source: String,link: Maybe<&2,InlineStep>) -> InlineStep:
  match link:
    case Some{step}: step
    case None{}: fallbackInline(source,marker(source))
def escapeStep(source: String) -> Maybe<&2,InlineStep>:
  match source:
    case SCon{'\\',SCon{+char,rest}}:
      Bool.pick(Unit -> Maybe<&2,InlineStep>,String.contains("\\`*_{}[]()#+-.!~>$",SCon{char,SNil{}}),
        _ => Some{Literal{char,rest}},_ => None{})(Unit{})
    case _: None{}
def escapedInline(+source: String,candidate: Maybe<&2,InlineStep>) -> InlineStep:
  match candidate:
    case Some{step}: step
    case None{}: preferredInline(source,linkStep(source))
# LaTeX
# -----
# pi's `latex` Marked extension: `$…$`, `$$…$$`, `\(…\)` and `\[…\]` on a
# line, and an unclosed delimiter while streaming (`pending`, shown raw).

def isAsciiLetter(+char: Char) -> Bool: Char.is_alpha(char)
# JavaScript's `\s`.
def isWhitespace(char: Char) -> Bool: Text.whitespace(Char.to_u32(char))
def startsWithAsciiLetter(text: String) -> Bool:
  match text:
    case SCon{char,_}: isAsciiLetter(char)
    case _: False{}
# `/\\[A-Za-z]+|[_^=+*/<>()[\]|±≤≥≠≈∈→⇒∞∫∑√-]/`
def looksLikePendingDollarMath(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{+char,+rest}:
      (Char.is_eq(char,'\\') && startsWithAsciiLetter(rest)) || String.contains("_^=+*/<>()[]|±≤≥≠≈∈→⇒∞∫∑√-",SCon{char,SNil{}}) || looksLikePendingDollarMath(rest)
def isIdentifierChar(+char: Char) -> Bool: isAsciiLetter(char) || Char.is_digit(char) || Char.is_eq(char,'_')
type Closed is Data: Closed{inner: String,after: String}
# `findClosingDelimiter`: the first `closing` not preceded by an odd run of
# backslashes; an escaped occurrence is skipped whole.
def closingDelimiter(text: String,+closing: String,+odd: Bool,+skip: Nat,+reversed: String) -> Maybe<&2,Closed>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}:
      +here = Nat.is_eq(skip,0n) && String.starts_with(SCon{char,rest},closing)
      Bool.pick(Unit -> Maybe<&2,Closed>,here && Bool.not(odd),
        _ => Some{Closed{String.reverse(reversed),String.drop(SCon{char,rest},String.length(closing))}},
        _ => closingDelimiter(rest,closing,Char.is_eq(char,'\\') && Bool.not(odd),Bool.pick(Nat,here,String.length(closing) - 1n,skip - 1n),SCon{char,reversed}))(Unit{})
# `/^[A-Z_][A-Z0-9_]*(?:[^A-Za-z0-9_\s])?$/`: a shell variable such as
# `$HOME/`.
def shellTail(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Bool,Char.is_upper(char) || Char.is_digit(char) || Char.is_eq(char,'_'),_ => shellTail(rest),
        _ => Bool.not(isIdentifierChar(char)) && Bool.not(isWhitespace(char)) && String.eq(rest,""))(Unit{})
def shellVariable(text: String) -> Bool:
  match text:
    case SCon{+char,rest}: (Char.is_upper(char) || Char.is_eq(char,'_')) && shellTail(rest)
    case _: False{}
def startsWithIdentifier(text: String) -> Bool:
  match text:
    case SCon{+char,_}: isAsciiLetter(char) || Char.is_eq(char,'_')
    case _: False{}
# Single dollars skip currency (`$5`), a space before the closing dollar,
# shell variables followed by a word, and code spans.
def dollarRejected(+inner: String,+after: String) -> Bool:
  Bool.not(String.eq(Text.trimEnd(inner),inner)) || Char.is_digit(Maybe.default(&2,Char,String.get(after,0n),' ')) || (shellVariable(inner) && startsWithIdentifier(after)) || String.contains(inner,"`")
def closedMath(+opening: String,+closing: String,found: Closed) -> Maybe<&2,InlineStep>:
  match found:
    case Closed{+inner,after}:
      Bool.pick(Maybe<&2,InlineStep>,String.eq(inner,"") || String.contains(inner,"\n"),None{},Some{Math{opening ++ inner ++ closing,inner,False{},after}})
def delimitedMath(found: Maybe<&2,Closed>,+source: String,+opening: String,+closing: String,single: Bool) -> Maybe<&2,InlineStep>:
  match found:
    case None{}:
      +pendingSource = String.drop(source,String.length(opening))
      Bool.pick(Maybe<&2,InlineStep>,String.starts_with(opening,"\\") || looksLikePendingDollarMath(pendingSource),Some{Math{source,pendingSource,True{},""}},None{})
    case Some{Closed{+inner,+after}}:
      Bool.pick(Unit -> Maybe<&2,InlineStep>,single && dollarRejected(inner,after),_ => None{},_ => closedMath(opening,closing,Closed{inner,after}))(Unit{})
def mathDelimited(+source: String,+opening: String,+closing: String,single: Bool) -> Maybe<&2,InlineStep>:
  delimitedMath(closingDelimiter(String.drop(source,String.length(opening)),closing,False{},0n,""),source,opening,closing,single)
# `tokenizeInlineLatex`
def latexInline(+source: String) -> Maybe<&2,InlineStep>:
  Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"$$"),_ => mathDelimited(source,"$$","$$",False{}),
    _ => Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"\\("),_ => mathDelimited(source,"\\(","\\)",False{}),
    _ => Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"\\["),_ => mathDelimited(source,"\\[","\\]",False{}),
    _ => Bool.pick(Unit -> Maybe<&2,InlineStep>,String.starts_with(source,"$") && Bool.not(isWhitespace(Maybe.default(&2,Char,String.get(source,1n),'x'))),
      _ => mathDelimited(source,"$","$",True{}),_ => None{})(Unit{}))(Unit{}))(Unit{}))(Unit{})
def latexFirst(+source: String,math: Maybe<&2,InlineStep>) -> InlineStep:
  match math:
    case Some{step}: step
    case None{}: escapedInline(source,escapeStep(source))
def nextInline(+source: String) -> InlineStep: latexFirst(source,latexInline(source))
# An underscore after a word character is literal: Marked does not open
# `_` emphasis inside a word (`$XDG_CONFIG_HOME`, `snake_case`).
def nextInlineAfter(+previous: Char,+source: String) -> InlineStep:
  Bool.pick(Unit -> InlineStep,isIdentifierChar(previous) && String.starts_with(source,"_"),_ => literalInline(source),_ => nextInline(source))(Unit{})
# A math token as shown: rendered, or its source while pending, when
# rendering is disabled or when pi's renderer does not support it.
def mathText(pending: Bool,+enabled: Bool,+raw: String,text: String) -> String:
  Bool.pick(Unit -> String,Bool.not(pending) && enabled,_ => Maybe.default(&2,String,Latex.renderLatex(text,Latex.defaultRenderLatexOptions()),raw),_ => raw)(Unit{})
def inlineStyle(kind: InlineKind,theme: MarkdownTheme) -> Style():
  match kind theme:
    case Strong{} theme: themeBold(theme)
    case Emphasis{} theme: themeItalic(theme)
    case Strike{} theme: themeStrike(theme)
    case Code{} MarkdownTheme{_,_,_,code,_,_,_,_,_,_,_,_,_,_,_,_}: code
    case Link{_} MarkdownTheme{_,link,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: link
def themeLinkUrl(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,linkUrl,_,_,_,_,_,_,_,_,_,_,_,_,_}: linkUrl
def styledInline(+kind: InlineKind,raw: String,inner: String,+theme: MarkdownTheme,flags: InlineFlags) -> IO(String):
  match kind:
    case Link{href}:
      do IO<String>:
        underlined : String <- C.call(String,String,themeUnderline(theme),inner)
        +linked : String <- C.call(String,String,inlineStyle(kind,theme),underlined)
        Bool.pick(Unit -> IO(String),hyperlinksOf(flags),
          _ => IO.pure(String,"\u{1b}]8;;" ++ href ++ "\u{1b}\\" ++ linked ++ "\u{1b}]8;;\u{1b}\\"),
        _ => Bool.pick(Unit -> IO(String),String.eq(raw,href),_ => IO.pure(String,linked),
          _ => do IO<String>:
            url : String <- C.call(String,String,themeLinkUrl(theme)," (" ++ href ++ ")")
            return linked ++ url)(Unit{}))(Unit{})
    case kind: C.call(String,String,inlineStyle(kind,theme),inner)
def isCode(kind: InlineKind) -> Bool:
  match kind:
    case Code{}: True{}
    case _: False{}
def prefixPart(value: Maybe<&2,Split>) -> String:
  match value:
    case None{}: ""
    case Some{Split{before,_}}: before
def prefixOf(styled: String) -> String: prefixPart(cut(styled,"\u{0}",""))
def styledSegments(segments: List<&2,String>,+style: Maybe<&2,DefaultTextStyle>,+theme: MarkdownTheme,reversed: List<&2,String>) -> IO(String):
  match segments:
    case Nil{}: IO.pure(String,String.join(List.reverse(&2,String,reversed),"\n"))
    case segment <> rest:
      do IO<String>:
        styled : String <- styleText(segment,style,theme)
        styledSegments(rest,style,theme,styled <> reversed)
@unsafe def renderDefault(step: InlineStep,+plain: String,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,+flags: InlineFlags,+prefix: String) -> IO(String):
  match step:
    case End{}: Bool.pick(Unit -> IO(String),String.eq(plain,""),_ => IO.pure(String,""),_ => styleText(String.reverse(plain),style,theme))(Unit{})
    case Literal{+char,rest}: renderDefault(nextInlineAfter(char,rest),SCon{char,plain},theme,style,flags,prefix)
    case Math{raw,text,pending,rest}:
      do IO<String>:
        before : String <- Bool.pick(Unit -> IO(String),String.eq(plain,""),_ => IO.pure(String,""),_ => styleText(String.reverse(plain),style,theme))(Unit{})
        shown : String <- styledSegments(Strings.split(mathText(pending,latexOf(flags),raw,text),'\n'),style,theme,Nil{})
        following : String <- renderDefault(nextInline(rest),"",theme,style,flags,prefix)
        return before ++ shown ++ following
    case Styled{+kind,+content,+rest}:
      do IO<String>:
        before : String <- Bool.pick(Unit -> IO(String),String.eq(plain,""),_ => IO.pure(String,""),_ => styleText(String.reverse(plain),style,theme))(Unit{})
        inner : String <- Bool.pick(Unit -> IO(String),isCode(kind),_ => IO.pure(String,content),_ => renderDefault(nextInline(content),"",theme,style,flags,prefix))(Unit{})
        highlighted : String <- styledInline(kind,content,inner,theme,flags)
        following : String <- renderDefault(nextInline(rest),"",theme,style,flags,prefix)
        return before ++ highlighted ++ Bool.pick(String,String.eq(rest,""),"",prefix) ++ following
def renderInline(step: InlineStep,plain: String,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,+flags: InlineFlags) -> IO(String):
  do IO<String>:
    sentinel : String <- styleText("\u{0}",style,theme)
    renderDefault(step,plain,theme,style,flags,prefixOf(sentinel))

def headingLevel(text: String,count: Nat) -> Nat:
  match text:
    case SCon{'#',rest}: headingLevel(rest,Succ{count})
    case _: count
def headingText(text: String,level: Nat) -> String:
  String.drop(text,level + 1n)
def themeHeading(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{heading,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: heading
def styledHeading(text: String,level: Nat,+theme: MarkdownTheme) -> IO(String):
  do IO<String>:
    underlined : String <- applyIf(text,Nat.is_eq(level,1n),themeUnderline(theme))
    bold : String <- C.call(String,String,themeBold(theme),underlined)
    C.call(String,String,themeHeading(theme),bold)
type InlineContext is Data:
  HeadingContext{level: Nat}
  QuoteContext{}
def contextPlain(text: String,context: InlineContext,theme: MarkdownTheme) -> IO(String):
  match context:
    case HeadingContext{level}: styledHeading(text,level,theme)
    case QuoteContext{}: IO.pure(String,text)
def contextSegments(segments: List<&2,String>,+context: InlineContext,+theme: MarkdownTheme,reversed: List<&2,String>) -> IO(String):
  match segments:
    case Nil{}: IO.pure(String,String.join(List.reverse(&2,String,reversed),"\n"))
    case segment <> rest:
      do IO<String>:
        styled : String <- contextPlain(segment,context,theme)
        contextSegments(rest,context,theme,styled <> reversed)
def hashes(count: Nat,reversed: String) -> String:
  match count:
    case Zero{}: reversed
    case Succ{rest}: hashes(rest,"#" ++ reversed)
@unsafe def renderContext(step: InlineStep,+plain: String,+context: InlineContext,+prefix: String,+theme: MarkdownTheme,+flags: InlineFlags) -> IO(String):
  match step:
    case End{}:
      Bool.pick(Unit -> IO(String),String.eq(plain,""),_ => IO.pure(String,""),_ => contextPlain(String.reverse(plain),context,theme))(Unit{})
    case Literal{+char,rest}: renderContext(nextInlineAfter(char,rest),SCon{char,plain},context,prefix,theme,flags)
    case Math{raw,text,pending,rest}:
      do IO<String>:
        before : String <- Bool.pick(Unit -> IO(String),String.eq(plain,""),_ => IO.pure(String,""),_ => contextPlain(String.reverse(plain),context,theme))(Unit{})
        shown : String <- contextSegments(Strings.split(mathText(pending,latexOf(flags),raw,text),'\n'),context,theme,Nil{})
        following : String <- renderContext(nextInline(rest),"",context,prefix,theme,flags)
        return before ++ shown ++ following
    case Styled{+kind,+content,+rest}:
      do IO<String>:
        before : String <- Bool.pick(Unit -> IO(String),String.eq(plain,""),_ => IO.pure(String,""),_ => contextPlain(String.reverse(plain),context,theme))(Unit{})
        inner : String <- Bool.pick(Unit -> IO(String),isCode(kind),_ => IO.pure(String,content),_ => renderContext(nextInline(content),"",context,prefix,theme,flags))(Unit{})
        highlighted : String <- styledInline(kind,content,inner,theme,flags)
        following : String <- renderContext(nextInline(rest),"",context,prefix,theme,flags)
        return before ++ highlighted ++ Bool.pick(String,String.eq(rest,""),"",prefix) ++ following
def headingInline(content: String,+level: Nat,+theme: MarkdownTheme,+flags: InlineFlags) -> IO(String):
  do IO<String>:
    styled : String <- styledHeading("\u{0}",level,theme)
    +rendered : String <- renderContext(nextInline(content),"",HeadingContext{level},prefixOf(styled),theme,flags)
    Bool.pick(Unit -> IO(String),Nat.is_ge(level,3n),_ => do IO<String>:
      marker : String <- styledHeading(hashes(level,"") ++ " ",level,theme)
      return marker ++ rendered,_ => IO.pure(String,rendered))(Unit{})
def themeQuote(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,quote,_,_,_,_,_,_,_,_,_}: quote
def quoteInline(content: String,+theme: MarkdownTheme,flags: InlineFlags) -> IO(String):
  do IO<String>:
    italic : String <- C.call(String,String,themeItalic(theme),"\u{0}")
    styled : String <- C.call(String,String,themeQuote(theme),italic)
    renderContext(nextInline(content),"",QuoteContext{},prefixOf(styled),theme,flags)
type BlockLine is Data:
  HeadingLine{level: Nat,content: String}
  BulletLine{depth: Nat,marker: String,content: String}
  QuoteLine{content: String}
  RuleLine{}
  PlainLine{content: String}
def leadingSpaces(text: String,count: Nat) -> Nat:
  match text:
    case SCon{' ',rest}: leadingSpaces(rest,Succ{count})
    case _: count
def orderedMarker(text: String,+digits: String,+depth: Nat) -> Maybe<&2,BlockLine>:
  match text:
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,BlockLine>,Char.is_digit(char),
        _ => orderedMarker(rest,digits ++ SCon{char,SNil{}},depth),
        _ => Bool.pick(Unit -> Maybe<&2,BlockLine>,Char.is_eq(char,'.') && Bool.not(String.eq(digits,"")) && String.starts_with(rest," "),
          _ => Some{BulletLine{depth,digits ++ ". ",String.drop(rest,1n)}},_ => None{})(Unit{}))(Unit{})
    case _: None{}
def bulletLine(+text: String,+depth: Nat) -> Maybe<&2,BlockLine>:
  match text:
    case SCon{+mark,SCon{' ',rest}}:
      Bool.pick(Unit -> Maybe<&2,BlockLine>,Char.is_eq(mark,'-') || Char.is_eq(mark,'+') || Char.is_eq(mark,'*'),
        _ => Some{BulletLine{depth,SCon{mark,SNil{}} ++ " ",rest}},_ => orderedMarker(text,"",depth))(Unit{})
    case _: orderedMarker(text,"",depth)
def quoteLine(text: String) -> Maybe<&2,BlockLine>:
  match text:
    case SCon{'>',SCon{' ',rest}}: Some{QuoteLine{rest}}
    case SCon{'>',rest}: Some{QuoteLine{rest}}
    case _: None{}
def classified(+line: String,+level: Nat,space: Nat,bullet: Maybe<&2,BlockLine>,quote: Maybe<&2,BlockLine>) -> BlockLine:
  match bullet quote:
    case Some{value} _: value
    case None{} Some{value}: value
    case None{} None{}:
      Bool.pick(BlockLine,Nat.is_gt(level,0n) && Nat.is_le(level,6n) && String.starts_with(String.drop(line,level)," "),
        HeadingLine{level,headingText(line,level)},
        Bool.pick(BlockLine,String.eq(Text.trim(line),"---"),RuleLine{},PlainLine{line}))
def classify(+line: String) -> BlockLine:
  +space = leadingSpaces(line,0n)
  +body = String.drop(line,space)
  classified(line,headingLevel(line,0n),space,bulletLine(body,space / 2n),quoteLine(body))
def themeListBullet(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,bullet,_,_,_,_,_,_}: bullet
def themeQuoteBorder(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,border,_,_,_,_,_,_,_,_}: border
def themeHr(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,hr,_,_,_,_,_,_,_}: hr
def repeatText(+text: String,count: Nat,reversed: String) -> String:
  match count:
    case Zero{}: reversed
    case Succ{rest}: repeatText(text,rest,text ++ reversed)
def lineResult(kind: BlockLine,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,width: Nat,+flags: InlineFlags) -> IO(String):
  match kind:
    case HeadingLine{level,content}: headingInline(content,level,theme,flags)
    case BulletLine{depth,mark,content}:
      do IO<String>:
        bullet : String <- C.call(String,String,themeListBullet(theme),mark)
        rendered : String <- renderInline(nextInline(content),"",theme,style,flags)
        return U.spaces(depth * 4n,"") ++ bullet ++ rendered
    case QuoteLine{content}:
      do IO<String>:
        border : String <- C.call(String,String,themeQuoteBorder(theme),"│ ")
        rendered : String <- renderInline(nextInline(content),"",theme,None{},flags)
        quoted : String <- C.call(String,String,themeItalic(theme),rendered)
        result : String <- C.call(String,String,themeQuote(theme),quoted)
        return border ++ result
    case RuleLine{}: C.call(String,String,themeHr(theme),repeatText("─",Nat.min(width,80n),""))
    case PlainLine{content}: renderInline(nextInline(content),"",theme,style,flags)
def continuation(lines: List<&2,String>,+prefix: String,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case line <> rest: continuation(rest,prefix,(prefix ++ line) <> reversed)
def prefixedParts(parts: List<&2,String>,+prefix: String,+space: String) -> List<&2,String>:
  match parts:
    case Nil{}: prefix <> Nil{}
    case first <> rest: (prefix ++ first) <> continuation(rest,space,Nil{})
def quotedParts(parts: List<&2,String>,+prefix: String,+theme: MarkdownTheme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match parts:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case fragment <> rest:
      do IO<List<&2,String>>:
        italic : String <- C.call(String,String,themeItalic(theme),fragment)
        styled : String <- C.call(String,String,themeQuote(theme),italic)
        quotedParts(rest,prefix,theme,(prefix ++ styled) <> reversed)
def quoteWrapped(content: String,+theme: MarkdownTheme,width: Nat,flags: InlineFlags) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    +border : String <- C.call(String,String,themeQuoteBorder(theme),"│ ")
    rendered : String <- quoteInline(content,theme,flags)
    quotedParts(U.wrapTextWithAnsi(rendered,Nat.max(1n,width - U.visibleWidth(border))),border,theme,Nil{})
def bulletWrapped(depth: Nat,mark: String,content: String,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,width: Nat,flags: InlineFlags) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    bullet : String <- C.call(String,String,themeListBullet(theme),mark)
    rendered : String <- renderInline(nextInline(content),"",theme,style,flags)
    +prefix : String <- IO.pure(String,U.spaces(depth * 4n,"") ++ bullet)
    +space : String <- IO.pure(String,U.spaces(U.visibleWidth(prefix),""))
    +parts : List<&2,String> <- IO.pure(List<&2,String>,U.wrapTextWithAnsi(rendered,Nat.max(1n,width - U.visibleWidth(prefix))))
    return prefixedParts(parts,prefix,space)
def blockKind(kind: BlockLine,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,width: Nat,flags: InlineFlags) -> IO(List<&2,String>):
  match kind:
    case BulletLine{depth,mark,content}: bulletWrapped(depth,mark,content,theme,style,width,flags)
    case QuoteLine{content}: quoteWrapped(content,theme,width,flags)
    case kind:
      do IO<List<&2,String>>:
        rendered : String <- lineResult(kind,theme,style,width,flags)
        return rendered <> Nil{}
def blockLine(line: String,theme: MarkdownTheme,style: Maybe<&2,DefaultTextStyle>,width: Nat,flags: InlineFlags) -> IO(List<&2,String>):
  blockKind(classify(line),theme,style,width,flags)
def dropTrailingBlank(+reversed: List<&2,String>) -> List<&2,String>:
  match reversed:
    case Nil{}: Nil{}
    case +line <> rest:
      Bool.pick(Unit -> List<&2,String>,Text.blank(line),_ => dropTrailingBlank(rest),_ => reversed)(Unit{})
def trimTrailing(lines: List<&2,String>) -> List<&2,String>:
  List.reverse(&2,String,dropTrailingBlank(List.reverse(&2,String,lines)))
def hasFollowing(lines: List<&2,String>) -> Bool:
  match lines:
    case Nil{}: False{}
    case line <> _: Bool.not(Text.blank(line))
# Display math
# ------------
# pi's `latexBlock` extension: a block opening with `$$` or `\[` after up to
# three spaces, through a closing delimiter that ends a line. An unclosed
# `\[`, or an unclosed `$$` whose text looks like math, is pending: it takes
# the rest of the document and shows it raw.
type BlockMath is Data: BlockMath{raw: String,text: String,pending: Bool,remaining: List<&2,String>}
type MathEnd is Data:
  TextEnd{}
  LineEnd{tail: String}
type MathClose is Data: MathClose{inner: String,end: MathEnd}
# `[ \t]*(?:\n|$)` after a closing delimiter.
def mathEnd(text: String) -> Maybe<&2,MathEnd>:
  match text:
    case SNil{}: Some{TextEnd{}}
    case SCon{'\n',rest}: Some{LineEnd{rest}}
    case SCon{' ',rest}: mathEnd(rest)
    case SCon{'\t',rest}: mathEnd(rest)
    case _: None{}
def closingAt(+text: String,+closing: String) -> Maybe<&2,MathEnd>:
  Bool.pick(Unit -> Maybe<&2,MathEnd>,String.starts_with(text,closing),_ => mathEnd(String.drop(text,String.length(closing))),_ => None{})(Unit{})
# The shortest text before a closing delimiter that ends a line.
def blockClose(text: String,+closing: String,+reversed: String) -> Maybe<&2,MathClose>:
  match text:
    case SNil{}: None{}
    case SCon{+char,+rest}:
      +ending = closingAt(SCon{char,rest},closing)
      Bool.pick(Unit -> Maybe<&2,MathClose>,Maybe.is_some(&2,MathEnd,ending),
        _ => Some{MathClose{String.reverse(reversed),Maybe.default(&2,MathEnd,ending,TextEnd{})}},
        _ => blockClose(rest,closing,SCon{char,reversed}))(Unit{})
def openingSpaces(text: String,+count: Nat) -> String:
  match text:
    case SCon{' ',+rest}: Bool.pick(Unit -> String,Nat.is_lt(count,3n),_ => openingSpaces(rest,Succ{count}),_ => SCon{' ',rest})(Unit{})
    case text: text
def blankPrefix(text: String) -> String:
  match text:
    case SCon{' ',rest}: blankPrefix(rest)
    case SCon{'\t',rest}: blankPrefix(rest)
    case SCon{'\n',rest}: rest
    case text: text
# `[ \t]*(?:\n)?` after the opening delimiter.
def mathContent(+body: String,+opening: String) -> String: blankPrefix(String.drop(body,String.length(opening)))
def closedBlockMath(end: MathEnd,+source: String,text: String) -> BlockMath:
  match end:
    case TextEnd{}: BlockMath{source,text,False{},Nil{}}
    case LineEnd{+tail}: BlockMath{String.take(source,String.length(source) - String.length(tail)),text,False{},Strings.split(tail,'\n')}
def closedBlock(found: Maybe<&2,MathClose>,+source: String) -> Maybe<&2,BlockMath>:
  match found:
    case None{}: None{}
    case Some{MathClose{+inner,end}}:
      Bool.pick(Unit -> Maybe<&2,BlockMath>,String.eq(inner,""),_ => None{},_ => Some{closedBlockMath(end,source,Text.trim(inner))})(Unit{})
def completeBlock(+source: String,+body: String,+opening: String,+closing: String) -> Maybe<&2,BlockMath>:
  Bool.pick(Unit -> Maybe<&2,BlockMath>,String.starts_with(body,opening),_ => closedBlock(blockClose(mathContent(body,opening),closing,""),source),_ => None{})(Unit{})
def pendingBlock(+source: String,+body: String,+opening: String,requireMath: Bool) -> Maybe<&2,BlockMath>:
  +content = mathContent(body,opening)
  Bool.pick(Unit -> Maybe<&2,BlockMath>,String.starts_with(body,opening) && (Bool.not(requireMath) || (Bool.not(String.eq(content,"")) && looksLikePendingDollarMath(content))),
    _ => Some{BlockMath{source,content,True{},Nil{}}},_ => None{})(Unit{})
# `tokenizeBlockLatex` over the rest of the document.
def blockMath(+source: String) -> Maybe<&2,BlockMath>:
  +body = openingSpaces(source,0n)
  Maybe.or(&2,BlockMath,completeBlock(source,body,"$$","$$"),Maybe.or(&2,BlockMath,completeBlock(source,body,"\\[","\\]"),
    Maybe.or(&2,BlockMath,pendingBlock(source,body,"\\[",False{}),pendingBlock(source,body,"$$",True{}))))
def opensMath(+line: String) -> Bool:
  +body = openingSpaces(line,0n)
  String.starts_with(body,"$$") || String.starts_with(body,"\\[")
def mathBlockAt(+lines: List<&2,String>) -> Maybe<&2,BlockMath>:
  match lines:
    case Nil{}: None{}
    case +line <> _: Bool.pick(Unit -> Maybe<&2,BlockMath>,opensMath(line),_ => blockMath(String.join(lines,"\n")),_ => None{})(Unit{})
def mathRemaining(block: BlockMath) -> List<&2,String>:
  match block: case BlockMath{_,_,_,remaining}: remaining
def styledLines(lines: List<&2,String>,+style: Maybe<&2,DefaultTextStyle>,+theme: MarkdownTheme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        styled : String <- styleText(line,style,theme)
        styledLines(rest,style,theme,styled <> reversed)
# Rendered in display mode, or the trimmed source while pending, when
# disabled or when pi's renderer does not support it.
def mathBlockLines(block: BlockMath,enabled: Bool,+style: Maybe<&2,DefaultTextStyle>,+theme: MarkdownTheme) -> IO(List<&2,String>):
  match block:
    case BlockMath{+raw,text,pending,_}:
      +shown = Bool.pick(Unit -> String,Bool.not(pending) && enabled,_ => Maybe.default(&2,String,Latex.renderLatex(text,Latex.RenderLatexOptions{True{}}),Text.trim(raw)),_ => Text.trim(raw))(Unit{})
      styledLines(Strings.split(shown,'\n'),style,theme,Nil{})
def classifiedSpacing(kind: BlockLine,+rest: List<&2,String>) -> Bool:
  match kind:
    case HeadingLine{_,_}: hasFollowing(rest)
    case RuleLine{}: hasFollowing(rest)
    case PlainLine{content}: Bool.not(Text.blank(content)) && Maybe.is_some(&2,BlockMath,mathBlockAt(rest))
    case _: False{}
def blockSpace(line: String,rest: List<&2,String>) -> Bool: classifiedSpacing(classify(line),rest)
def spaced(+rendered: List<&2,String>,space: Bool,frame: Frame,+following: List<&2,String>) -> List<&2,String>:
  Bool.pick(List<&2,String>,space,List.append(&2,String,rendered,List.append(&2,String,frameGap(frame),following)),List.append(&2,String,rendered,following))
def withSpacing(line: String,+rendered: List<&2,String>,rest: List<&2,String>,frame: Frame,+following: List<&2,String>) -> List<&2,String>:
  spaced(rendered,blockSpace(line,rest),frame,following)
def afterFence(+rendered: List<&2,String>,rest: List<&2,String>,frame: Frame,+following: List<&2,String>) -> List<&2,String>:
  spaced(rendered,hasFollowing(rest),frame,following)
type Fence is Data: Fence{code: List<&2,String>,remaining: List<&2,String>}
type QuoteGroup is Data: QuoteGroup{content: List<&2,String>,remaining: List<&2,String>}
def quoteContent(kind: BlockLine) -> Maybe<&2,String>:
  match kind:
    case QuoteLine{content}: Some{content}
    case PlainLine{content}: Some{content}
    case _: None{}
def quoteLineContent(line: String) -> Maybe<&2,String>: quoteContent(classify(line))
def collectQuote(lines: List<&2,String>,+reversed: List<&2,String>) -> QuoteGroup:
  match lines:
    case Nil{}: QuoteGroup{List.reverse(&2,String,reversed),Nil{}}
    case +line <> +rest:
      Bool.pick(Unit -> QuoteGroup,Bool.not(Text.blank(line)) && Bool.not(Maybe.is_none(&2,String,quoteLineContent(line))),
        _ => collectQuote(rest,Maybe.default(&2,String,quoteLineContent(line),"") <> reversed),
        _ => QuoteGroup{List.reverse(&2,String,reversed),line <> rest})(Unit{})
def quoteLines(group: QuoteGroup) -> List<&2,String>:
  match group: case QuoteGroup{lines,_}: lines
def quoteRest(group: QuoteGroup) -> List<&2,String>:
  match group: case QuoteGroup{_,rest}: rest
def quotedLines(lines: List<&2,String>,+theme: MarkdownTheme,+width: Nat) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case line <> rest:
      do IO<List<&2,String>>:
        +border : String <- C.call(String,String,themeQuoteBorder(theme),"│ ")
        quoted : List<&2,String> <- quotedParts(U.wrapTextWithAnsi(line,Nat.max(1n,width - U.visibleWidth(border))),border,theme,Nil{})
        following : List<&2,String> <- quotedLines(rest,theme,width)
        return List.append(&2,String,quoted,following)
# pi separates display math from the other blocks of a quote with an empty
# quote line.
def quoteGap(present: Bool,+theme: MarkdownTheme,+width: Nat) -> IO(List<&2,String>):
  match present:
    case True{}: quotedLines([""],theme,width)
    case False{}: IO.pure(List<&2,String>,Nil{})
# A quote's lines; display math renders with the default text style, as in
# pi, before the quote styling.
@unsafe def renderQuoteLines(display: Maybe<&2,BlockMath>,lines: List<&2,String>,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,+width: Nat,+flags: InlineFlags) -> IO(List<&2,String>):
  match display lines:
    case Some{+block} _:
      do IO<List<&2,String>>:
        shown : List<&2,String> <- mathBlockLines(block,latexOf(flags),style,theme)
        quoted : List<&2,String> <- quotedLines(shown,theme,width)
        gap : List<&2,String> <- quoteGap(Bool.not(List.is_empty(&2,String,mathRemaining(block))),theme,width)
        following : List<&2,String> <- renderQuoteLines(mathBlockAt(mathRemaining(block)),mathRemaining(block),theme,style,width,flags)
        return List.append(&2,String,quoted,List.append(&2,String,gap,following))
    case None{} Nil{}: IO.pure(List<&2,String>,Nil{})
    case None{} line <> +rest:
      do IO<List<&2,String>>:
        rendered : List<&2,String> <- quoteWrapped(line,theme,width,flags)
        gap : List<&2,String> <- quoteGap(Maybe.is_some(&2,BlockMath,mathBlockAt(rest)),theme,width)
        following : List<&2,String> <- renderQuoteLines(mathBlockAt(rest),rest,theme,style,width,flags)
        return List.append(&2,String,rendered,List.append(&2,String,gap,following))
def fenceLines(value: Fence) -> List<&2,String>:
  match value: case Fence{code,_}: code
def fenceRest(value: Fence) -> List<&2,String>:
  match value: case Fence{_,rest}: rest
def collectFence(lines: List<&2,String>,+marker: String,+reversed: List<&2,String>) -> Fence:
  match lines:
    case Nil{}: Fence{List.reverse(&2,String,reversed),Nil{}}
    case +line <> +rest:
      Bool.pick(Unit -> Fence,String.starts_with(line,marker),
        _ => Fence{List.reverse(&2,String,reversed),rest},
        _ => collectFence(rest,marker,line <> reversed))(Unit{})
def themeCodeBlock(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,code,_,_,_,_,_,_,_,_,_,_,_}: code
def themeCodeBorder(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,border,_,_,_,_,_,_,_,_,_,_}: border
def codeIndent(theme: MarkdownTheme) -> String:
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,indent}: Maybe.default(&2,String,indent,"  ")
def codeLines(lines: List<&2,String>,+theme: MarkdownTheme,+indent: String,reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> +rest:
      do IO<List<&2,String>>:
        styled : String <- C.call(String,String,themeCodeBlock(theme),line)
        codeLines(rest,theme,indent,(indent ++ styled) <> reversed)
def indented(lines: List<&2,String>,+indent: String,reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case line <> rest: indented(rest,indent,(indent ++ line) <> reversed)
def highlighted(code: List<&2,String>,lang: String,+theme: MarkdownTheme) -> IO(List<&2,String>):
  match theme:
    case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,_,_,Some{highlight},_}:
      do IO<List<&2,String>>:
        lines : List<&2,String> <- C.call(HighlightInput,List<&2,String>,highlight,HighlightInput{String.join(code,"\n"),Some{lang}})
        return indented(lines,codeIndent(theme),Nil{})
    case _: codeLines(code,theme,codeIndent(theme),Nil{})
def fenceRendered(+opening: String,code: List<&2,String>,+theme: MarkdownTheme) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    first : String <- C.call(String,String,themeCodeBorder(theme),opening)
    body : List<&2,String> <- highlighted(code,String.drop(opening,3n),theme)
    last : String <- C.call(String,String,themeCodeBorder(theme),"```")
    return first <> List.append(&2,String,body,last <> Nil{})
type TableRows is Data: TableRows{rows: List<&2,List<&2,String>>,remaining: List<&2,String>}
type TableResult is Data: TableResult{lines: List<&2,String>,remaining: List<&2,String>}
def rawTable(lines: List<&2,String>,+reversed: List<&2,String>) -> TableResult:
  match lines:
    case Nil{}: TableResult{List.reverse(&2,String,reversed),Nil{}}
    case +line <> +rest:
      Bool.pick(Unit -> TableResult,String.contains(line,"|") && Bool.not(Text.blank(line)),
        _ => rawTable(rest,line <> reversed),_ => TableResult{List.reverse(&2,String,reversed),line <> rest})(Unit{})
def narrowFromRaw(raw: TableResult,width: Nat) -> TableResult:
  match raw:
    case TableResult{lines,remaining}: TableResult{wrap(lines,width,Nil{}),remaining}
def narrowTable(header: String,rest: List<&2,String>,width: Nat) -> TableResult:
  narrowFromRaw(rawTable(header <> rest,Nil{}),width)
def tableLines(value: TableResult) -> List<&2,String>:
  match value: case TableResult{lines,_}: lines
def tableRest(value: TableResult) -> List<&2,String>:
  match value: case TableResult{_,rest}: rest
def trimCellEndReversed(reversed: List<&2,String>,original: List<&2,String>) -> List<&2,String>:
  match reversed:
    case Nil{}: Nil{}
    case last <> rest:
      Bool.pick(List<&2,String>,Text.blank(last),List.reverse(&2,String,rest),original)
def trimCellEnd(+parts: List<&2,String>) -> List<&2,String>:
  trimCellEndReversed(List.reverse(&2,String,parts),parts)
def trimCellEdges(+parts: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: Nil{}
    case first <> rest:
      Bool.pick(Unit -> List<&2,String>,Text.blank(first),_ => trimCellEnd(rest),_ => trimCellEnd(parts))(Unit{})
def trimmedCells(parts: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: Nil{}
    case cell <> rest: Text.trim(cell) <> trimmedCells(rest)
def cells(line: String) -> List<&2,String>: trimmedCells(trimCellEdges(Strings.split(line,'|')))
def tableHeader(line: String) -> List<&2,String>: cells(line)
def dividerAfter(rest: List<&2,String>) -> Bool:
  match rest:
    case +line <> _: String.contains(line,"---") && String.contains(line,"|")
    case _: False{}
def isTable(line: String,rest: List<&2,String>) -> Bool:
  String.contains(line,"|") && dividerAfter(rest)
def afterDivider(rest: List<&2,String>) -> List<&2,String>:
  match rest:
    case _ <> following: following
    case Nil{}: Nil{}
def collectRows(lines: List<&2,String>,+reversed: List<&2,List<&2,String>>) -> TableRows:
  match lines:
    case Nil{}: TableRows{List.reverse(&2,List<&2,String>,reversed),Nil{}}
    case +line <> +rest:
      Bool.pick(Unit -> TableRows,String.contains(line,"|") && Bool.not(Text.blank(line)),
        _ => collectRows(rest,tableHeader(line) <> reversed),
        _ => TableRows{List.reverse(&2,List<&2,String>,reversed),line <> rest})(Unit{})
def tableRows(value: TableRows) -> List<&2,List<&2,String>>:
  match value: case TableRows{rows,_}: rows
def tableRemaining(value: TableRows) -> List<&2,String>:
  match value: case TableRows{_,rest}: rest
def inlineCells(cells: List<&2,String>,+theme: MarkdownTheme,+flags: InlineFlags) -> IO(List<&2,String>):
  match cells:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case cell <> rest:
      do IO<List<&2,String>>:
        rendered : String <- renderInline(nextInline(cell),"",theme,None{},flags)
        following : List<&2,String> <- inlineCells(rest,theme,flags)
        return rendered <> following
def inlineRows(rows: List<&2,List<&2,String>>,+theme: MarkdownTheme,+flags: InlineFlags) -> IO(List<&2,List<&2,String>>):
  match rows:
    case Nil{}: IO.pure(List<&2,List<&2,String>>,Nil{})
    case row <> rest:
      do IO<List<&2,List<&2,String>>>:
        rendered : List<&2,String> <- inlineCells(row,theme,flags)
        following : List<&2,List<&2,String>> <- inlineRows(rest,theme,flags)
        return rendered <> following
def rowWidth(rows: List<&2,List<&2,String>>,+index: Nat) -> Nat:
  match rows:
    case Nil{}: 0n
    case row <> rest: Nat.max(Maybe.default(&2,Nat,Maybe.map(&2,String,Nat,text => U.visibleWidth(text),List.get(&2,String,row,index)),0n),rowWidth(rest,index))
def widths(header: List<&2,String>,+rows: List<&2,List<&2,String>>,+index: Nat) -> List<&2,Nat>:
  match header:
    case Nil{}: Nil{}
    case cell <> rest: Nat.max(U.visibleWidth(cell),rowWidth(rows,index)) <> widths(rest,rows,Succ{index})
def longestWord(words: List<&2,String>) -> Nat:
  match words:
    case Nil{}: 1n
    case word <> rest: Nat.max(U.visibleWidth(word),longestWord(rest))
def wordWidth(text: String) -> Nat: Nat.min(30n,longestWord(Strings.split(text,' ')))
def rowWordWidth(rows: List<&2,List<&2,String>>,+index: Nat) -> Nat:
  match rows:
    case Nil{}: 1n
    case row <> rest: Nat.max(Maybe.default(&2,Nat,Maybe.map(&2,String,Nat,word => wordWidth(word),List.get(&2,String,row,index)),1n),rowWordWidth(rest,index))
def minimumWidths(header: List<&2,String>,+rows: List<&2,List<&2,String>>,+index: Nat) -> List<&2,Nat>:
  match header:
    case Nil{}: Nil{}
    case cell <> rest: Nat.max(wordWidth(cell),rowWordWidth(rows,index)) <> minimumWidths(rest,rows,Succ{index})
def sumWidths(sizes: List<&2,Nat>) -> Nat:
  match sizes:
    case Nil{}: 0n
    case size <> rest: size + sumWidths(rest)
def ones(count: Nat) -> List<&2,Nat>:
  match count:
    case Zero{}: Nil{}
    case Succ{rest}: 1n <> ones(rest)
def potential(target: List<&2,Nat>,base: List<&2,Nat>) -> List<&2,Nat>:
  match target base:
    case Nil{} _: Nil{}
    case _ Nil{}: Nil{}
    case value <> more minimum <> rest: (value - minimum) <> potential(more,rest)
def proportional(base: List<&2,Nat>,weights: List<&2,Nat>,+extra: Nat,+total: Nat) -> List<&2,Nat>:
  match base weights:
    case Nil{} _: Nil{}
    case _ Nil{}: Nil{}
    case value <> more weight <> rest: (value + Bool.pick(Nat,Nat.is_gt(total,0n),weight * extra / total,0n)) <> proportional(more,rest,extra,total)
def growPass(current: List<&2,Nat>,targets: List<&2,Nat>,+remaining: Nat) -> List<&2,Nat>:
  match current targets:
    case Nil{} _: Nil{}
    case _ Nil{}: Nil{}
    case +value <> more target <> rest:
      +grow = Nat.is_gt(remaining,0n) && Nat.is_lt(value,target)
      Bool.pick(Nat,grow,Succ{value},value) <> growPass(more,rest,Bool.pick(Nat,grow,remaining - 1n,remaining))
@unsafe def fillWidths(+current: List<&2,Nat>,+targets: List<&2,Nat>,+budget: Nat) -> List<&2,Nat>:
  +remaining = budget - sumWidths(current)
  Bool.pick(Unit -> List<&2,Nat>,Nat.is_gt(remaining,0n) && Nat.is_lt(sumWidths(current),sumWidths(targets)),
    _ => fillWidths(growPass(current,targets,remaining),targets,budget),_ => current)(Unit{})
def allocatedWidths(+natural: List<&2,Nat>,+minimum: List<&2,Nat>,+available: Nat) -> List<&2,Nat>:
  +count = List.length(&2,Nat,natural)
  +base = Bool.pick(List<&2,Nat>,Nat.is_gt(sumWidths(minimum),available),ones(count),minimum)
  +target = Bool.pick(List<&2,Nat>,Nat.is_gt(sumWidths(minimum),available),minimum,natural)
  +weights = potential(target,base)
  +initial = proportional(base,weights,available - sumWidths(base),sumWidths(weights))
  fillWidths(initial,target,available)
def tableWidths(+natural: List<&2,Nat>,minimum: List<&2,Nat>,+available: Nat) -> List<&2,Nat>:
  Bool.pick(List<&2,Nat>,Nat.is_le(sumWidths(natural),available),natural,allocatedWidths(natural,minimum,available))
def dashes(widths: List<&2,Nat>) -> List<&2,String>:
  match widths:
    case Nil{}: Nil{}
    case width <> rest: repeatText("─",width,"") <> dashes(rest)
def border(widths: List<&2,Nat>,left: String,middle: String,right: String) -> String:
  left ++ String.join(dashes(widths),middle) ++ right
def paddedCell(+cell: String,width: Nat,bold: Bool,theme: MarkdownTheme) -> IO(String):
  +plain = U.padResult(cell,U.visibleWidth(cell),width,True{})
  applyIf(plain,bold,themeBold(theme))
def resetFragments(parts: List<&2,String>) -> List<&2,String>:
  match parts:
    case Nil{}: Nil{}
    case last <> Nil{}: last <> Nil{}
    case first <> rest: (first ++ "\u{1b}[22;23;24;25;27;28;29;39m") <> resetFragments(rest)
@unsafe def wrappedCells(+cells: List<&2,String>,sizes: List<&2,Nat>,reversed: List<&2,List<&2,String>>) -> List<&2,List<&2,String>>:
  match sizes:
    case Nil{}: List.reverse(&2,List<&2,String>,reversed)
    case width <> rest:
      wrappedCells(List.drop(&2,String,cells,1n),rest,resetFragments(U.wrapTextWithAnsi(Maybe.default(&2,String,List.get(&2,String,cells,0n),""),Nat.max(1n,width))) <> reversed)
def wrappedHeight(cells: List<&2,List<&2,String>>) -> Nat:
  match cells:
    case Nil{}: 0n
    case cell <> rest: Nat.max(List.length(&2,String,cell),wrappedHeight(rest))
def wrappedRowParts(cells: List<&2,List<&2,String>>,sizes: List<&2,Nat>,+index: Nat,+bold: Bool,+theme: MarkdownTheme,reversed: List<&2,String>) -> IO(List<&2,String>):
  match cells sizes:
    case Nil{} _: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case _ Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case cell <> more width <> rest:
      do IO<List<&2,String>>:
        padded : String <- paddedCell(Maybe.default(&2,String,List.get(&2,String,cell,index),""),width,bold,theme)
        wrappedRowParts(more,rest,index,bold,theme,padded <> reversed)
@unsafe def wrappedRowLines(+cells: List<&2,List<&2,String>>,+sizes: List<&2,Nat>,+bold: Bool,+theme: MarkdownTheme,+index: Nat,count: Nat) -> IO(List<&2,String>):
  match count:
    case Zero{}: IO.pure(List<&2,String>,Nil{})
    case Succ{rest}:
      do IO<List<&2,String>>:
        parts : List<&2,String> <- wrappedRowParts(cells,sizes,index,bold,theme,Nil{})
        following : List<&2,String> <- wrappedRowLines(cells,sizes,bold,theme,Succ{index},rest)
        return ("│ " ++ String.join(parts," │ ") ++ " │") <> following
def wrappedRow(row: List<&2,String>,+sizes: List<&2,Nat>,+bold: Bool,+theme: MarkdownTheme) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    +cells : List<&2,List<&2,String>> <- IO.pure(List<&2,List<&2,String>>,wrappedCells(row,sizes,Nil{}))
    wrappedRowLines(cells,sizes,bold,theme,0n,wrappedHeight(cells))
def renderedRows(rows: List<&2,List<&2,String>>,+widths: List<&2,Nat>,+theme: MarkdownTheme,+separator: String) -> IO(List<&2,String>):
  match rows:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case row <> Nil{}: wrappedRow(row,widths,False{},theme)
    case row <> rest:
      do IO<List<&2,String>>:
        line : List<&2,String> <- wrappedRow(row,widths,False{},theme)
        following : List<&2,String> <- renderedRows(rest,widths,theme,separator)
        return List.append(&2,String,line,separator <> following)
def tableRegular(header: String,rest: List<&2,String>,+theme: MarkdownTheme,+width: Nat,+flags: InlineFlags) -> IO(TableResult):
  do IO<TableResult>:
    +parsed : TableRows <- IO.pure(TableRows,collectRows(afterDivider(rest),Nil{}))
    +cells : List<&2,String> <- inlineCells(tableHeader(header),theme,flags)
    +body : List<&2,List<&2,String>> <- inlineRows(tableRows(parsed),theme,flags)
    +columns : List<&2,Nat> <- IO.pure(List<&2,Nat>,tableWidths(widths(cells,body,0n),minimumWidths(cells,body,0n),width - (3n * List.length(&2,String,cells) + 1n)))
    heading : List<&2,String> <- wrappedRow(cells,columns,True{},theme)
    rows : List<&2,String> <- renderedRows(body,columns,theme,border(columns,"├─","─┼─","─┤"))
    return TableResult{border(columns,"┌─","─┬─","─┐") <> List.append(&2,String,heading,border(columns,"├─","─┼─","─┤") <> List.append(&2,String,rows,border(columns,"└─","─┴─","─┘") <> Nil{})),tableRemaining(parsed)}
def tableRendered(+header: String,+rest: List<&2,String>,+theme: MarkdownTheme,+width: Nat,+flags: InlineFlags) -> IO(TableResult):
  Bool.pick(Unit -> IO(TableResult),Nat.is_lt(width,4n * List.length(&2,String,tableHeader(header)) + 1n),
    _ => IO.pure(TableResult,narrowTable(header,rest,width)),_ => tableRegular(header,rest,theme,width,flags))(Unit{})
# `display` is the display math starting at `lines`, if any. Fenced code
# and single lines are remembered in `memos`.
def fenceKey(line: String,code: List<&2,String>) -> String: "F" ++ line ++ "\n" ++ String.join(code,"\n")
def fenceFinished(+opening: String,code: List<&2,String>,+theme: MarkdownTheme,frame: Frame) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    rendered : List<&2,String> <- fenceRendered(opening,code,theme)
    finishLines(rendered,frame)
def lineFinished(+line: String,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,+width: Nat,+flags: InlineFlags,frame: Frame) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    rendered : List<&2,String> <- Bool.pick(Unit -> IO(List<&2,String>),Text.blank(line),_ => IO.pure(List<&2,String>,"" <> Nil{}),_ => blockLine(line,theme,style,width,flags))(Unit{})
    finishLines(rendered,frame)
@unsafe def renderBlocks(display: Maybe<&2,BlockMath>,lines: List<&2,String>,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,+width: Nat,+flags: InlineFlags,+frame: Frame,+memos: Memos) -> IO(Rendering):
  match display lines:
    case Some{+block} _:
      do IO<Rendering>:
        shown : List<&2,String> <- mathBlockLines(block,latexOf(flags),style,theme)
        rendered : List<&2,String> <- finishLines(shown,frame)
        +following : Rendering <- renderBlocks(mathBlockAt(mathRemaining(block)),mathRemaining(block),theme,style,width,flags,frame,memos)
        return Rendering{afterFence(rendered,mathRemaining(block),frame,linesOf(following)),memosOf(following)}
    case None{} Nil{}: IO.pure(Rendering,Rendering{Nil{},memos})
    case None{} +line <> +rest:
      Bool.pick(Unit -> IO(Rendering),String.starts_with(line,"```"),
        _ => do IO<Rendering>:
          +fence : Fence <- IO.pure(Fence,collectFence(rest,"```",Nil{}))
          +block : Rendering <- memoized(fenceKey(line,fenceLines(fence)),_ => fenceFinished(line,fenceLines(fence),theme,frame),memos)
          +following : Rendering <- renderBlocks(mathBlockAt(fenceRest(fence)),fenceRest(fence),theme,style,width,flags,frame,memosOf(block))
          return Rendering{afterFence(linesOf(block),fenceRest(fence),frame,linesOf(following)),memosOf(following)},
        _ => Bool.pick(Unit -> IO(Rendering),Bool.not(Maybe.is_none(&2,BlockLine,quoteLine(line))),
          _ => do IO<Rendering>:
            +group : QuoteGroup <- IO.pure(QuoteGroup,collectQuote(rest,Nil{}))
            +contents : List<&2,String> <- IO.pure(List<&2,String>,Maybe.default(&2,String,quoteLineContent(line),"") <> quoteLines(group))
            quoted : List<&2,String> <- renderQuoteLines(mathBlockAt(contents),contents,theme,style,width,flags)
            rendered : List<&2,String> <- finishLines(quoted,frame)
            +following : Rendering <- renderBlocks(mathBlockAt(quoteRest(group)),quoteRest(group),theme,style,width,flags,frame,memos)
            return Rendering{afterFence(rendered,quoteRest(group),frame,linesOf(following)),memosOf(following)},
        _ => Bool.pick(Unit -> IO(Rendering),isTable(line,rest),
          _ => do IO<Rendering>:
            +table : TableResult <- tableRendered(line,rest,theme,width,flags)
            rendered : List<&2,String> <- finishLines(tableLines(table),frame)
            +following : Rendering <- renderBlocks(mathBlockAt(tableRest(table)),tableRest(table),theme,style,width,flags,frame,memos)
            return Rendering{List.append(&2,String,rendered,linesOf(following)),memosOf(following)},
          _ => do IO<Rendering>:
            +block : Rendering <- memoized("L" ++ line,_ => lineFinished(line,theme,style,width,flags,frame),memos)
            +following : Rendering <- renderBlocks(mathBlockAt(rest),rest,theme,style,width,flags,frame,memosOf(block))
            return Rendering{withSpacing(line,linesOf(block),rest,frame,linesOf(following)),memosOf(following)})(Unit{}))(Unit{}))(Unit{})

type OrderedLine is Data: OrderedLine{number: Nat,content: String}
type Numbered is Data: Numbered{line: String,next: Maybe<&2,Nat>}
def orderedResult(value: Nat,content: String,seen: Bool) -> Maybe<&2,OrderedLine>:
  match seen:
    case True{}: Some{OrderedLine{value,content}}
    case False{}: None{}
def orderedDot(rest: String,value: Nat,seen: Bool) -> Maybe<&2,OrderedLine>:
  match rest:
    case SCon{' ',content}: orderedResult(value,content,seen)
    case _: None{}
def orderedDigits(text: String,+value: Nat,+seen: Bool) -> Maybe<&2,OrderedLine>:
  match text:
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Maybe<&2,OrderedLine>,Char.is_eq(char,'.'),
        _ => orderedDot(rest,value,seen),
        _ => Bool.pick(Unit -> Maybe<&2,OrderedLine>,Char.is_digit(char),
          _ => orderedDigits(rest,value * 10n + U32.to_nat((Char.to_u32(char) - 48 : U32)),True{}),
          _ => None{})(Unit{}))(Unit{})
    case _: None{}
def numbered(line: String,current: Maybe<&2,Nat>,parsed: Maybe<&2,OrderedLine>) -> Numbered:
  match parsed:
    case None{}: Numbered{line,None{}}
    case Some{OrderedLine{source,content}}:
      +number = Maybe.default(&2,Nat,current,source)
      Numbered{Nat.show(number) ++ ". " ++ content,Some{Succ{number}}}
def numberedLine(step: Numbered) -> String:
  match step: case Numbered{line,_}: line
def numberedNext(step: Numbered) -> Maybe<&2,Nat>:
  match step: case Numbered{_,next}: next
def normalizeOrdered(lines: List<&2,String>,current: Maybe<&2,Nat>) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case +line <> rest:
      +step = numbered(line,current,orderedDigits(line,0n,False{}))
      numberedLine(step) <> normalizeOrdered(rest,numberedNext(step))
def preparedLines(lines: List<&2,String>,options: MarkdownOptions) -> List<&2,String>:
  match options:
    case MarkdownOptions{True{},_,_,_,_}: lines
    case _: normalizeOrdered(lines,None{})
def withMemo(pair: Markdown & List<&2,String>,memo: Memo) -> Markdown & List<&2,String> & Memo:
  match pair: case (state,lines): (state,lines,memo)
def uncached(+state: Markdown,+width: Nat,+memo: Memo) -> IO(Markdown & List<&2,String> & Memo):
  match state:
    case Markdown{+source,+x,_,theme,+style,options,_}:
      do IO<Markdown & List<&2,String> & Memo>:
        +inner : Nat <- IO.pure(Nat,Nat.max(1n,width - x * 2n))
        +transformedText : String <- transformed(source,inner,options)
        Bool.pick(Unit -> IO(Markdown & List<&2,String> & Memo),Text.blank(transformedText),
          _ => IO.pure(Markdown & List<&2,String> & Memo,withMemo(rendered(state,width,Nil{}),memo)),
          _ => do IO<Markdown & List<&2,String> & Memo>:
            +lines : List<&2,String> <- IO.pure(List<&2,String>,preparedLines(trimTrailing(Strings.split(String.join(Strings.split(transformedText,'\t'),"   "),'\n')),options))
            +frame : Frame <- newFrame(inner,U.spaces(x,""),width,background(style))
            +blocks : Rendering <- renderBlocks(mathBlockAt(lines),lines,theme,style,inner,inlineFlags(options),frame,memoFor(memo,width,x))
            finished : Markdown & List<&2,String> <- finish(state,width,linesOf(blocks))
            return withMemo(finished,memoAfter(memosOf(blocks),width,x)))(Unit{})
def withoutMemo(value: Markdown & List<&2,String> & Memo) -> Markdown & List<&2,String>:
  match value: case (state,lines,_): (state,lines)
def uncachedAlone(+state: Markdown,+width: Nat) -> IO(Markdown & List<&2,String>):
  do IO<Markdown & List<&2,String>>:
    value : Markdown & List<&2,String> & Memo <- uncached(state,width,emptyMemo())
    return withoutMemo(value)
def render(+state: Markdown,+width: Nat) -> IO(Markdown & List<&2,String>):
  match state:
    case Markdown{_,_,_,_,_,_,Some{Cache{oldWidth,lines}}}:
      Bool.pick(Unit -> IO(Markdown & List<&2,String>),Nat.is_eq(oldWidth,width),_ => IO.pure(Markdown & List<&2,String>,(state,lines)),_ => uncachedAlone(state,width))(Unit{})
    case _: uncachedAlone(state,width)
# `render` with the memo of the component's previous render (see `Memo`).
def renderWithMemo(+state: Markdown,+width: Nat,+memo: Memo) -> IO(Markdown & List<&2,String> & Memo):
  match state:
    case Markdown{_,_,_,_,_,_,Some{Cache{oldWidth,lines}}}:
      Bool.pick(Unit -> IO(Markdown & List<&2,String> & Memo),Nat.is_eq(oldWidth,width),_ => IO.pure(Markdown & List<&2,String> & Memo,(state,lines,memo)),_ => uncached(state,width,memo))(Unit{})
    case _: uncached(state,width,memo)
