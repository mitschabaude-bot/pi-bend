import Base
import ../utils.bend as U
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
def linkCapability(options: MarkdownOptions) -> Bool:
  match options: case MarkdownOptions{_,_,_,_,enabled}: enabled
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
def finish(+state: Markdown,+width: Nat,lines: List<&2,String>) -> IO(Markdown & List<&2,String>):
  match state:
    case Markdown{_,x,y,_,style,_,_}:
      do IO<Markdown & List<&2,String>>:
        +bg : Maybe<&2,Style()> <- IO.pure(Maybe<&2,Style()>,background(style))
        margin : String <- IO.pure(String,U.spaces(x,""))
        body : List<&2,String> <- paint(wrap(lines,Nat.max(1n,width - x * 2n),Nil{}),margin,width,bg,Nil{})
        top : List<&2,String> <- padding(y,width,bg,Nil{})
        bottom : List<&2,String> <- padding(y,width,bg,Nil{})
        return rendered(state,width,List.append(&2,String,top,List.append(&2,String,body,bottom)))

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
      Bool.pick(Unit -> Maybe<&2,InlineStep>,String.contains("\\`*_{}[]()#+-.!~>",SCon{char,SNil{}}),
        _ => Some{Literal{char,rest}},_ => None{})(Unit{})
    case _: None{}
def escapedInline(+source: String,candidate: Maybe<&2,InlineStep>) -> InlineStep:
  match candidate:
    case Some{step}: step
    case None{}: preferredInline(source,linkStep(source))
