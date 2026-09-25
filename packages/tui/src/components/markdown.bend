import Base
import ../utils.bend as U
import ../latex.bend as Latex
import ../terminal-image.bend as Image
import ../../../runtime/src/callback.bend as C
import ../../../runtime/src/text.bend as Text
import ../../../runtime/src/string.bend as Strings
import ../../../runtime/src/ecma-regex.bend as Re
import ../../../runtime/src/marked/tokens.bend as T
import ../../../runtime/src/marked/rules.bend as Rules
import ../../../runtime/src/marked/helpers.bend as MarkedHelpers
import ../../../runtime/src/marked/tokenizer.bend as Tokenizer
import ../../../runtime/src/marked/lexer.bend as Marked

# pi's Markdown component (packages/tui/src/components/markdown.ts): the text
# is lexed with a Marked instance (marked 18.0.11 with pi's LaTeX
# extensions and strict strikethrough) and the tokens render as styled
# terminal lines, wrapped to the width and cached per width.
#
# Language-driven: theme functions are callbacks (rendering is IO); the
# OSC 8 hyperlink capability is the `hyperlinks` option (upstream reads
# getCapabilities()); an inline style context names its text style instead
# of holding a function.

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
def new(+text: String,+paddingX: Nat,+paddingY: Nat,+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,+options: Maybe<&2,MarkdownOptions>) -> Markdown:
  Markdown{text,paddingX,paddingY,theme,style,Maybe.default(&2,MarkdownOptions,options,defaultOptions()),None{}}
def setText(+state: Markdown,+text: String) -> Markdown:
  match state: case Markdown{_,x,y,theme,style,options,_}: Markdown{text,x,y,theme,style,options,None{}}
def invalidate(+state: Markdown) -> Markdown:
  match state: case Markdown{text,x,y,theme,style,options,_}: Markdown{text,x,y,theme,style,options,None{}}

# LaTeX tokens
# ------------
# pi's `latex` and `latexBlock` Marked extensions (the `value` of their
# Generic tokens). Their expressions are matched directly over the source's
# scalars.

type Latex is Data: Latex{text: String,pending: Bool}
def latexToken(+name: String,+raw: String,+text: String,+pending: Bool) -> T.Token<Latex>: T.Generic{name,raw,Latex{text,pending}}

def startsWithText(+codes: List<&2,U32>,+prefix: String) -> Bool:
  match codes prefix:
    case _ SNil{}: True{}
    case Nil{} SCon{_,_}: False{}
    case code <> rest SCon{Chr{expected},more}: U32.is_eq(code,expected) && startsWithText(rest,more)
def isAsciiLetter(+code: U32) -> Bool: (U32.is_ge(code,65) && U32.is_le(code,90)) || (U32.is_ge(code,97) && U32.is_le(code,122))
def isDigitCode(+code: U32) -> Bool: U32.is_ge(code,48) && U32.is_le(code,57)
def isIdentifierCode(+code: U32) -> Bool: isAsciiLetter(code) || isDigitCode(code) || U32.is_eq(code,95)
def isMathSymbol(+code: U32) -> Bool: String.contains("_^=+*/<>()[]|±≤≥≠≈∈→⇒∞∫∑√-",SCon{Chr{code},SNil{}})
# `/\\[A-Za-z]+|[_^=+*/<>()[\]|±≤≥≠≈∈→⇒∞∫∑√-]/.test(source)`
def looksLikePendingDollarMath(codes: List<&2,U32>) -> Bool:
  match codes:
    case Nil{}: False{}
    case +code <> +rest:
      Bool.pick(Unit -> Bool,(U32.is_eq(code,92) && isAsciiLetter(Maybe.default(&2,U32,List.head(&2,U32,rest),0))) || isMathSymbol(code),_ => True{},_ => looksLikePendingDollarMath(rest))(Unit{})

# findClosingDelimiter: the first `closing` not preceded by an odd run of
# backslashes; `run` counts the backslashes before the current scalar and
# `skip` the rest of an escaped occurrence.
def closingFrom(+codes: List<&2,U32>,+closing: String,+run: Nat,+skip: Nat,+index: Nat) -> Maybe<&2,Nat>:
  match codes:
    case Nil{}: None{}
    case +code <> +rest:
      +here = Nat.is_eq(skip,0n) && startsWithText(code <> rest,closing)
      Bool.pick(Unit -> Maybe<&2,Nat>,here && Nat.is_eq(Nat.mod(run,2n),0n),_ => Some{index},
        _ => closingFrom(rest,closing,Bool.pick(Nat,U32.is_eq(code,92),run + 1n,0n),Bool.pick(Nat,here,String.length(closing) - 1n,skip - 1n),index + 1n))(Unit{})
def isSpaceCode(+code: U32) -> Bool: Re.isSpaceCode(code)
def lastCode(+codes: List<&2,U32>) -> Maybe<&2,U32>: List.last(&2,U32,codes)
def shellTail(+codes: List<&2,U32>) -> Bool:
  match codes:
    case Nil{}: True{}
    case +code <> +rest:
      Bool.pick(Unit -> Bool,(U32.is_ge(code,65) && U32.is_le(code,90)) || isDigitCode(code) || U32.is_eq(code,95),_ => shellTail(rest),
        _ => Bool.not(isIdentifierCode(code)) && Bool.not(isSpaceCode(code)) && List.is_empty(&2,U32,rest))(Unit{})
# `/^[A-Z_][A-Z0-9_]*(?:[^A-Za-z0-9_\s])?$/`
def shellVariable(+codes: List<&2,U32>) -> Bool:
  match codes:
    case +code <> rest: ((U32.is_ge(code,65) && U32.is_le(code,90)) || U32.is_eq(code,95)) && shellTail(rest)
    case Nil{}: False{}
def startsWithIdentifier(+codes: List<&2,U32>) -> Bool:
  match codes:
    case +code <> _: isAsciiLetter(code) || U32.is_eq(code,95)
    case Nil{}: False{}
def startsWithDigit(+codes: List<&2,U32>) -> Bool:
  match codes:
    case +code <> _: isDigitCode(code)
    case Nil{}: False{}
def spaceCode(+code: Maybe<&2,U32>) -> Bool:
  match code:
    case Some{+found}: isSpaceCode(found)
    case None{}: False{}
def endsWithSpace(+codes: List<&2,U32>) -> Bool: spaceCode(lastCode(codes))
# A single dollar is no math before a digit (currency), after a space, as a
# shell variable before a word, or around a code span.
def dollarRejected(+inner: List<&2,U32>,+after: List<&2,U32>) -> Bool:
  endsWithSpace(inner) || startsWithDigit(after) || (shellVariable(inner) && startsWithIdentifier(after)) || Marked.containsCode(inner,96)
def inlineClosed(+source: List<&2,U32>,+opening: Nat,+closing: String,+index: Nat) -> Maybe<&2,T.Token<Latex>>:
  +inner = Tokenizer.take(Tokenizer.drop(source,opening),index - opening)
  Bool.pick(Unit -> Maybe<&2,T.Token<Latex>>,List.is_empty(&2,U32,inner) || Marked.containsCode(inner,10),_ => None{},
    _ => Some{latexToken("latex",Tokenizer.textOf(Tokenizer.take(source,index + String.length(closing))),Tokenizer.textOf(inner),False{})})(Unit{})
def inlineFound(+source: List<&2,U32>,+opening: Nat,+closing: String,+single: Bool,+backslash: Bool,+found: Maybe<&2,Nat>) -> Maybe<&2,T.Token<Latex>>:
  match found:
    case None{}:
      +pending = Tokenizer.drop(source,opening)
      Bool.pick(Unit -> Maybe<&2,T.Token<Latex>>,backslash || looksLikePendingDollarMath(pending),
        _ => Some{latexToken("latex",Tokenizer.textOf(source),Tokenizer.textOf(pending),True{})},_ => None{})(Unit{})
    case Some{+index}:
      Bool.pick(Unit -> Maybe<&2,T.Token<Latex>>,single && dollarRejected(Tokenizer.take(Tokenizer.drop(source,opening),index - opening),Tokenizer.drop(source,index + 1n)),
        _ => None{},_ => inlineClosed(source,opening,closing,index))(Unit{})
def inlineDelimited(+source: List<&2,U32>,+opening: Nat,+closing: String,+single: Bool,+backslash: Bool) -> Maybe<&2,T.Token<Latex>>:
  inlineFound(source,opening,closing,single,backslash,closingFrom(Tokenizer.drop(source,opening),closing,0n,0n,opening))
def startsWithSpaceAfter(+codes: List<&2,U32>) -> Bool:
  match codes:
    case _ <> +code <> _: isSpaceCode(code)
    case _: False{}
def inlineLatex(+source: List<&2,U32>) -> Maybe<&2,T.Token<Latex>>:
  Bool.pick(Unit -> Maybe<&2,T.Token<Latex>>,startsWithText(source,"$$"),_ => inlineDelimited(source,2n,"$$",False{},False{}),
    _ => Bool.pick(Unit -> Maybe<&2,T.Token<Latex>>,startsWithText(source,"\\("),_ => inlineDelimited(source,2n,"\\)",False{},True{}),
    _ => Bool.pick(Unit -> Maybe<&2,T.Token<Latex>>,startsWithText(source,"\\["),_ => inlineDelimited(source,2n,"\\]",False{},True{}),
    _ => Bool.pick(Unit -> Maybe<&2,T.Token<Latex>>,startsWithText(source,"$") && Bool.not(startsWithSpaceAfter(source)),_ => inlineDelimited(source,1n,"$",True{},False{}),_ => None{})(Unit{}))(Unit{}))(Unit{}))(Unit{})