def nextInline(+source: String) -> InlineStep: escapedInline(source,escapeStep(source))
def inlineStyle(kind: InlineKind,theme: MarkdownTheme) -> Style():
  match kind theme:
    case Strong{} theme: themeBold(theme)
    case Emphasis{} theme: themeItalic(theme)
    case Strike{} theme: themeStrike(theme)
    case Code{} MarkdownTheme{_,_,_,code,_,_,_,_,_,_,_,_,_,_,_,_}: code
    case Link{_} MarkdownTheme{_,link,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: link
def themeLinkUrl(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,linkUrl,_,_,_,_,_,_,_,_,_,_,_,_,_}: linkUrl
def styledInline(+kind: InlineKind,raw: String,inner: String,+theme: MarkdownTheme,links: Bool) -> IO(String):
  match kind:
    case Link{href}:
      do IO<String>:
        underlined : String <- C.call(String,String,themeUnderline(theme),inner)
        +linked : String <- C.call(String,String,inlineStyle(kind,theme),underlined)
        Bool.pick(Unit -> IO(String),links,
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
@unsafe def renderDefault(step: InlineStep,+plain: String,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,+links: Bool,+prefix: String) -> IO(String):
  match step:
    case End{}: Bool.pick(Unit -> IO(String),String.eq(plain,""),_ => IO.pure(String,""),_ => styleText(String.reverse(plain),style,theme))(Unit{})
    case Literal{char,rest}: renderDefault(nextInline(rest),SCon{char,plain},theme,style,links,prefix)
    case Styled{+kind,+content,+rest}:
      do IO<String>:
        before : String <- Bool.pick(Unit -> IO(String),String.eq(plain,""),_ => IO.pure(String,""),_ => styleText(String.reverse(plain),style,theme))(Unit{})
        inner : String <- Bool.pick(Unit -> IO(String),isCode(kind),_ => IO.pure(String,content),_ => renderDefault(nextInline(content),"",theme,style,links,prefix))(Unit{})
        highlighted : String <- styledInline(kind,content,inner,theme,links)
        following : String <- renderDefault(nextInline(rest),"",theme,style,links,prefix)
        return before ++ highlighted ++ Bool.pick(String,String.eq(rest,""),"",prefix) ++ following
def renderInline(step: InlineStep,plain: String,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,+links: Bool) -> IO(String):
  do IO<String>:
    sentinel : String <- styleText("\u{0}",style,theme)
    renderDefault(step,plain,theme,style,links,prefixOf(sentinel))

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
def hashes(count: Nat,reversed: String) -> String:
  match count:
    case Zero{}: reversed
    case Succ{rest}: hashes(rest,"#" ++ reversed)
@unsafe def renderContext(step: InlineStep,+plain: String,+context: InlineContext,+prefix: String,+theme: MarkdownTheme,+links: Bool) -> IO(String):
  match step:
    case End{}:
      Bool.pick(Unit -> IO(String),String.eq(plain,""),_ => IO.pure(String,""),_ => contextPlain(String.reverse(plain),context,theme))(Unit{})
    case Literal{char,rest}: renderContext(nextInline(rest),SCon{char,plain},context,prefix,theme,links)
    case Styled{+kind,+content,+rest}:
      do IO<String>:
        before : String <- Bool.pick(Unit -> IO(String),String.eq(plain,""),_ => IO.pure(String,""),_ => contextPlain(String.reverse(plain),context,theme))(Unit{})
        inner : String <- Bool.pick(Unit -> IO(String),isCode(kind),_ => IO.pure(String,content),_ => renderContext(nextInline(content),"",context,prefix,theme,links))(Unit{})
        highlighted : String <- styledInline(kind,content,inner,theme,links)
        following : String <- renderContext(nextInline(rest),"",context,prefix,theme,links)
        return before ++ highlighted ++ Bool.pick(String,String.eq(rest,""),"",prefix) ++ following
def headingInline(content: String,+level: Nat,+theme: MarkdownTheme,+links: Bool) -> IO(String):
  do IO<String>:
    styled : String <- styledHeading("\u{0}",level,theme)
    +rendered : String <- renderContext(nextInline(content),"",HeadingContext{level},prefixOf(styled),theme,links)
    Bool.pick(Unit -> IO(String),Nat.is_ge(level,3n),_ => do IO<String>:
      marker : String <- styledHeading(hashes(level,"") ++ " ",level,theme)
      return marker ++ rendered,_ => IO.pure(String,rendered))(Unit{})
def themeQuote(theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,quote,_,_,_,_,_,_,_,_,_}: quote
def quoteInline(content: String,+theme: MarkdownTheme,links: Bool) -> IO(String):
  do IO<String>:
    italic : String <- C.call(String,String,themeItalic(theme),"\u{0}")
    styled : String <- C.call(String,String,themeQuote(theme),italic)
    renderContext(nextInline(content),"",QuoteContext{},prefixOf(styled),theme,links)
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
def lineResult(kind: BlockLine,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,width: Nat,+links: Bool) -> IO(String):
  match kind:
    case HeadingLine{level,content}: headingInline(content,level,theme,links)
    case BulletLine{depth,mark,content}:
      do IO<String>:
        bullet : String <- C.call(String,String,themeListBullet(theme),mark)
        rendered : String <- renderInline(nextInline(content),"",theme,style,links)
        return U.spaces(depth * 4n,"") ++ bullet ++ rendered
    case QuoteLine{content}:
      do IO<String>:
        border : String <- C.call(String,String,themeQuoteBorder(theme),"│ ")
        rendered : String <- renderInline(nextInline(content),"",theme,None{},links)
        quoted : String <- C.call(String,String,themeItalic(theme),rendered)
        result : String <- C.call(String,String,themeQuote(theme),quoted)
        return border ++ result
    case RuleLine{}: C.call(String,String,themeHr(theme),repeatText("─",Nat.min(width,80n),""))
    case PlainLine{content}: renderInline(nextInline(content),"",theme,style,links)
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
def quoteWrapped(content: String,+theme: MarkdownTheme,width: Nat,links: Bool) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    +border : String <- C.call(String,String,themeQuoteBorder(theme),"│ ")
    rendered : String <- quoteInline(content,theme,links)
    quotedParts(U.wrapTextWithAnsi(rendered,Nat.max(1n,width - U.visibleWidth(border))),border,theme,Nil{})
def bulletWrapped(depth: Nat,mark: String,content: String,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,width: Nat,links: Bool) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    bullet : String <- C.call(String,String,themeListBullet(theme),mark)
    rendered : String <- renderInline(nextInline(content),"",theme,style,links)
    +prefix : String <- IO.pure(String,U.spaces(depth * 4n,"") ++ bullet)
    +space : String <- IO.pure(String,U.spaces(U.visibleWidth(prefix),""))
    +parts : List<&2,String> <- IO.pure(List<&2,String>,U.wrapTextWithAnsi(rendered,Nat.max(1n,width - U.visibleWidth(prefix))))
    return prefixedParts(parts,prefix,space)
def blockKind(kind: BlockLine,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,width: Nat,links: Bool) -> IO(List<&2,String>):
  match kind:
    case BulletLine{depth,mark,content}: bulletWrapped(depth,mark,content,theme,style,width,links)
    case QuoteLine{content}: quoteWrapped(content,theme,width,links)
    case kind:
      do IO<List<&2,String>>:
        rendered : String <- lineResult(kind,theme,style,width,links)
        return rendered <> Nil{}
def blockLine(line: String,theme: MarkdownTheme,style: Maybe<&2,DefaultTextStyle>,width: Nat,links: Bool) -> IO(List<&2,String>):
  blockKind(classify(line),theme,style,width,links)
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
def classifiedSpacing(kind: BlockLine,rest: List<&2,String>) -> Bool:
  match kind:
    case HeadingLine{_,_}: hasFollowing(rest)
    case RuleLine{}: hasFollowing(rest)
    case _: False{}
def blockSpace(line: String,rest: List<&2,String>) -> Bool: classifiedSpacing(classify(line),rest)
def withSpacing(line: String,+rendered: List<&2,String>,rest: List<&2,String>,+following: List<&2,String>) -> List<&2,String>:
  Bool.pick(List<&2,String>,blockSpace(line,rest),List.append(&2,String,rendered,"" <> following),List.append(&2,String,rendered,following))
def afterFence(+rendered: List<&2,String>,rest: List<&2,String>,+following: List<&2,String>) -> List<&2,String>:
  Bool.pick(List<&2,String>,hasFollowing(rest),List.append(&2,String,rendered,"" <> following),List.append(&2,String,rendered,following))
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
def renderQuoteLines(lines: List<&2,String>,+theme: MarkdownTheme,+width: Nat,+links: Bool) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case line <> rest:
      do IO<List<&2,String>>:
        rendered : List<&2,String> <- quoteWrapped(line,theme,width,links)
        following : List<&2,String> <- renderQuoteLines(rest,theme,width,links)
        return List.append(&2,String,rendered,following)
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
def inlineCells(cells: List<&2,String>,+theme: MarkdownTheme,+links: Bool) -> IO(List<&2,String>):
  match cells:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case cell <> rest:
      do IO<List<&2,String>>:
        rendered : String <- renderInline(nextInline(cell),"",theme,None{},links)
        following : List<&2,String> <- inlineCells(rest,theme,links)
        return rendered <> following
def inlineRows(rows: List<&2,List<&2,String>>,+theme: MarkdownTheme,+links: Bool) -> IO(List<&2,List<&2,String>>):
  match rows:
    case Nil{}: IO.pure(List<&2,List<&2,String>>,Nil{})
    case row <> rest:
      do IO<List<&2,List<&2,String>>>:
        rendered : List<&2,String> <- inlineCells(row,theme,links)
        following : List<&2,List<&2,String>> <- inlineRows(rest,theme,links)
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
def tableRegular(header: String,rest: List<&2,String>,+theme: MarkdownTheme,+width: Nat,+links: Bool) -> IO(TableResult):
  do IO<TableResult>:
    +parsed : TableRows <- IO.pure(TableRows,collectRows(afterDivider(rest),Nil{}))
    +cells : List<&2,String> <- inlineCells(tableHeader(header),theme,links)
    +body : List<&2,List<&2,String>> <- inlineRows(tableRows(parsed),theme,links)
    +columns : List<&2,Nat> <- IO.pure(List<&2,Nat>,tableWidths(widths(cells,body,0n),minimumWidths(cells,body,0n),width - (3n * List.length(&2,String,cells) + 1n)))
    heading : List<&2,String> <- wrappedRow(cells,columns,True{},theme)
    rows : List<&2,String> <- renderedRows(body,columns,theme,border(columns,"├─","─┼─","─┤"))
    return TableResult{border(columns,"┌─","─┬─","─┐") <> List.append(&2,String,heading,border(columns,"├─","─┼─","─┤") <> List.append(&2,String,rows,border(columns,"└─","─┴─","─┘") <> Nil{})),tableRemaining(parsed)}
def tableRendered(+header: String,+rest: List<&2,String>,+theme: MarkdownTheme,+width: Nat,+links: Bool) -> IO(TableResult):
  Bool.pick(Unit -> IO(TableResult),Nat.is_lt(width,4n * List.length(&2,String,tableHeader(header)) + 1n),
    _ => IO.pure(TableResult,narrowTable(header,rest,width)),_ => tableRegular(header,rest,theme,width,links))(Unit{})
@unsafe def renderBlocks(lines: List<&2,String>,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,+width: Nat,+links: Bool) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case +line <> +rest:
      Bool.pick(Unit -> IO(List<&2,String>),String.starts_with(line,"```"),
        _ => do IO<List<&2,String>>:
          +fence : Fence <- IO.pure(Fence,collectFence(rest,"```",Nil{}))
          rendered : List<&2,String> <- fenceRendered(line,fenceLines(fence),theme)
          following : List<&2,String> <- renderBlocks(fenceRest(fence),theme,style,width,links)
          return afterFence(rendered,fenceRest(fence),following),
        _ => Bool.pick(Unit -> IO(List<&2,String>),Bool.not(Maybe.is_none(&2,BlockLine,quoteLine(line))),
          _ => do IO<List<&2,String>>:
            +group : QuoteGroup <- IO.pure(QuoteGroup,collectQuote(rest,Nil{}))
            first : List<&2,String> <- blockLine(line,theme,style,width,links)
            more : List<&2,String> <- renderQuoteLines(quoteLines(group),theme,width,links)
            following : List<&2,String> <- renderBlocks(quoteRest(group),theme,style,width,links)
            return afterFence(List.append(&2,String,first,more),quoteRest(group),following),
        _ => Bool.pick(Unit -> IO(List<&2,String>),isTable(line,rest),
          _ => do IO<List<&2,String>>:
            +table : TableResult <- tableRendered(line,rest,theme,width,links)
            following : List<&2,String> <- renderBlocks(tableRest(table),theme,style,width,links)
            return List.append(&2,String,tableLines(table),following),
          _ => do IO<List<&2,String>>:
            rendered : List<&2,String> <- Bool.pick(Unit -> IO(List<&2,String>),Text.blank(line),_ => IO.pure(List<&2,String>,"" <> Nil{}),_ => blockLine(line,theme,style,width,links))(Unit{})
            following : List<&2,String> <- renderBlocks(rest,theme,style,width,links)
            return withSpacing(line,rendered,rest,following))(Unit{}))(Unit{}))(Unit{})

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
def uncached(+state: Markdown,+width: Nat) -> IO(Markdown & List<&2,String>):
  match state:
    case Markdown{+source,x,_,theme,style,options,_}:
      do IO<Markdown & List<&2,String>>:
        +transformedText : String <- transformed(source,Nat.max(1n,width - x * 2n),options)
        Bool.pick(Unit -> IO(Markdown & List<&2,String>),Text.blank(transformedText),
          _ => IO.pure(Markdown & List<&2,String>,rendered(state,width,Nil{})),
          _ => do IO<Markdown & List<&2,String>>:
            blocks : List<&2,String> <- renderBlocks(preparedLines(trimTrailing(Strings.split(String.join(Strings.split(transformedText,'\t'),"   "),'\n')),options),theme,style,Nat.max(1n,width - x * 2n),linkCapability(options))
            finish(state,width,blocks))(Unit{})
def render(+state: Markdown,+width: Nat) -> IO(Markdown & List<&2,String>):
  match state:
    case Markdown{_,_,_,_,_,_,Some{Cache{oldWidth,lines}}}:
      Bool.pick(Unit -> IO(Markdown & List<&2,String>),Nat.is_eq(oldWidth,width),_ => IO.pure(Markdown & List<&2,String>,(state,lines)),_ => uncached(state,width))(Unit{})
    case _: uncached(state,width)