# The latex extension's start: the first `$`, `\(` or `\[`.
def inlineStartFrom(+codes: List<&2,U32>,+index: Nat) -> Maybe<&2,Nat>:
  match codes:
    case Nil{}: None{}
    case +code <> +rest:
      Bool.pick(Unit -> Maybe<&2,Nat>,U32.is_eq(code,36) || (U32.is_eq(code,92) && (startsWithText(rest,"(") || startsWithText(rest,"["))),_ => Some{index},_ => inlineStartFrom(rest,index + 1n))(Unit{})
# tokenizeInlineLatex: `$$…$$`, `\(…\)`, `\[…\]` or `$…$` on one line; an
# unclosed `\(`/`\[`, or unclosed dollars before math-like text, is pending
# (the rest of the source, shown raw while streaming).
def tokenizeInlineLatex(source: List<&2,U32>) -> Maybe<&2,T.Token<Latex>>: inlineLatex(source)
def startInlineLatex(source: List<&2,U32>) -> Maybe<&2,Nat>: inlineStartFrom(source,0n)

# ` {0,3}` then `opening`: the scalars after the opening.
def afterIndent(codes: List<&2,U32>,+count: Nat) -> Maybe<&2,List<&2,U32>>:
  match codes:
    case +code <> +rest:
      Bool.pick(Unit -> Maybe<&2,List<&2,U32>>,U32.is_eq(code,32),_ => Bool.pick(Unit -> Maybe<&2,List<&2,U32>>,Nat.is_ge(count,3n),_ => None{},_ => afterIndent(rest,count + 1n))(Unit{}),_ => Some{code <> rest})(Unit{})
    case Nil{}: Some{Nil{}}
def openingAfter(indented: Maybe<&2,List<&2,U32>>,+opening: String) -> Maybe<&2,List<&2,U32>>:
  match indented:
    case Some{+rest}: Bool.pick(Unit -> Maybe<&2,List<&2,U32>>,startsWithText(rest,opening),_ => Some{Tokenizer.drop(rest,String.length(opening))},_ => None{})(Unit{})
    case None{}: None{}
def openedBlock(+source: List<&2,U32>,+opening: String) -> Maybe<&2,List<&2,U32>>: openingAfter(afterIndent(source,0n),opening)
def dropSpaceTab(+codes: List<&2,U32>) -> List<&2,U32>:
  match codes:
    case +code <> +rest: Bool.pick(Unit -> List<&2,U32>,U32.is_eq(code,32) || U32.is_eq(code,9),_ => dropSpaceTab(rest),_ => code <> rest)(Unit{})
    case Nil{}: Nil{}
# `[ \t]*(?:\n)?` after the opening.
def contentStart(+codes: List<&2,U32>) -> List<&2,U32>:
  +rest = dropSpaceTab(codes)
  Bool.pick(Unit -> List<&2,U32>,Tokenizer.startsWith(rest,'\n'),_ => Tokenizer.drop(rest,1n),_ => rest)(Unit{})
# `closing[ \t]*(?:\n|$)` at the start: the scalars it takes.
def spaceTabRun(codes: List<&2,U32>,+count: Nat) -> Maybe<&2,Nat>:
  match codes:
    case Nil{}: Some{count}
    case +code <> +rest:
      Bool.pick(Unit -> Maybe<&2,Nat>,U32.is_eq(code,32) || U32.is_eq(code,9),_ => spaceTabRun(rest,count + 1n),
        _ => Bool.pick(Maybe<&2,Nat>,U32.is_eq(code,10),Some{count + 1n},None{}))(Unit{})
def closingLine(+codes: List<&2,U32>,+closing: String) -> Maybe<&2,Nat>:
  Bool.pick(Unit -> Maybe<&2,Nat>,startsWithText(codes,closing),_ => Maybe.map(&2,Nat,Nat,taken => taken + String.length(closing),spaceTabRun(Tokenizer.drop(codes,String.length(closing)),0n)),_ => None{})(Unit{})
type BlockClose is Data: BlockClose{index: Nat,taken: Nat}
# `([\s\S]*?)closing[ \t]*(?:\n|$)`: the shortest content before a closing line.
def blockCloseFrom(+codes: List<&2,U32>,+closing: String,+index: Nat) -> Maybe<&2,BlockClose>:
  match codes:
    case Nil{}: Maybe.map(&2,Nat,BlockClose,taken => BlockClose{index,taken},closingLine(Nil{},closing))
    case +code <> +rest:
      Bool.pick(Unit -> Maybe<&2,BlockClose>,Maybe.is_some(&2,Nat,closingLine(code <> rest,closing)),_ => Some{BlockClose{index,Maybe.default(&2,Nat,closingLine(code <> rest,closing),0n)}},_ => blockCloseFrom(rest,closing,index + 1n))(Unit{})
def blockClosed(+source: List<&2,U32>,+content: List<&2,U32>,+found: Maybe<&2,BlockClose>) -> Maybe<&2,T.Token<Latex>>:
  match found:
    case None{}: None{}
    case Some{BlockClose{+index,taken}}:
      +text = Tokenizer.take(content,index)
      Bool.pick(Unit -> Maybe<&2,T.Token<Latex>>,List.is_empty(&2,U32,text),_ => None{},
        _ => Some{latexToken("latexBlock",Tokenizer.textOf(Tokenizer.take(source,Tokenizer.codesLength(source,0n) - Tokenizer.codesLength(content,0n) + index + taken)),Text.trim(Tokenizer.textOf(text)),False{})})(Unit{})
def closedBlock(+source: List<&2,U32>,+opened: Maybe<&2,List<&2,U32>>,+closing: String) -> Maybe<&2,T.Token<Latex>>:
  match opened:
    case None{}: None{}
    case Some{+after}: blockClosed(source,contentStart(after),blockCloseFrom(contentStart(after),closing,0n))
def pendingBlock(+source: List<&2,U32>,+opened: Maybe<&2,List<&2,U32>>,+dollars: Bool) -> Maybe<&2,T.Token<Latex>>:
  match opened:
    case None{}: None{}
    case Some{+after}:
      +text = contentStart(after)
      Bool.pick(Unit -> Maybe<&2,T.Token<Latex>>,Bool.not(dollars) || (Bool.not(List.is_empty(&2,U32,text)) && looksLikePendingDollarMath(text)),
        _ => Some{latexToken("latexBlock",Tokenizer.textOf(source),Tokenizer.textOf(text),True{})},_ => None{})(Unit{})
def orElse(+first: Maybe<&2,T.Token<Latex>>,+second: Maybe<&2,T.Token<Latex>>) -> Maybe<&2,T.Token<Latex>>:
  match first:
    case Some{token}: Some{token}
    case None{}: second
# tokenizeBlockLatex: display math from `$$` or `\[` after up to three spaces
# to a closing delimiter ending a line; an unclosed `\[`, or `$$` before
# math-like text, is pending and takes the rest of the source.
def tokenizeBlockLatex(+source: List<&2,U32>) -> Maybe<&2,T.Token<Latex>>:
  orElse(closedBlock(source,openedBlock(source,"$$"),"$$"),orElse(closedBlock(source,openedBlock(source,"\\["),"\\]"),
    orElse(pendingBlock(source,openedBlock(source,"\\["),False{}),pendingBlock(source,openedBlock(source,"$$"),True{}))))
def blockLatex(source: List<&2,U32>) -> Maybe<&2,T.Token<Latex>>: tokenizeBlockLatex(source)
# The latexBlock extension's start, `/(?:^|\n) {0,3}(?:\$\$|\\\[)/`: the
# first line opening display math.
def blockStartFrom(+codes: List<&2,U32>,+lineStart: Bool,+index: Nat) -> Maybe<&2,Nat>:
  match codes:
    case Nil{}: None{}
    case +code <> +rest:
      Bool.pick(Unit -> Maybe<&2,Nat>,Bool.pick(Unit -> Bool,lineStart,_ => Maybe.is_some(&2,List<&2,U32>,openedBlock(code <> rest,"$$")) || Maybe.is_some(&2,List<&2,U32>,openedBlock(code <> rest,"\\[")),_ => False{})(Unit{}),_ => Some{index},
        _ => blockStartFrom(rest,U32.is_eq(code,10),index + 1n))(Unit{})
def startBlockLatex(source: List<&2,U32>) -> Maybe<&2,Nat>: blockStartFrom(source,True{},0n)

# StrictStrikethroughTokenizer.del: only `~~`, by
# `/^(~~)(?=[^\s~])((?:\\.|[^\\])*?(?:\\.|[^\s~\\]))\1(?=[^~]|$)/`.
def isLineBreak(+code: U32) -> Bool: Re.isLineTerminator(code)
# Content units are an escape (a backslash and a character on its line) or
# any other character; the span ends after a unit that is an escape or not
# a space or `~`, before `~~` not followed by `~`.
def strictClose(+codes: List<&2,U32>,+escaped: Bool,+count: Nat) -> Maybe<&2,Nat>:
  match codes:
    case Nil{}: None{}
    case +code <> +rest:
      Bool.pick(Unit -> Maybe<&2,Nat>,Bool.not(escaped) && U32.is_eq(code,92),
        _ => Bool.pick(Unit -> Maybe<&2,Nat>,List.is_empty(&2,U32,rest) || isLineBreak(Maybe.default(&2,U32,List.head(&2,U32,rest),10)),_ => None{},_ => strictClose(rest,True{},count + 1n))(Unit{}),
        _ => Bool.pick(Unit -> Maybe<&2,Nat>,(escaped || Bool.not(isSpaceCode(code) || U32.is_eq(code,126))) && startsWithText(rest,"~~") && Bool.not(startsWithText(Tokenizer.drop(rest,2n),"~")),
          _ => Some{count + 1n},_ => strictClose(rest,False{},count + 1n))(Unit{}))(Unit{})
def strictFound(+src: List<&2,U32>,+found: Maybe<&2,Nat>) -> Maybe<&2,Tokenizer.Delimited>:
  match found:
    case Some{+length}: Some{Tokenizer.Delimited{Tokenizer.textOf(Tokenizer.take(src,length + 4n)),Tokenizer.textOf(Tokenizer.take(Tokenizer.drop(src,2n),length))}}
    case None{}: None{}
def strictOpened(+src: List<&2,U32>,+after: List<&2,U32>) -> Maybe<&2,Tokenizer.Delimited>:
  match after:
    case +code <> +rest: Bool.pick(Unit -> Maybe<&2,Tokenizer.Delimited>,isSpaceCode(code) || U32.is_eq(code,126),_ => None{},_ => strictFound(src,strictClose(code <> rest,False{},0n)))(Unit{})
    case Nil{}: None{}
def strictAt(+src: List<&2,U32>) -> Maybe<&2,Tokenizer.Delimited>:
  Bool.pick(Unit -> Maybe<&2,Tokenizer.Delimited>,startsWithText(src,"~~"),_ => strictOpened(src,Tokenizer.drop(src,2n)),_ => None{})(Unit{})
def strictDel(rules: Rules.Inline,src: List<&2,U32>,masked: List<&2,U32>,previous: Maybe<&2,U32>) -> Maybe<&2,Tokenizer.Delimited>: strictAt(src)

def piExtensions() -> Marked.Extensions<Latex>: Marked.Extensions{blockLatex,startBlockLatex,tokenizeInlineLatex,startInlineLatex,strictDel}

# Streamed code fences
# --------------------
# trimPartialClosingFences: a code block whose last line is an incomplete
# closing fence (a streamed "`" or "``") loses that line, so the block does
# not shrink when the last fence character arrives (pi issue #5825).

def fenceRun(+text: String,+char: Char,+count: Nat) -> Nat:
  match text:
    case SCon{+next,+rest}: Bool.pick(Unit -> Nat,Char.is_eq(next,char),_ => fenceRun(rest,char,count + 1n),_ => count)(Unit{})
    case SNil{}: count
# `/^(`{3,}|~{3,})/`: the opening fence's length.
def fenceMarker(+raw: String) -> Maybe<&2,Nat>:
  +backticks = fenceRun(raw,'`',0n)
  +tildes = fenceRun(raw,'~',0n)
  Bool.pick(Unit -> Maybe<&2,Nat>,Nat.is_ge(backticks,3n),_ => Some{backticks},_ => Bool.pick(Maybe<&2,Nat>,Nat.is_ge(tildes,3n),Some{tildes},None{}))(Unit{})
def lastLineOf(+lines: List<&2,String>) -> String: Maybe.default(&2,String,List.last(&2,String,lines),"")
def partialFence(+marker: Maybe<&2,Nat>,+raw: String,+last: String) -> Bool:
  match marker:
    case Some{+length}:
      Bool.not(String.is_empty(last)) && Nat.is_lt(String.length(last),length) && Nat.is_eq(fenceRun(last,Maybe.default(&2,Char,String.get(raw,0n),'`'),0n),String.length(last))
    case None{}: False{}
def withoutTrailingNewline(+text: String) -> String: Bool.pick(Unit -> String,MarkedHelpers.endsWithChar(text,'\n'),_ => MarkedHelpers.dropEnd(text,1n),_ => text)(Unit{})
def fenceTrimmed(+token: T.Token<Latex>) -> T.Token<Latex>:
  match token:
    case T.Code{+raw,style,lang,+text}:
      +last = lastLineOf(MarkedHelpers.linesOf(raw))
      T.Code{raw,style,lang,Bool.pick(Unit -> String,partialFence(fenceMarker(raw),raw,last),_ => withoutTrailingNewline(MarkedHelpers.dropEnd(text,String.length(last))),_ => text)(Unit{})}
    case other: other
# Tokens newest first; the last token, or the last of the last list item or
# blockquote, is trimmed.
@unsafe def trimmedLast(+reversed: List<&2,T.Token<Latex>>) -> List<&2,T.Token<Latex>>:
  match reversed:
    case Nil{}: Nil{}
    case T.ListToken{raw,ordered,start,loose,items} <> earlier: T.ListToken{raw,ordered,start,loose,List.reverse(&2,T.Token<Latex>,trimmedLast(List.reverse(&2,T.Token<Latex>,items)))} <> earlier
    case T.ListItem{raw,task,checked,loose,text,inner} <> earlier: T.ListItem{raw,task,checked,loose,text,List.reverse(&2,T.Token<Latex>,trimmedLast(List.reverse(&2,T.Token<Latex>,inner)))} <> earlier
    case T.Blockquote{raw,text,inner} <> earlier: T.Blockquote{raw,text,List.reverse(&2,T.Token<Latex>,trimmedLast(List.reverse(&2,T.Token<Latex>,inner)))} <> earlier
    case last <> earlier: fenceTrimmed(last) <> earlier
def trimPartialClosingFences(+tokens: List<&2,T.Token<Latex>>) -> List<&2,T.Token<Latex>>: List.reverse(&2,T.Token<Latex>,trimmedLast(List.reverse(&2,T.Token<Latex>,tokens)))

# Styles
# ------

def themeHeading(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{found,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: found
def themeLink(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,found,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: found
def themeLinkUrl(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,found,_,_,_,_,_,_,_,_,_,_,_,_,_}: found
def themeCode(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,found,_,_,_,_,_,_,_,_,_,_,_,_}: found
def themeCodeBlock(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,found,_,_,_,_,_,_,_,_,_,_,_}: found
def themeCodeBlockBorder(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,found,_,_,_,_,_,_,_,_,_,_}: found
def themeQuote(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,found,_,_,_,_,_,_,_,_,_}: found
def themeQuoteBorder(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,found,_,_,_,_,_,_,_,_}: found
def themeHr(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,found,_,_,_,_,_,_,_}: found
def themeListBullet(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,found,_,_,_,_,_,_}: found
def themeBold(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,found,_,_,_,_,_}: found
def themeItalic(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,found,_,_,_,_}: found
def themeStrikethrough(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,found,_,_,_}: found
def themeUnderline(+theme: MarkdownTheme) -> Style():
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,_,found,_,_}: found
def codeIndent(+theme: MarkdownTheme) -> String:
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,indent}: Maybe.default(&2,String,indent,"  ")
def styled(+style: Style(),+text: String) -> IO(String): C.call(String,String,style,text)

# What rendering reads: the theme, the default text style and the options.
type Env is Data: Env{theme: MarkdownTheme,style: Maybe<&2,DefaultTextStyle>,options: MarkdownOptions}
def envTheme(+env: Env) -> MarkdownTheme:
  match env: case Env{theme,_,_}: theme
def envStyle(+env: Env) -> Maybe<&2,DefaultTextStyle>:
  match env: case Env{_,style,_}: style
def envOptions(+env: Env) -> MarkdownOptions:
  match env: case Env{_,_,options}: options
def preserveOrderedListMarkers(+options: MarkdownOptions) -> Bool:
  match options: case MarkdownOptions{found,_,_,_,_}: found
def preserveBackslashEscapes(+options: MarkdownOptions) -> Bool:
  match options: case MarkdownOptions{_,found,_,_,_}: found
def renderLatexOption(+options: MarkdownOptions) -> Bool:
  match options: case MarkdownOptions{_,_,_,found,_}: found
def hyperlinksOption(+options: MarkdownOptions) -> Bool:
  match options: case MarkdownOptions{_,_,_,_,found}: found

def applyOptional(+text: String,+style: Maybe<&2,Style()>) -> IO(String):
  match style:
    case None{}: IO.pure(String,text)
    case Some{callback}: C.call(String,String,callback,text)
def applyIf(+text: String,+enabled: Bool,+style: Style()) -> IO(String):
  Bool.pick(Unit -> IO(String),enabled,_ => C.call(String,String,style,text),_ => IO.pure(String,text))(Unit{})
# applyDefaultStyle: the colour, then bold, italic, strikethrough and
# underline from the theme (the background applies per line later).
def defaultStyled(+theme: MarkdownTheme,+style: Maybe<&2,DefaultTextStyle>,+text: String) -> IO(String):
  match style:
    case None{}: IO.pure(String,text)
    case Some{DefaultTextStyle{color,_,bold,italic,strike,underline}}:
      do IO<String>:
        +colored : String <- applyOptional(text,color)
        +strong : String <- applyIf(colored,bold,themeBold(theme))
        +emphasis : String <- applyIf(strong,italic,themeItalic(theme))
        +deleted : String <- applyIf(emphasis,strike,themeStrikethrough(theme))
        applyIf(deleted,underline,themeUnderline(theme))
def applyDefaultStyle(+env: Env,+text: String) -> IO(String): defaultStyled(envTheme(env),envStyle(env),text)

# Inline style contexts
# ---------------------
# The style applied to text and the prefix that restores it after an inline
# token's own reset (upstream's InlineStyleContext holds the function).

type TextStyle is Data:
  # applyDefaultStyle
  DefaultText{}
  # A heading's style: heading(bold(underline(text))) at level 1,
  # heading(bold(text)) below.
  HeadingText{level: Nat}
  # Text inside blockquotes keeps no default style.
  PlainText{}
  # quote(italic(text)), for blockquote lines.
  QuoteText{}
type Context is Data: Context{text: TextStyle,prefix: String}
def textStyled(+env: Env,+style: TextStyle,+text: String) -> IO(String):
  match style:
    case DefaultText{}: applyDefaultStyle(env,text)
    case HeadingText{1n}:
      do IO<String>:
        +underlined : String <- styled(themeUnderline(envTheme(env)),text)
        +bold : String <- styled(themeBold(envTheme(env)),underlined)
        styled(themeHeading(envTheme(env)),bold)
    case HeadingText{_}:
      do IO<String>:
        +bold : String <- styled(themeBold(envTheme(env)),text)
        styled(themeHeading(envTheme(env)),bold)
    case PlainText{}: IO.pure(String,text)
    case QuoteText{}:
      do IO<String>:
        +italic : String <- styled(themeItalic(envTheme(env)),text)
        styled(themeQuote(envTheme(env)),italic)
def beforeSentinel(+text: String,+reversed: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{+char,+rest}: Bool.pick(Unit -> String,U32.is_eq(Char.to_u32(char),0),_ => String.reverse(reversed),_ => beforeSentinel(rest,SCon{char,reversed}))(Unit{})
# getStylePrefix: what the style writes before its text (styling "\0").
def stylePrefix(+env: Env,+style: TextStyle) -> IO(String):
  do IO<String>:
    +marked : String <- textStyled(env,style,"\u{0}")
    return beforeSentinel(marked,"")
def contextOf(+env: Env,+style: TextStyle) -> IO(Context):
  do IO<Context>:
    +prefix : String <- stylePrefix(env,style)
    return Context{style,prefix}
def contextText(+context: Context) -> TextStyle:
  match context: case Context{style,_}: style
def contextPrefix(+context: Context) -> String:
  match context: case Context{_,prefix}: prefix
# `styleContext ?? this.getDefaultInlineStyleContext()`
def resolvedContext(+env: Env,+context: Maybe<&2,Context>) -> IO(Context):
  match context:
    case Some{found}: IO.pure(Context,found)
    case None{}: contextOf(env,DefaultText{})
def styledSegments(+env: Env,+style: TextStyle,+segments: List<&2,String>,+reversed: List<&2,String>) -> IO(String):
  match segments:
    case Nil{}: IO.pure(String,String.join(List.reverse(&2,String,reversed),"\n"))
    case segment <> rest:
      do IO<String>:
        +line : String <- textStyled(env,style,segment)
        styledSegments(env,style,rest,line <> reversed)
# applyTextWithNewlines: each line styled on its own.
def applyText(+env: Env,+context: Context,+text: String) -> IO(String): styledSegments(env,contextText(context),MarkedHelpers.linesOf(text),Nil{})
@unsafe def withoutTrailingPrefix(+text: String,+prefix: String) -> String:
  Bool.pick(Unit -> String,Bool.not(String.is_empty(prefix)) && String.ends_with(text,prefix),_ => withoutTrailingPrefix(MarkedHelpers.dropEnd(text,String.length(prefix)),prefix),_ => text)(Unit{})

# Inline tokens
# -------------

def latexText(+enabled: Bool,+value: Latex,+raw: String,+display: Bool) -> String:
  match value:
    case Latex{text,pending}: Bool.pick(Unit -> String,Bool.not(pending) && enabled,_ => Maybe.default(&2,String,Latex.renderLatex(text,Latex.RenderLatexOptions{display}),raw),_ => raw)(Unit{})
# terminal-image.ts hyperlink(text, url).
def hyperlink(+text: String,+url: String) -> String: "\u{1b}]8;;" ++ url ++ "\u{1b}\\" ++ text ++ "\u{1b}]8;;\u{1b}\\"
def withoutMailto(+href: String) -> String: Bool.pick(Unit -> String,String.starts_with(href,"mailto:"),_ => String.drop(href,7n),_ => href)(Unit{})
# A link: OSC 8 when the terminal has hyperlinks (the URL stays hidden),
# else the URL in parentheses unless the text is the URL.
def linkRendered(+env: Env,+prefix: String,+href: String,+text: String,+label: String) -> IO(String):
  do IO<String>:
    +underlined : String <- styled(themeUnderline(envTheme(env)),label)
    +link : String <- styled(themeLink(envTheme(env)),underlined)
    Bool.pick(Unit -> IO(String),hyperlinksOption(envOptions(env)),_ => IO.pure(String,hyperlink(link,href) ++ prefix),
      _ => Bool.pick(Unit -> IO(String),String.eq(text,href) || String.eq(text,withoutMailto(href)),_ => IO.pure(String,link ++ prefix),
        _ => do IO<String>:
          +url : String <- styled(themeLinkUrl(envTheme(env))," (" ++ href ++ ")")
          return link ++ url ++ prefix)(Unit{}))(Unit{})
def wrappedStyle(+style: Style(),+prefix: String,+content: String) -> IO(String):
  do IO<String>:
    +text : String <- styled(style,content)
    return text ++ prefix
# The default case: a token's text, if it has one.
def defaultText(+env: Env,+context: Context,+token: T.Token<Latex>) -> IO(String):
  match token:
    case T.Blockquote{_,text,_}: applyText(env,context,text)
    case T.Code{_,_,_,text}: applyText(env,context,text)
    case T.Heading{_,_,text,_}: applyText(env,context,text)
    case T.ListItem{_,_,_,_,text,_}: applyText(env,context,text)
    case T.TableCell{text,_,_,_}: applyText(env,context,text)
    case _: IO.pure(String,"")
# renderInlineTokens: the tokens' text; `pieces` newest first.
@unsafe def renderInline(+env: Env,+tokens: List<&2,T.Token<Latex>>,+context: Context,+pieces: List<&2,String>) -> IO(String):
  match tokens:
    case Nil{}: IO.pure(String,withoutTrailingPrefix(MarkedHelpers.concatReversed(pieces,""),contextPrefix(context)))
    case T.Generic{"latex",+raw,value} <> rest:
      do IO<String>:
        +text : String <- applyText(env,context,latexText(renderLatexOption(envOptions(env)),value,raw,False{}))
        renderInline(env,rest,context,text <> pieces)
    case T.Escape{+raw,+text} <> rest:
      do IO<String>:
        +shown : String <- applyText(env,context,Bool.pick(String,preserveBackslashEscapes(envOptions(env)),raw,text))
        renderInline(env,rest,context,shown <> pieces)
    case T.Text{_,text,Nil{},_} <> rest:
      do IO<String>:
        +shown : String <- applyText(env,context,text)
        renderInline(env,rest,context,shown <> pieces)
    case T.Text{_,_,inner,_} <> rest:
      do IO<String>:
        +shown : String <- renderInline(env,inner,context,Nil{})
        renderInline(env,rest,context,shown <> pieces)
    case T.Paragraph{_,_,inner} <> rest:
      do IO<String>:
        +shown : String <- renderInline(env,inner,context,Nil{})
        renderInline(env,rest,context,shown <> pieces)
    case T.Strong{_,_,inner} <> rest:
      do IO<String>:
        +content : String <- renderInline(env,inner,context,Nil{})
        +shown : String <- wrappedStyle(themeBold(envTheme(env)),contextPrefix(context),content)
        renderInline(env,rest,context,shown <> pieces)
    case T.Em{_,_,inner} <> rest:
      do IO<String>:
        +content : String <- renderInline(env,inner,context,Nil{})
        +shown : String <- wrappedStyle(themeItalic(envTheme(env)),contextPrefix(context),content)
        renderInline(env,rest,context,shown <> pieces)
    case T.Del{_,_,inner} <> rest:
      do IO<String>:
        +content : String <- renderInline(env,inner,context,Nil{})
        +shown : String <- wrappedStyle(themeStrikethrough(envTheme(env)),contextPrefix(context),content)
        renderInline(env,rest,context,shown <> pieces)
    case T.Codespan{_,text} <> rest:
      do IO<String>:
        +shown : String <- wrappedStyle(themeCode(envTheme(env)),contextPrefix(context),text)
        renderInline(env,rest,context,shown <> pieces)
    case T.Link{_,href,_,text,inner} <> rest:
      do IO<String>:
        +label : String <- renderInline(env,inner,context,Nil{})
        +shown : String <- linkRendered(env,contextPrefix(context),href,text,label)
        renderInline(env,rest,context,shown <> pieces)
    case T.Br{_} <> rest: renderInline(env,rest,context,"\n" <> pieces)
    case T.Tag{raw,_,_,_,_} <> rest:
      do IO<String>:
        +shown : String <- applyText(env,context,raw)
        renderInline(env,rest,context,shown <> pieces)
    case T.HTML{raw,_,_,_} <> rest:
      do IO<String>:
        +shown : String <- applyText(env,context,raw)
        renderInline(env,rest,context,shown <> pieces)
    case T.Image{_,_,_,text,_} <> rest:
      do IO<String>:
        +shown : String <- applyText(env,context,text)
        renderInline(env,rest,context,shown <> pieces)
    case T.Generic{_,_,Latex{text,_}} <> rest:
      do IO<String>:
        +shown : String <- applyText(env,context,text)
        renderInline(env,rest,context,shown <> pieces)
    case token <> rest:
      do IO<String>:
        +shown : String <- defaultText(env,context,token)
        renderInline(env,rest,context,shown <> pieces)
def inlineText(+env: Env,+tokens: List<&2,T.Token<Latex>>,+context: Maybe<&2,Context>) -> IO(String):
  do IO<String>:
    +resolved : Context <- resolvedContext(env,context)
    renderInline(env,tokens,resolved,Nil{})

# Tables
# ------

def sum(+values: List<&2,Nat>,+total: Nat) -> Nat:
  match values:
    case Nil{}: total
    case value <> rest: sum(rest,total + value)
def pairwiseMax(+left: List<&2,Nat>,+right: List<&2,Nat>) -> List<&2,Nat>:
  match left right:
    case Nil{} right: right
    case left Nil{}: left
    case +a <> more +b <> rest: Nat.max(a,b) <> pairwiseMax(more,rest)
def widthsOf(+cells: List<&2,String>) -> List<&2,Nat>:
  match cells:
    case Nil{}: Nil{}
    case cell <> rest: U.visibleWidth(cell) <> widthsOf(rest)
# getLongestWordWidth(text, 30): the widest run between whitespace.
def longestFrom(+text: String,+word: String,+longest: Nat) -> Nat:
  match text:
    case SNil{}: Nat.max(longest,U.visibleWidth(String.reverse(word)))
    case SCon{+char,+rest}:
      Bool.pick(Unit -> Nat,MarkedHelpers.isSpace(char),_ => longestFrom(rest,"",Nat.max(longest,U.visibleWidth(String.reverse(word)))),_ => longestFrom(rest,SCon{char,word},longest))(Unit{})
def wordWidths(+cells: List<&2,String>) -> List<&2,Nat>:
  match cells:
    case Nil{}: Nil{}
    case cell <> rest: Nat.max(1n,Nat.min(longestFrom(cell,"",0n),30n)) <> wordWidths(rest)
def rowsNatural(+rows: List<&2,List<&2,String>>,+widths: List<&2,Nat>) -> List<&2,Nat>:
  match rows:
    case Nil{}: widths
    case row <> rest: rowsNatural(rest,pairwiseMax(widths,widthsOf(row)))
def rowsWords(+rows: List<&2,List<&2,String>>,+widths: List<&2,Nat>) -> List<&2,Nat>:
  match rows:
    case Nil{}: widths
    case row <> rest: rowsWords(rest,pairwiseMax(widths,wordWidths(row)))
# `Math.floor(part / total * amount)` in binary64.
def share(+part: Nat,+total: Nat,+amount: Nat) -> Nat:
  Bool.pick(Unit -> Nat,Nat.is_gt(total,0n),_ => U32.to_nat(F64.to_u32(F64.floor(F64.mul(F64.div(U32.to_f64(U32.from_nat(part)),U32.to_f64(U32.from_nat(total))),U32.to_f64(U32.from_nat(amount)))))),_ => 0n)(Unit{})
def growths(+weights: List<&2,Nat>,+total: Nat,+amount: Nat) -> List<&2,Nat>:
  match weights:
    case Nil{}: Nil{}
    case weight <> rest: share(weight,total,amount) <> growths(rest,total,amount)
def added(+left: List<&2,Nat>,+right: List<&2,Nat>) -> List<&2,Nat>:
  match left right:
    case Nil{} _: Nil{}
    case left Nil{}: left
    case a <> more b <> rest: (a + b) <> added(more,rest)
def firstIncremented(+values: List<&2,Nat>,+count: Nat) -> List<&2,Nat>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: Bool.pick(Nat,Nat.is_gt(count,0n),value + 1n,value) <> firstIncremented(rest,count - 1n)
def ones(+count: Nat) -> List<&2,Nat>:
  match count:
    case Zero{}: Nil{}
    case Succ{more}: 1n <> ones(more)
def lessOne(+values: List<&2,Nat>) -> List<&2,Nat>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: (value - 1n) <> lessOne(rest)
# Columns too narrow for their longest words share the room by word width.
def squeezedMinimum(+words: List<&2,Nat>,+count: Nat,+available: Nat) -> List<&2,Nat>:
  +remaining = available - count
  +growth = growths(lessOne(words),sum(lessOne(words),0n),remaining)
  Bool.pick(Unit -> List<&2,Nat>,Nat.is_gt(remaining,0n),_ => firstIncremented(added(ones(count),growth),remaining - sum(growth,0n)),_ => ones(count))(Unit{})
def minimumWidths(+words: List<&2,Nat>,+count: Nat,+available: Nat) -> List<&2,Nat>:
  Bool.pick(Unit -> List<&2,Nat>,Nat.is_gt(sum(words,0n),available),_ => squeezedMinimum(words,count,available),_ => words)(Unit{})
def growPotential(+natural: List<&2,Nat>,+minimum: List<&2,Nat>) -> List<&2,Nat>:
  match natural minimum:
    case Nil{} _: Nil{}
    case _ Nil{}: Nil{}
    case a <> more b <> rest: (a - b) <> growPotential(more,rest)
type Grown is Data: Grown{widths: List<&2,Nat>,remaining: Nat,grew: Bool}
def growPass(+current: List<&2,Nat>,+natural: List<&2,Nat>,+remaining: Nat,+grew: Bool,+reversed: List<&2,Nat>) -> Grown:
  match current natural:
    case Nil{} _: Grown{List.reverse(&2,Nat,reversed),remaining,grew}
    case current Nil{}: Grown{List.append(&2,Nat,List.reverse(&2,Nat,reversed),current),remaining,grew}
    case +value <> more +target <> rest:
      +grow = Nat.is_gt(remaining,0n) && Nat.is_lt(value,target)
      growPass(more,rest,Bool.pick(Nat,grow,remaining - 1n,remaining),grew || grow,Bool.pick(Nat,grow,value + 1n,value) <> reversed)
# Rounding leftovers go one column at a time to columns below their natural
# width.
@unsafe def distributed(+natural: List<&2,Nat>,+grown: Grown) -> List<&2,Nat>:
  match grown:
    case Grown{+widths,+remaining,grew}: Bool.pick(Unit -> List<&2,Nat>,Nat.is_gt(remaining,0n) && grew,_ => distributed(natural,growPass(widths,natural,remaining,False{},Nil{})),_ => widths)(Unit{})
def pairwiseMaxOf(+left: List<&2,Nat>,+right: List<&2,Nat>) -> List<&2,Nat>: pairwiseMax(left,right)
def shrunk(+natural: List<&2,Nat>,+minimum: List<&2,Nat>,+available: Nat) -> List<&2,Nat>:
  +potential = growPotential(natural,minimum)
  +widths = added(minimum,growths(potential,sum(potential,0n),available - sum(minimum,0n)))
  distributed(natural,Grown{widths,available - sum(widths,0n),True{}})
def columnWidths(+natural: List<&2,Nat>,+minimum: List<&2,Nat>,+available: Nat,+overhead: Nat,+width: Nat) -> List<&2,Nat>:
  Bool.pick(Unit -> List<&2,Nat>,Nat.is_le(sum(natural,0n) + overhead,width),_ => pairwiseMaxOf(natural,minimum),_ => shrunk(natural,minimum,available))(Unit{})
def dashes(+widths: List<&2,Nat>) -> List<&2,String>:
  match widths:
    case Nil{}: Nil{}
    case width <> rest: String.repeat("─",width) <> dashes(rest)
def rule(+widths: List<&2,Nat>,+left: String,+middle: String,+right: String) -> String:
  left ++ String.join(dashes(widths),middle) ++ right
# wrapCellText: continuation fragments reset text styles, then every
# fragment restores the surrounding style.
def cellFragments(+lines: List<&2,String>,+prefix: String) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case last <> Nil{}: (last ++ prefix) <> Nil{}
    case line <> rest: (line ++ "\u{1b}[22;23;24;25;27;28;29;39m" ++ prefix) <> cellFragments(rest,prefix)
def wrappedCells(+cells: List<&2,String>,+widths: List<&2,Nat>,+prefix: String) -> List<&2,List<&2,String>>:
  match cells widths:
    case Nil{} _: Nil{}
    case _ Nil{}: Nil{}
    case cell <> rest width <> more: cellFragments(U.wrapTextWithAnsi(cell,Nat.max(1n,width)),prefix) <> wrappedCells(rest,more,prefix)
def height(+cells: List<&2,List<&2,String>>) -> Nat:
  match cells:
    case Nil{}: 0n
    case cell <> rest: Nat.max(List.length(&2,String,cell),height(rest))
def cellLine(+theme: MarkdownTheme,+bold: Bool,+text: String,+width: Nat) -> IO(String):
  +padded = text ++ U.spaces(width - U.visibleWidth(text),"")
  applyIf(padded,bold,themeBold(theme))
def lineParts(+theme: MarkdownTheme,+bold: Bool,+cells: List<&2,List<&2,String>>,+widths: List<&2,Nat>,+index: Nat,+reversed: List<&2,String>) -> IO(String):
  match cells widths:
    case Nil{} _: IO.pure(String,"│ " ++ String.join(List.reverse(&2,String,reversed)," │ ") ++ " │")
    case _ Nil{}: IO.pure(String,"│ " ++ String.join(List.reverse(&2,String,reversed)," │ ") ++ " │")
    case cell <> rest width <> more:
      do IO<String>:
        +part : String <- cellLine(theme,bold,Maybe.default(&2,String,List.get(&2,String,cell,index),""),width)
        lineParts(theme,bold,rest,more,index,part <> reversed)
def rowLines(count: Nat,+theme: MarkdownTheme,+bold: Bool,+cells: List<&2,List<&2,String>>,+widths: List<&2,Nat>,+index: Nat,+reversed: List<&2,String>) -> IO(List<&2,String>):
  match count:
    case Zero{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case Succ{more}:
      do IO<List<&2,String>>:
        +line : String <- lineParts(theme,bold,cells,widths,index,Nil{})
        rowLines(more,theme,bold,cells,widths,index + 1n,line <> reversed)
def tableRow(+theme: MarkdownTheme,+bold: Bool,+row: List<&2,String>,+widths: List<&2,Nat>,+prefix: String) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    +cells : List<&2,List<&2,String>> <- IO.pure(List<&2,List<&2,String>>,wrappedCells(row,widths,prefix))
    rowLines(height(cells),theme,bold,cells,widths,0n,Nil{})
def bodyLines(+theme: MarkdownTheme,+rows: List<&2,List<&2,String>>,+widths: List<&2,Nat>,+prefix: String,+separator: String,+reversed: List<&2,String>) -> IO(List<&2,String>):
  match rows:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case row <> +rest:
      do IO<List<&2,String>>:
        +lines : List<&2,String> <- tableRow(theme,False{},row,widths,prefix)
        bodyLines(theme,rest,widths,prefix,separator,Bool.pick(List<&2,String>,List.is_empty(&2,List<&2,String>,rest),List.append(&2,String,List.reverse(&2,String,lines),reversed),separator <> List.append(&2,String,List.reverse(&2,String,lines),reversed)))
def spacedAfter(+lines: List<&2,String>,+next: Maybe<&2,String>) -> List<&2,String>:
  match next:
    case Some{+kind}: Bool.pick(List<&2,String>,String.eq(kind,"space"),lines,List.append(&2,String,lines,[""]))
    case None{}: lines
def cellTexts(+env: Env,+cells: List<&2,T.Token<Latex>>,+context: Maybe<&2,Context>,+reversed: List<&2,String>) -> IO(List<&2,String>):
  match cells:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case T.TableCell{_,inner,_,_} <> rest:
      do IO<List<&2,String>>:
        +text : String <- inlineText(env,inner,context)
        cellTexts(env,rest,context,text <> reversed)
    case _ <> rest: cellTexts(env,rest,context,reversed)
def rowTexts(+env: Env,+rows: List<&2,List<&2,T.Token<Latex>>>,+context: Maybe<&2,Context>,+reversed: List<&2,List<&2,String>>) -> IO(List<&2,List<&2,String>>):
  match rows:
    case Nil{}: IO.pure(List<&2,List<&2,String>>,List.reverse(&2,List<&2,String>,reversed))
    case row <> rest:
      do IO<List<&2,List<&2,String>>>:
        +texts : List<&2,String> <- cellTexts(env,row,context,Nil{})
        rowTexts(env,rest,context,texts <> reversed)
def prefixOf(+context: Maybe<&2,Context>) -> String:
  match context:
    case Some{Context{_,prefix}}: prefix
    case None{}: ""
def tableLaidOut(+env: Env,+header: List<&2,String>,+rows: List<&2,List<&2,String>>,+width: Nat,+prefix: String,+next: Maybe<&2,String>) -> IO(List<&2,String>):
  +count = List.length(&2,String,header)
  +overhead = 3n * count + 1n
  +natural = rowsNatural(rows,widthsOf(header))
  +widths = columnWidths(natural,minimumWidths(rowsWords(rows,wordWidths(header)),count,width - overhead),width - overhead,overhead,width)
  +separator = rule(widths,"├─","─┼─","─┤")
  do IO<List<&2,String>>:
    +heading : List<&2,String> <- tableRow(envTheme(env),True{},header,widths,prefix)
    +body : List<&2,String> <- bodyLines(envTheme(env),rows,widths,prefix,separator,Nil{})
    return spacedAfter(rule(widths,"┌─","─┬─","─┐") <> List.append(&2,String,heading,separator <> List.append(&2,String,body,[rule(widths,"└─","─┴─","─┘")])),next)
# renderTable: columns get their natural width when it fits, else shrink
# towards their longest words; a table narrower than one column per cell
# shows its source.
def renderTable(+env: Env,+raw: String,+header: List<&2,T.Token<Latex>>,+rows: List<&2,List<&2,T.Token<Latex>>>,+width: Nat,+next: Maybe<&2,String>,+context: Maybe<&2,Context>) -> IO(List<&2,String>):
  +count = List.length(&2,T.Token<Latex>,header)
  Bool.pick(Unit -> IO(List<&2,String>),Nat.is_eq(count,0n),_ => IO.pure(List<&2,String>,Nil{}),
    _ => Bool.pick(Unit -> IO(List<&2,String>),Nat.is_lt(width,4n * count + 1n),_ => IO.pure(List<&2,String>,spacedAfter(Bool.pick(List<&2,String>,String.is_empty(raw),Nil{},U.wrapTextWithAnsi(raw,width)),next)),
      _ => do IO<List<&2,String>>:
        +cells : List<&2,String> <- cellTexts(env,header,context,Nil{})
        +body : List<&2,List<&2,String>> <- rowTexts(env,rows,context,Nil{})
        tableLaidOut(env,cells,body,width,prefixOf(context),next))(Unit{}))(Unit{})

# Blocks
# ------

def nextType(+tokens: List<&2,T.Token<Latex>>) -> Maybe<&2,String>:
  match tokens:
    case token <> _: Some{T.typeOf(Latex,token)}
    case Nil{}: None{}
def spacedUnless(+lines: List<&2,String>,+next: Maybe<&2,String>,+other: String) -> List<&2,String>:
  match next:
    case Some{+kind}: Bool.pick(List<&2,String>,String.eq(kind,"space") || String.eq(kind,other),lines,List.append(&2,String,lines,[""]))
    case None{}: lines
def styledLines(+env: Env,+lines: List<&2,String>,+reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        +shown : String <- applyDefaultStyle(env,line)
        styledLines(env,rest,shown <> reversed)
def hashes(+count: Nat,+text: String) -> String:
  match count:
    case Zero{}: text
    case Succ{more}: hashes(more,SCon{'#',text})
def headingLines(+env: Env,+depth: Nat,+inner: List<&2,T.Token<Latex>>,+next: Maybe<&2,String>) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    +context : Context <- contextOf(env,HeadingText{depth})
    +text : String <- renderInline(env,inner,context,Nil{})
    +prefix : String <- textStyled(env,HeadingText{depth},hashes(depth," "))
    return spacedUnless([Bool.pick(String,Nat.is_ge(depth,3n),prefix ++ text,text)],next,"space")
def indentedLines(+lines: List<&2,String>,+indent: String) -> List<&2,String>:
  match lines:
    case Nil{}: Nil{}
    case line <> rest: (indent ++ line) <> indentedLines(rest,indent)
def codeLines(+env: Env,+lines: List<&2,String>,+indent: String,+reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        +shown : String <- styled(themeCodeBlock(envTheme(env)),line)
        codeLines(env,rest,indent,(indent ++ shown) <> reversed)
def codeBody(+env: Env,+highlight: Maybe<&2,C.Callback<HighlightInput,List<&2,String>>>,+text: String,+lang: Maybe<&2,String>) -> IO(List<&2,String>):
  match highlight:
    case Some{callback}:
      do IO<List<&2,String>>:
        +lines : List<&2,String> <- C.call(HighlightInput,List<&2,String>,callback,HighlightInput{text,lang})
        return indentedLines(lines,codeIndent(envTheme(env)))
    case None{}: codeLines(env,MarkedHelpers.linesOf(text),codeIndent(envTheme(env)),Nil{})
def highlighterOf(+theme: MarkdownTheme) -> Maybe<&2,C.Callback<HighlightInput,List<&2,String>>>:
  match theme: case MarkdownTheme{_,_,_,_,_,_,_,_,_,_,_,_,_,_,found,_}: found
def codeBlockLines(+env: Env,+lang: Maybe<&2,String>,+text: String,+next: Maybe<&2,String>) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    +opening : String <- styled(themeCodeBlockBorder(envTheme(env)),"```" ++ Maybe.default(&2,String,lang,""))
    +body : List<&2,String> <- codeBody(env,highlighterOf(envTheme(env)),text,lang)
    +closing : String <- styled(themeCodeBlockBorder(envTheme(env)),"```")
    return spacedUnless(opening <> List.append(&2,String,body,[closing]),next,"space")
def latexBlockLines(+env: Env,+raw: String,+value: Latex,+next: Maybe<&2,String>) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    +lines : List<&2,String> <- styledLines(env,MarkedHelpers.linesOf(latexText(renderLatexOption(envOptions(env)),value,Text.trim(raw),True{})),Nil{})
    return spacedUnless(lines,next,"space")
# renderToken for the tokens without nested blocks.
def leafLines(+env: Env,+token: T.Token<Latex>,+width: Nat,+next: Maybe<&2,String>,+context: Maybe<&2,Context>) -> IO(List<&2,String>):
  match token:
    case T.Heading{_,depth,_,inner}: headingLines(env,depth,inner,next)
    case T.Paragraph{_,_,inner}:
      do IO<List<&2,String>>:
        +text : String <- inlineText(env,inner,context)
        return spacedUnless([text],next,"list")
    case T.Text{raw,text,inner,escaped}:
      do IO<List<&2,String>>:
        +shown : String <- inlineText(env,[T.Text{raw,text,inner,escaped}],context)
        return [shown]
    case T.Generic{"latexBlock",raw,value}: latexBlockLines(env,raw,value,next)
    case T.Code{_,_,lang,text}: codeBlockLines(env,lang,text,next)
    case T.Table{raw,_,header,rows}: renderTable(env,raw,header,rows,width,next,context)
    case T.Hr{_}:
      do IO<List<&2,String>>:
        +line : String <- styled(themeHr(envTheme(env)),String.repeat("─",Nat.min(width,80n)))
        return spacedUnless([line],next,"space")
    case T.HTML{raw,_,_,_}:
      do IO<List<&2,String>>:
        +line : String <- applyDefaultStyle(env,Text.trim(raw))
        return [line]
    case T.Tag{raw,_,_,_,_}:
      do IO<List<&2,String>>:
        +line : String <- applyDefaultStyle(env,Text.trim(raw))
        return [line]
    case T.Space{_}: IO.pure(List<&2,String>,[""])
    case T.Codespan{_,text}: IO.pure(List<&2,String>,[text])
    case T.Escape{_,text}: IO.pure(List<&2,String>,[text])
    case T.Del{_,text,_}: IO.pure(List<&2,String>,[text])
    case T.Em{_,text,_}: IO.pure(List<&2,String>,[text])
    case T.Strong{_,text,_}: IO.pure(List<&2,String>,[text])
    case T.Link{_,_,_,text,_}: IO.pure(List<&2,String>,[text])
    case T.Image{_,_,_,text,_}: IO.pure(List<&2,String>,[text])
    case T.Generic{_,_,Latex{text,_}}: IO.pure(List<&2,String>,[text])
    case T.Blockquote{_,text,_}: IO.pure(List<&2,String>,[text])
    case T.ListItem{_,_,_,_,text,_}: IO.pure(List<&2,String>,[text])
    case T.TableCell{text,_,_,_}: IO.pure(List<&2,String>,[text])
    case _: IO.pure(List<&2,String>,Nil{})

# A blockquote's lines: quote-styled (restoring the style after full resets),
# wrapped, behind the border.
def withoutTrailingBlank(+reversed: List<&2,String>) -> List<&2,String>:
  match reversed:
    case "" <> rest: withoutTrailingBlank(rest)
    case lines: lines
def quoteStyled(+env: Env,+prefix: String,+line: String) -> IO(String):
  textStyled(env,QuoteText{},Bool.pick(Unit -> String,String.is_empty(prefix),_ => line,_ => Strings.replaceAll(line,"\u{1b}[0m","\u{1b}[0m" ++ prefix))(Unit{}))
def bordered(+border: String,+lines: List<&2,String>,+reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: reversed
    case line <> rest: bordered(border,rest,(border ++ line) <> reversed)
def quoteLines(+env: Env,+prefix: String,+width: Nat,+lines: List<&2,String>,+border: String,+reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case line <> rest:
      do IO<List<&2,String>>:
        +shown : String <- quoteStyled(env,prefix,line)
        quoteLines(env,prefix,width,rest,border,bordered(border,U.wrapTextWithAnsi(shown,width),reversed))
def blockquoteFinished(+env: Env,+prefix: String,+width: Nat,+children: List<&2,String>,+next: Maybe<&2,String>) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    +border : String <- styled(themeQuoteBorder(envTheme(env)),"│ ")
    +lines : List<&2,String> <- quoteLines(env,prefix,width,List.reverse(&2,String,withoutTrailingBlank(List.reverse(&2,String,children))),border,Nil{})
    return spacedUnless(lines,next,"space")

# List items: `rendered` says whether a line of the item exists yet (the
# first takes the bullet, the rest its width in spaces).
type ItemLines is Data: ItemLines{rendered: Bool,lines: List<&2,String>}
def prefixedLines(+lines: List<&2,String>,+first: String,+continuation: String,+rendered: Bool,+reversed: List<&2,String>) -> ItemLines:
  match lines:
    case Nil{}: ItemLines{rendered,reversed}
    case line <> rest: prefixedLines(rest,first,continuation,True{},(Bool.pick(String,rendered,continuation,first) ++ line) <> reversed)
def wrappedItem(+lines: List<&2,String>,+width: Nat,+first: String,+continuation: String,+done: ItemLines) -> ItemLines:
  match lines done:
    case Nil{} done: done
    case line <> rest ItemLines{rendered,reversed}: wrappedItem(rest,width,first,continuation,prefixedLines(U.wrapTextWithAnsi(line,width),first,continuation,rendered,reversed))
def nestedItem(+done: ItemLines,+lines: List<&2,String>) -> ItemLines:
  match done: case ItemLines{_,reversed}: ItemLines{True{},List.append(&2,String,List.reverse(&2,String,lines),reversed)}
def itemFinished(+done: ItemLines,+first: String) -> List<&2,String>:
  match done:
    case ItemLines{False{},_}: [first]
    case ItemLines{True{},reversed}: List.reverse(&2,String,reversed)
def dropDigits(+text: String) -> String:
  match text:
    case SCon{+char,+rest}: Bool.pick(Unit -> String,Char.is_digit(char),_ => dropDigits(rest),_ => SCon{char,rest})(Unit{})
    case SNil{}: SNil{}
def startsWithSpaceOrTab(+text: String) -> Bool:
  match text:
    case SCon{+char,_}: MarkedHelpers.isSpaceOrTab(char)
    case SNil{}: False{}
# `^(?: {0,3})(\d{1,9}[.)])[ \t]+` and `^(?: {0,3})([-+*])(?:[ \t]+|(?=\r?\n|$))`
# on the item's source: its own marker.
def orderedMarker(+raw: String) -> Maybe<&2,String>:
  +rest = MarkedHelpers.dropWhileChar(raw,' ')
  +digits = String.length(rest) - String.length(dropDigits(rest))
  +after = dropDigits(rest)
  Bool.pick(Unit -> Maybe<&2,String>,Nat.is_le(String.length(raw) - String.length(rest),3n) && Nat.is_ge(digits,1n) && Nat.is_le(digits,9n) && (MarkedHelpers.startsWithChar(after,'.') || MarkedHelpers.startsWithChar(after,')')) && startsWithSpaceOrTab(String.drop(after,1n)),
    _ => Some{String.take(rest,digits + 1n) ++ " "},_ => None{})(Unit{})
def unorderedMarker(+raw: String) -> Maybe<&2,String>:
  +rest = MarkedHelpers.dropWhileChar(raw,' ')
  +after = String.drop(rest,1n)
  Bool.pick(Unit -> Maybe<&2,String>,Nat.is_le(String.length(raw) - String.length(rest),3n) && (MarkedHelpers.startsWithChar(rest,'-') || MarkedHelpers.startsWithChar(rest,'+') || MarkedHelpers.startsWithChar(rest,'*')) && (startsWithSpaceOrTab(after) || String.is_empty(after) || String.starts_with(after,"\n") || String.starts_with(after,"\r\n")),
    _ => Some{String.take(rest,1n) ++ " "},_ => None{})(Unit{})
def bulletOf(+options: MarkdownOptions,+ordered: Bool,+number: Nat,+raw: String) -> String:
  +counted = Nat.show(number) ++ ". "
  Bool.pick(Unit -> String,ordered,
    _ => Bool.pick(Unit -> String,preserveOrderedListMarkers(options),_ => Maybe.default(&2,String,orderedMarker(raw),counted),_ => counted)(Unit{}),
    _ => Bool.pick(Unit -> String,preserveOrderedListMarkers(options),_ => Maybe.default(&2,String,unorderedMarker(raw),"- "),_ => "- ")(Unit{}))(Unit{})
def taskMarker(+task: Bool,+checked: Maybe<&2,Bool>) -> String:
  match task checked:
    case False{} _: ""
    case True{} Some{True{}}: "[x] "
    case True{} _: "[ ] "
def indentOf(+depth: Nat) -> String: String.repeat("    ",depth)

# renderToken, over sequences of tokens and list items: blockquotes and
# lists render their blocks through the same function.
type Job is Data:
  # Tokens in order, each followed by the next one's type; `lines` newest
  # first.
  Blocks{tokens: List<&2,T.Token<Latex>>,width: Nat,context: Maybe<&2,Context>,lines: List<&2,String>}
  One{token: T.Token<Latex>,width: Nat,next: Maybe<&2,String>,context: Maybe<&2,Context>}
  # renderList: the remaining items, the next number and the depth.
  Items{items: List<&2,T.Token<Latex>>,ordered: Bool,number: Nat,loose: Bool,depth: Nat,width: Nat,context: Maybe<&2,Context>,lines: List<&2,String>}
  # One item's tokens after its first prefix and continuation prefix.
  Item{tokens: List<&2,T.Token<Latex>>,first: String,continuation: String,itemWidth: Nat,depth: Nat,width: Nat,context: Maybe<&2,Context>,done: ItemLines}
def prependLines(+lines: List<&2,String>,+reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: reversed
    case line <> rest: prependLines(rest,line <> reversed)
@unsafe def renderBlocks(+env: Env,+job: Job) -> IO(List<&2,String>):
  match job:
    case Blocks{Nil{},_,_,lines}: IO.pure(List<&2,String>,List.reverse(&2,String,lines))
    case Blocks{token <> +rest,+width,+context,lines}:
      do IO<List<&2,String>>:
        +rendered : List<&2,String> <- renderBlocks(env,One{token,width,nextType(rest),context})
        renderBlocks(env,Blocks{rest,width,context,prependLines(rendered,lines)})
    case One{T.Blockquote{_,_,inner},+width,next,_}:
      do IO<List<&2,String>>:
        +quote : Context <- contextOf(env,QuoteText{})
        +children : List<&2,String> <- renderBlocks(env,Blocks{inner,Nat.max(1n,width - 2n),Some{Context{PlainText{},contextPrefix(quote)}},Nil{}})
        blockquoteFinished(env,contextPrefix(quote),Nat.max(1n,width - 2n),children,next)
    case One{T.ListToken{_,ordered,start,loose,items},width,_,context}: renderBlocks(env,Items{items,ordered,Maybe.default(&2,Nat,start,1n),loose,0n,width,context,Nil{}})
    case One{token,width,next,context}: leafLines(env,token,width,next,context)
    case Items{Nil{},_,_,_,_,_,_,lines}: IO.pure(List<&2,String>,List.reverse(&2,String,lines))
    case Items{T.ListItem{+raw,task,checked,_,_,inner} <> +rest,+ordered,+number,+loose,+depth,+width,+context,lines}:
      +marker = bulletOf(envOptions(env),ordered,number,raw) ++ taskMarker(task,checked)
      do IO<List<&2,String>>:
        +bullet : String <- styled(themeListBullet(envTheme(env)),marker)
        +first : String <- IO.pure(String,indentOf(depth) ++ bullet)
        +item : List<&2,String> <- renderBlocks(env,Item{inner,first,indentOf(depth) ++ U.spaces(U.visibleWidth(marker),""),Nat.max(1n,width - U.visibleWidth(first)),depth,width,context,ItemLines{False{},Nil{}}})
        renderBlocks(env,Items{rest,ordered,number + 1n,loose,depth,width,context,Bool.pick(List<&2,String>,loose && Bool.not(List.is_empty(&2,T.Token<Latex>,rest)),"" <> prependLines(item,lines),prependLines(item,lines))})
    case Items{_ <> rest,ordered,number,loose,depth,width,context,lines}: renderBlocks(env,Items{rest,ordered,number + 1n,loose,depth,width,context,lines})
    case Item{Nil{},+first,_,_,_,_,_,done}: IO.pure(List<&2,String>,itemFinished(done,first))
    case Item{T.ListToken{_,ordered,start,loose,items} <> rest,first,continuation,itemWidth,+depth,+width,+context,done}:
      do IO<List<&2,String>>:
        +nested : List<&2,String> <- renderBlocks(env,Items{items,ordered,Maybe.default(&2,Nat,start,1n),loose,depth + 1n,width,context,Nil{}})
        renderBlocks(env,Item{rest,first,continuation,itemWidth,depth,width,context,nestedItem(done,nested)})
    case Item{token <> rest,+first,+continuation,+itemWidth,depth,width,+context,done}:
      do IO<List<&2,String>>:
        +lines : List<&2,String> <- renderBlocks(env,One{token,itemWidth,None{},context})
        renderBlocks(env,Item{rest,first,continuation,itemWidth,depth,width,context,wrappedItem(lines,itemWidth,first,continuation,done)})

# render(width)
# -------------

def transformed(+source: String,+width: Nat,+options: MarkdownOptions) -> IO(String):
  match options:
    case MarkdownOptions{_,_,None{},_,_}: IO.pure(String,source)
    case MarkdownOptions{_,_,Some{transform},_,_}: C.call(String & Nat,String,transform,(source,width))
def background(+style: Maybe<&2,DefaultTextStyle>) -> Maybe<&2,Style()>:
  match style:
    case None{}: None{}
    case Some{DefaultTextStyle{_,bgFn,_,_,_,_}}: bgFn
def painted(+line: String,+width: Nat,+bg: Maybe<&2,Style()>) -> IO(String):
  match bg:
    case None{}: IO.pure(String,U.padResult(line,U.visibleWidth(line),width,True{}))
    case Some{callback}: U.applyBackgroundToLine(line,width,callback)
# Margins and background (or padding to the width); image lines stay as
# they are.
def paint(+lines: List<&2,String>,+margin: String,+width: Nat,+bg: Maybe<&2,Style()>,+reversed: List<&2,String>) -> IO(List<&2,String>):
  match lines:
    case Nil{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case +line <> rest:
      Bool.pick(Unit -> IO(List<&2,String>),Image.isImageLine(line),_ => paint(rest,margin,width,bg,line <> reversed),
        _ => do IO<List<&2,String>>:
          +result : String <- painted(margin ++ line ++ margin,width,bg)
          paint(rest,margin,width,bg,result <> reversed))(Unit{})
def padding(+count: Nat,+width: Nat,+bg: Maybe<&2,Style()>,+reversed: List<&2,String>) -> IO(List<&2,String>):
  match count:
    case Zero{}: IO.pure(List<&2,String>,List.reverse(&2,String,reversed))
    case Succ{count}:
      do IO<List<&2,String>>:
        +line : String <- painted(U.spaces(width,""),width,bg)
        padding(count,width,bg,line <> reversed)
def wrap(+lines: List<&2,String>,+width: Nat,+reversed: List<&2,String>) -> List<&2,String>:
  match lines:
    case Nil{}: List.reverse(&2,String,reversed)
    case +line <> rest: wrap(rest,width,Bool.pick(Unit -> List<&2,String>,Image.isImageLine(line),_ => line <> reversed,_ => prependLines(U.wrapTextWithAnsi(line,width),reversed))(Unit{}))
def cached(+state: Markdown,+width: Nat,+lines: List<&2,String>) -> Markdown & List<&2,String>:
  match state:
    case Markdown{text,x,y,theme,style,options,_}: (Markdown{text,x,y,theme,style,options,Some{Cache{width,lines}}},lines)
# The lines are cached as rendered; an empty result reads as one empty line.
def atLeastOneLine(pair: Markdown & List<&2,String>) -> Markdown & List<&2,String>:
  match pair:
    case (state,Nil{}): (state,[""])
    case pair: pair
def finish(+state: Markdown,+width: Nat,+lines: List<&2,String>) -> IO(Markdown & List<&2,String>):
  match state:
    case Markdown{_,x,y,_,style,_,_}:
      do IO<Markdown & List<&2,String>>:
        +bg : Maybe<&2,Style()> <- IO.pure(Maybe<&2,Style()>,background(style))
        +margin : String <- IO.pure(String,U.spaces(x,""))
        +body : List<&2,String> <- paint(wrap(lines,Nat.max(1n,width - x * 2n),Nil{}),margin,width,bg,Nil{})
        +top : List<&2,String> <- padding(y,width,bg,Nil{})
        +bottom : List<&2,String> <- padding(y,width,bg,Nil{})
        return atLeastOneLine(cached(state,width,List.append(&2,String,top,List.append(&2,String,body,bottom))))

# The Marked instance pi's Markdown component lexes with.
def tokensOf(+value: Marked.TokensList<Latex>) -> List<&2,T.Token<Latex>>:
  match value: case Marked.TokensList{tokens,_}: tokens
def lexed(+marked: Marked.Marked,+text: String) -> List<&2,T.Token<Latex>>: tokensOf(Marked.lex(~Latex,~piExtensions(),marked,text))
def uncached(+state: Markdown,+width: Nat) -> IO(Markdown & List<&2,String>):
  match state:
    case Markdown{+source,x,_,theme,style,options,_}:
      do IO<Markdown & List<&2,String>>:
        +contentWidth : Nat <- IO.pure(Nat,Nat.max(1n,width - x * 2n))
        +text : String <- transformed(source,contentWidth,options)
        Bool.pick(Unit -> IO(Markdown & List<&2,String>),Text.blank(text),
          _ => IO.pure(Markdown & List<&2,String>,cached(state,width,Nil{})),
          _ => do IO<Markdown & List<&2,String>>:
            +lines : List<&2,String> <- renderBlocks(Env{theme,style,options},Blocks{trimPartialClosingFences(lexed(Marked.new(),Strings.replaceAll(text,"\t","   "))),contentWidth,None{},Nil{}})
            finish(state,width,lines))(Unit{})
def render(+state: Markdown,+width: Nat) -> IO(Markdown & List<&2,String>):
  match state:
    case Markdown{_,_,_,_,_,_,Some{Cache{oldWidth,lines}}}:
      Bool.pick(Unit -> IO(Markdown & List<&2,String>),Nat.is_eq(oldWidth,width),_ => IO.pure(Markdown & List<&2,String>,(state,lines)),_ => uncached(state,width))(Unit{})
    case _: uncached(state,width)
