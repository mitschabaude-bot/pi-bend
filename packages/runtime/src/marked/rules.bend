import Base
import ../ecma-regex.bend as Re

# marked 18.0.11's grammar (src/rules.ts) for its default options (gfm,
# not pedantic) and with `breaks`: the block and inline rules built from their
# upstream sources with `edit`, then compiled once per lexer. The fixed
# `other` expressions of rules.ts are simple enough to be plain functions in
# helpers.bend; the rules of pedantic mode and non-GFM Markdown are not ported.
# tests/marked_rules_check.py compares every source with marked's.

# edit
# ----
# `edit(regex).replace(name, value)`: a string name replaces its first
# occurrence, `replaceAll` stands for a /name/g expression; the value loses
# its `^` anchors (other.caret, `/(^|[^\[])\^/g` → "$1") first.

type Edit is Data: Edit{source: String,flags: String}

def edit(source: String,flags: String) -> Edit: Edit{source,flags}
# A caret goes when it opens the text or follows a character other than '['
# that an earlier match did not consume.
def caretFree(text: String,pairs: Bool,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      Bool.pick(Unit -> String,pairs && Char.is_eq(char,'^'),_ => caretFree(rest,False{},reversed),
        _ => caretFree(rest,Bool.not(Char.is_eq(char,'[')),SCon{char,reversed}))(Unit{})
# Whether `name` starts `text`, comparing its first character first.
def startsName(+text: String,+name: String) -> Bool:
  match text name:
    case SCon{+char,_} SCon{+first,_}: Bool.pick(Unit -> Bool,Char.is_eq(char,first),_ => String.starts_with(text,name),_ => False{})(Unit{})
    case _ _: False{}
def firstReplaced(text: String,+name: String,+value: String,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      Bool.pick(Unit -> String,startsName(SCon{char,rest},name),
        _ => String.reverse(reversed) ++ value ++ String.drop(SCon{char,rest},String.length(name)),
        _ => firstReplaced(rest,name,value,SCon{char,reversed}))(Unit{})
# /name/g: every occurrence, left to right; `skip` counts the rest of a
# replaced occurrence.
def everyReplaced(text: String,+name: String,+value: String,+skip: Nat,+reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{+char,+rest}:
      Bool.pick(Unit -> String,Nat.is_gt(skip,0n),_ => everyReplaced(rest,name,value,skip - 1n,reversed),
        _ => Bool.pick(Unit -> String,startsName(SCon{char,rest},name),_ => everyReplaced(rest,name,value,String.length(name) - 1n,String.reverse(value) ++ reversed),
          _ => everyReplaced(rest,name,value,0n,SCon{char,reversed}))(Unit{}))(Unit{})
def replace(value: Edit,name: String,replacement: String) -> Edit:
  match value: case Edit{source,flags}: Edit{firstReplaced(source,name,caretFree(replacement,True{},""),""),flags}
def replaceAll(value: Edit,name: String,replacement: String) -> Edit:
  match value: case Edit{source,flags}: Edit{everyReplaced(source,name,caretFree(replacement,True{},""),0n,""),flags}
def sourceOf(value: Edit) -> String:
  match value: case Edit{source,_}: source
def flagsOf(value: Edit) -> String:
  match value: case Edit{_,flags}: flags

# Sources
# -------

def newlineRule() -> String: "^(?:[ \\t]*(?:\\n|$))+"
def blockCodeRule() -> String: "^((?: {4}| {0,3}\\t)[^\\n]+(?:\\n(?:[ \\t]*(?:\\n|$))*)?)+"
def fencesRule() -> String: "^ {0,3}(`{3,}(?=[^`\\n]*(?:\\n|$))|~{3,})([^\\n]*)(?:\\n|$)(?:|([\\s\\S]*?)(?:\\n|$))(?: {0,3}\\1[~`]* *(?=\\n|$)|$)"
def hrRule() -> String: "^ {0,3}((?:-[\\t ]*){3,}|(?:_[ \\t]*){3,}|(?:\\*[ \\t]*){3,})(?:\\n+|$)"
def headingRule() -> String: "^ {0,3}(#{1,6})(?=\\s|$)(.*)(?:\\n+|$)"
def bullet() -> String: " {0,3}(?:[*+-]|\\d{1,9}[.)])"
def lheadingCore() -> String: "^(?!bull |blockCode|fences|blockquote|heading|html|table)((?:.|\\n(?!\\s*?\\n|bull |blockCode|fences|blockquote|heading|html|table))+?)\\n {0,3}(=+|-+) *(?:\\n+|$)"
def lhBlockCode() -> String: "(?: {4}| {0,3}\\t)"
def lhFences() -> String: " {0,3}(?:`{3,}|~{3,})"
def lhBlockquote() -> String: " {0,3}>"
def lhHeading() -> String: " {0,3}#{1,6}(?:\\s|$)"
def lhHtml() -> String: " {0,3}<[^\\n>]+>\\n"
def lhTable() -> String: " {0,3}\\|?(?:[:\\- ]*\\|)+[\\:\\- ]*\\n"
def paragraphCore() -> String: "^([^\\n]+(?:\\n(?!hr|heading|lheading|blockquote|fences|list|html|table|[ \\t]+\\n)[^\\n]+)*)"
def blockTextRule() -> String: "^[^\\n]+"
def blockLabel() -> String: "(?!\\s*\\])(?:\\\\[\\s\\S]|[^\\[\\]\\\\])+"
def defCore() -> String: "^ {0,3}\\[(label)\\]: *(?:\\n[ \\t]*)?([^<\\s][^\\s]*|<.*?>)(?:(?: +(?:\\n[ \\t]*)?| *\\n[ \\t]*)(title))? *(?:\\n+|$)"
def defTitle() -> String: "(?:\"(?:\\\\\"?|[^\"\\\\])*\"|'[^'\\n]*(?:\\n[^'\\n]+)*\\n?'|\\([^()]*\\))"
def listCore() -> String: "^(bull)([ \\t][^\\n]*?)?(?:\\n|$)"
def tagNames() -> String: "address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|meta|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul"
def comment() -> String: "<!--(?:-?>|[\\s\\S]*?(?:-->|$))"
def htmlCore() -> String: "^ {0,3}(?:<(script|pre|style|textarea)[\\s>][\\s\\S]*?(?:</\\1>[^\\n]*\\n*|$)|comment[^\\n]*(\\n+|$)|<\\?[\\s\\S]*?(?:\\?>[^\\n]*\\n*|$)|<![A-Z][\\s\\S]*?(?:>[^\\n]*\\n*|$)|<!\\[CDATA\\[[\\s\\S]*?(?:\\]\\]>[^\\n]*\\n*|$)|</?(tag)(?: +|\\n|/?>)[\\s\\S]*?(?:(?:\\n[ \t]*)+\\n|$)|<(?!script|pre|style|textarea)([a-z][\\w-]*)(?:attribute)*? */?>(?=[ \\t]*(?:\\n|$))[\\s\\S]*?(?:(?:\\n[ \t]*)+\\n|$)|</(?!script|pre|style|textarea)[a-z][\\w-]*\\s*>(?=[ \\t]*(?:\\n|$))[\\s\\S]*?(?:(?:\\n[ \t]*)+\\n|$))"
def htmlAttribute() -> String: " +[a-zA-Z:_][\\w.:-]*(?: *= *\"[^\"\\n]*\"| *= *'[^'\\n]*'| *= *[^\\s\"'=<>`]+)?"
def pHeading() -> String: " {0,3}#{1,6}(?:\\s|$)"
def pBlockquote() -> String: " {0,3}>"
def pFences() -> String: " {0,3}(?:`{3,}(?=[^`\\n]*(?:\\n|$))|~~~)[^\\n]*(?:\\n|$)"
def pHtml() -> String: "</?(?:tag)(?: +|\\n|/?>)|<(?:script|pre|style|textarea|!--)"
def listInterrupt() -> String: " {0,3}(?:[*+-]|1[.)])[ \\t]+[^ \\t\\n]"
def bqListInterrupt() -> String: " {0,3}(?:[*+-]|\\d{1,9}[.)])(?:[ \\t]|\\n|$)"
def bqCore() -> String: "^( {0,3}> ?(paragraph|[^\\n]*)(?:\\n|$))+"
def gfmTableCore() -> String: "^ *([^\\n ].*)\\n {0,3}((?:\\| *)?:?-+:? *(?:\\| *:?-+:? *)*(?:\\| *)?)(?:\\n((?:(?! *\\n|hr|heading|blockquote|code|fences|list|html).*(?:\\n|$))*)\\n*|$)"
def tCode() -> String: "(?: {4}| {0,3}\t)[^\\n]"
def tList() -> String: " {0,3}(?:[*+-]|1[.)])[ \\t]"
def gfmPList() -> String: " {0,3}(?:[*+-]|1[.)])[ \\t]+[^ \\t\\n]"
def escapeRule() -> String: "^\\\\([!\"#$%&'()*+,\\-./:;<=>?@\\[\\]\\\\^_`{|}~])"
def inlineCodeRule() -> String: "^(`+)([^`]|[^`][\\s\\S]*?[^`])\\1(?!`)"
def brRule() -> String: "^( {2,}|\\\\)\\n(?!\\s*$)"
def punct() -> String: "[\\p{P}\\p{S}]"
def punctSpace() -> String: "[\\s\\p{P}\\p{S}]"
def notPunctSpace() -> String: "[^\\s\\p{P}\\p{S}]"
def punctuationCore() -> String: "^((?![*_])punctSpace)"
def punctGfm() -> String: "(?!~)[\\p{P}\\p{S}]"
def punctSpaceGfm() -> String: "(?!~)[\\s\\p{P}\\p{S}]"
def notPunctSpaceGfm() -> String: "(?:[^\\s\\p{P}\\p{S}]|~)"
def blockSkipCore() -> String: "link|precode-code|html"
def bsLink() -> String: "\\[(?:[^\\[\\]`]|(?<a>`+)[^`]+\\k<a>(?!`))*?\\]\\((?:\\\\[\\s\\S]|[^\\\\\\(\\)]|\\((?:\\\\[\\s\\S]|[^\\\\\\(\\)])*\\))*\\)"
def bsPrecode() -> String: "(?<!`)()"
def bsCode() -> String: "(?<b>`+)[^`]+\\k<b>(?!`)"
def bsHtml() -> String: "<(?! )[^<>]*?>"
def emStrongLDelimCore() -> String: "^(?:\\*+(?:((?!\\*)punct)|([^\\s*]))?)|^_+(?:((?!_)punct)|([^\\s_]))?"
def emStrongRDelimAstCore() -> String: "^[^_*]*?__[^_*]*?\\*[^_*]*?(?=__)|[^*]+(?=[^*])|(?!\\*)punct(\\*+)(?=[\\s]|$)|notPunctSpace(\\*+)(?!\\*)(?=punctSpace|$)|(?!\\*)punctSpace(\\*+)(?=notPunctSpace)|[\\s](\\*+)(?!\\*)(?=punct)|(?!\\*)punct(\\*+)(?!\\*)(?=punct)|notPunctSpace(\\*+)(?=notPunctSpace)"
def emStrongRDelimUndCore() -> String: "^[^_*]*?\\*\\*[^_*]*?_[^_*]*?(?=\\*\\*)|[^_]+(?=[^_])|(?!_)punct(_+)(?=[\\s]|$)|notPunctSpace(_+)(?!_)(?=punctSpace|$)|(?!_)punctSpace(_+)(?=notPunctSpace)|[\\s](_+)(?!_)(?=punct)|(?!_)punct(_+)(?!_)(?=punct)"
def delLDelimCore() -> String: "^~~?(?:((?!~)punct)|[^\\s~])"
def delRDelimCore() -> String: "^[^~]+(?=[^~])|(?!~)punct(~~?)(?=[\\s]|$)|notPunctSpace(~~?)(?!~)(?=punctSpace|$)|(?!~)punctSpace(~~?)(?=notPunctSpace)|[\\s](~~?)(?!~)(?=punct)|(?!~)punct(~~?)(?!~)(?=punct)|notPunctSpace(~~?)(?=notPunctSpace)"
def anyPunctuationCore() -> String: "\\\\(punct)"
def autolinkCore() -> String: "^<(scheme:[^\\s\\x00-\\x1f<>]*|email)>"
def alScheme() -> String: "[a-zA-Z][a-zA-Z0-9+.-]{1,31}"
def alEmail() -> String: "[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+(@)[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+(?![-_])"
def tagCore() -> String: "^comment|^</[a-zA-Z][\\w:-]*\\s*>|^<[a-zA-Z][\\w-]*(?:attribute)*?\\s*/?>|^<\\?[\\s\\S]*?\\?>|^<![a-zA-Z]+\\s[\\s\\S]*?>|^<!\\[CDATA\\[[\\s\\S]*?\\]\\]>"
def tagAttribute() -> String: "\\s+[a-zA-Z:_][\\w.:-]*(?:\\s*=\\s*\"[^\"]*\"|\\s*=\\s*'[^']*'|\\s*=\\s*[^\\s\"'=<>`]+)?"
def inlineLabel() -> String: "(?:\\[(?:\\\\[\\s\\S]|[^\\[\\]\\\\])*\\]|\\\\[\\s\\S]|`+(?!`)[^`]*?`+(?!`)|``+(?=\\])|[^\\[\\]\\\\`])*?"
def linkCore() -> String: "^!?\\[(label)\\]\\(\\s*(href)(?:(?:[ \\t]+(?:\\n[ \\t]*)?|\\n[ \\t]*)(title))?\\s*\\)"
def linkHref() -> String: "<(?:\\\\.|[^\\n<>\\\\])+>|[^ \\t\\n\\x00-\\x1f]+|(?=\\))"
def linkTitle() -> String: "\"(?:\\\\\"?|[^\"\\\\])*\"|'(?:\\\\'?|[^'\\\\])*'|\\((?:\\\\\\)?|[^)\\\\])*\\)"
def reflinkCore() -> String: "^!?\\[(label)\\]\\[(ref)\\]"
def nolinkCore() -> String: "^!?\\[(ref)\\](?:\\[\\])?"
def reflinkSearchCore() -> String: "reflink|nolink(?!\\()"
def protocol() -> String: "[hH][tT][tT][pP][sS]?|[fF][tT][pP]"
def urlCore() -> String: "^((?:protocol):\\/\\/|www\\.)(?:[a-zA-Z0-9\\-]+\\.?)+[^\\s<]*|^email"
def urlEmail() -> String: "[A-Za-z0-9._+-]+(@)[a-zA-Z0-9-_]+(?:\\.[a-zA-Z0-9-_]*[a-zA-Z0-9])+(?![-_])"
def backpedal() -> String: "(?:[^?!.,:;*_'\"~()&]+|\\([^)]*\\)|&(?![a-zA-Z0-9]+;$)|[?!.,:;*_'\"~)]+(?!$))+"
def gfmTextCore() -> String: "^(`+|~+|[^`~])(?:(?=[`~])|(?= {2,}\\n)|(?=[a-zA-Z0-9.!#$%&'*+\\/=?_`{\\|}~-]+@)|[\\s\\S]*?(?:(?=[\\\\<!\\[`*~_]|\\b_|protocol:\\/\\/|www\\.|$)|[^ ](?= {2,}\\n)|[^a-zA-Z0-9.!#$%&'*+\\/=?_`{\\|}~-](?=[a-zA-Z0-9.!#$%&'*+\\/=?_`{\\|}~-]+@)))"

# Block grammar
# -------------

def lheadingGfm() -> Edit:
  replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(edit(lheadingCore(),""),"bull",bullet()),"blockCode",lhBlockCode()),"fences",lhFences()),"blockquote",lhBlockquote()),"heading",lhHeading()),"html",lhHtml()),"table",lhTable())
def definition() -> Edit: replace(replace(edit(defCore(),""),"label",blockLabel()),"title",defTitle())
def listRule() -> Edit: replaceAll(edit(listCore(),""),"bull",bullet())
def html() -> Edit:
  replace(replace(replace(edit(htmlCore(),"i"),"comment",comment()),"tag",tagNames()),"attribute",htmlAttribute())
# createParagraph(listInterrupt)
def createParagraph(interrupt: String) -> Edit:
  replace(replace(replace(replace(replace(replace(replace(replace(replace(edit(paragraphCore(),""),"hr",hrRule()),"heading",pHeading()),"|lheading",""),"|table",""),"blockquote",pBlockquote()),"fences",pFences()),"list",interrupt),"html",pHtml()),"tag",tagNames())
def blockquote() -> Edit: replace(edit(bqCore(),""),"paragraph",sourceOf(createParagraph(bqListInterrupt())))
def gfmTable() -> Edit:
  replace(replace(replace(replace(replace(replace(replace(replace(edit(gfmTableCore(),""),"hr",hrRule()),"heading",pHeading()),"blockquote",pBlockquote()),"code",tCode()),"fences",pFences()),"list",tList()),"html",pHtml()),"tag",tagNames())
def gfmParagraphWith(+table: Edit) -> Edit:
  replace(replace(replace(replace(replace(replace(replace(replace(replace(edit(paragraphCore(),""),"hr",hrRule()),"heading",pHeading()),"|lheading",""),"table",sourceOf(table)),"blockquote",pBlockquote()),"fences",pFences()),"list",gfmPList()),"html",pHtml()),"tag",tagNames())
def gfmParagraph() -> Edit: gfmParagraphWith(gfmTable())

# Inline grammar
# --------------

def punctuation() -> Edit: replaceAll(edit(punctuationCore(),"u"),"punctSpace",punctSpace())
def blockSkip() -> Edit: replace(replace(replace(replace(edit(blockSkipCore(),"g"),"link",bsLink()),"precode-",bsPrecode()),"code",bsCode()),"html",bsHtml())
def emStrongLDelimGfm() -> Edit: replaceAll(edit(emStrongLDelimCore(),"u"),"punct",punctGfm())
def emStrongRDelimAstGfm() -> Edit:
  replaceAll(replaceAll(replaceAll(edit(emStrongRDelimAstCore(),"gu"),"notPunctSpace",notPunctSpaceGfm()),"punctSpace",punctSpaceGfm()),"punct",punctGfm())
def emStrongRDelimUnd() -> Edit:
  replaceAll(replaceAll(replaceAll(edit(emStrongRDelimUndCore(),"gu"),"notPunctSpace",notPunctSpace()),"punctSpace",punctSpace()),"punct",punct())
def delLDelim() -> Edit: replaceAll(edit(delLDelimCore(),"u"),"punct",punct())
def delRDelim() -> Edit:
  replaceAll(replaceAll(replaceAll(edit(delRDelimCore(),"gu"),"notPunctSpace",notPunctSpace()),"punctSpace",punctSpace()),"punct",punct())
def anyPunctuation() -> Edit: replaceAll(edit(anyPunctuationCore(),"gu"),"punct",punct())
def autolink() -> Edit: replace(replace(edit(autolinkCore(),""),"scheme",alScheme()),"email",alEmail())
def inlineComment() -> Edit: replace(edit(comment(),""),"(?:-->|$)","-->")
def tag() -> Edit: replace(replace(edit(tagCore(),""),"comment",sourceOf(inlineComment())),"attribute",tagAttribute())
def link() -> Edit: replace(replace(replace(edit(linkCore(),""),"label",inlineLabel()),"href",linkHref()),"title",linkTitle())
def reflink() -> Edit: replace(replace(edit(reflinkCore(),""),"label",inlineLabel()),"ref",blockLabel())
def nolink() -> Edit: replace(edit(nolinkCore(),""),"ref",blockLabel())
def reflinkSearch() -> Edit: replace(replace(edit(reflinkSearchCore(),"g"),"reflink",sourceOf(reflink())),"nolink",sourceOf(nolink()))
def url() -> Edit: replace(replace(edit(urlCore(),""),"protocol",protocol()),"email",urlEmail())
def gfmText() -> Edit: replace(edit(gfmTextCore(),""),"protocol",protocol())

# GFM with line breaks (`breaks: true`).
def breaksBr() -> Edit: replace(edit(brRule(),""),"{2,}","*")
def breaksText() -> Edit: replaceAll(replace(edit(sourceOf(gfmText()),""),"\\b_","\\b_| {2,}\\n"),"{2,}","*")

# Every rule by marked's name (`block.*`, `inline.*`), as built above.
type Named is Data: Named{name: String,rule: Edit}
def sources() -> List<&2,Named>:
  Named{"block.blockquote",blockquote()} <> Named{"block.code",edit(blockCodeRule(),"")} <> Named{"block.def",definition()} <> Named{"block.fences",edit(fencesRule(),"")} <> Named{"block.heading",edit(headingRule(),"")} <> Named{"block.hr",edit(hrRule(),"")} <> Named{"block.html",html()} <> Named{"block.lheading",lheadingGfm()} <> Named{"block.list",listRule()} <> Named{"block.newline",edit(newlineRule(),"")} <> Named{"block.paragraph",gfmParagraph()} <> Named{"block.table",gfmTable()} <> Named{"block.text",edit(blockTextRule(),"")}
  <> Named{"breaks.br",breaksBr()} <> Named{"breaks.text",breaksText()}
  <> Named{"inline._backpedal",edit(backpedal(),"")} <> Named{"inline.anyPunctuation",anyPunctuation()} <> Named{"inline.autolink",autolink()} <> Named{"inline.blockSkip",blockSkip()} <> Named{"inline.br",edit(brRule(),"")} <> Named{"inline.code",edit(inlineCodeRule(),"")} <> Named{"inline.delLDelim",delLDelim()} <> Named{"inline.delRDelim",delRDelim()} <> Named{"inline.emStrongLDelim",emStrongLDelimGfm()} <> Named{"inline.emStrongRDelimAst",emStrongRDelimAstGfm()} <> Named{"inline.emStrongRDelimUnd",emStrongRDelimUnd()} <> Named{"inline.escape",edit(escapeRule(),"")} <> Named{"inline.link",link()} <> Named{"inline.nolink",nolink()} <> Named{"inline.punctuation",punctuation()} <> Named{"inline.reflink",reflink()} <> Named{"inline.reflinkSearch",reflinkSearch()} <> Named{"inline.tag",tag()} <> Named{"inline.text",gfmText()} <> Named{"inline.url",url()} <> Nil{}

# Compiled rules
# --------------
# Compiled once per lexer (a definition without parameters is evaluated at
# each use), each with its start analysis: a rule is tried only where a
# match can begin.

type Search is Data: Search{regex: Re.RegExp,start: Re.Start}
# Never matches (a failed compilation, which tests/marked_rules_check.py
# rules out).
def never() -> Re.RegExp: Re.RegExp{"(?!)",Re.noFlags(),Re.Look{True{},True{},Re.Empty{}},0n,Nil{}}
def compiledResult(result: Result<&2,&2,Re.Error,Re.RegExp>) -> Re.RegExp:
  match result:
    case Done{regex}: regex
    case Fail{_}: never()
def compiled(rule: Edit) -> Re.RegExp:
  match rule: case Edit{source,flags}: compiledResult(Re.compile(source,flags))
def searched(+regex: Re.RegExp) -> Search: Search{regex,Re.startOf(regex)}
def searchOf(rule: Edit) -> Search: searched(compiled(rule))

type Block is Data: Block{blockquote: Search,code: Search,definition: Search,fences: Search,heading: Search,hr: Search,html: Search,lheading: Search,list: Search,newline: Search,paragraph: Search,table: Search,text: Search}
type Inline is Data: Inline{backpedal: Search,autolink: Search,blockSkip: Search,br: Search,code: Search,delLDelim: Search,delRDelim: Search,emStrongLDelim: Search,emStrongRDelimAst: Search,emStrongRDelimUnd: Search,escape: Search,link: Search,nolink: Search,reflink: Search,reflinkSearch: Search,tag: Search,text: Search,url: Search,breaks: Bool}
type Rules is Data: Rules{block: Block,inline: Inline}
# The rules for marked's default options, with `breaks` or without.
def rulesWith(+breaks: Bool,+table: Edit) -> Rules:
  Rules{Block{searchOf(blockquote()),searchOf(edit(blockCodeRule(),"")),searchOf(definition()),searchOf(edit(fencesRule(),"")),searchOf(edit(headingRule(),"")),searchOf(edit(hrRule(),"")),searchOf(html()),searchOf(lheadingGfm()),searchOf(listRule()),searchOf(edit(newlineRule(),"")),searchOf(gfmParagraphWith(table)),searchOf(table),searchOf(edit(blockTextRule(),""))},
    Inline{searchOf(edit(backpedal(),"")),searchOf(autolink()),searchOf(blockSkip()),searchOf(Bool.pick(Unit -> Edit,breaks,_ => breaksBr(),_ => edit(brRule(),""))(Unit{})),searchOf(edit(inlineCodeRule(),"")),searchOf(delLDelim()),searchOf(delRDelim()),searchOf(emStrongLDelimGfm()),searchOf(emStrongRDelimAstGfm()),searchOf(emStrongRDelimUnd()),searchOf(edit(escapeRule(),"")),searchOf(link()),searchOf(nolink()),searchOf(reflink()),searchOf(reflinkSearch()),searchOf(tag()),searchOf(Bool.pick(Unit -> Edit,breaks,_ => breaksText(),_ => gfmText())(Unit{})),searchOf(url()),breaks}}
def rules(+breaks: Bool) -> Rules: rulesWith(breaks,gfmTable())

# Rules by name
# -------------
# A tokenizer reads a rule where the start analysis allows a match at the
# first scalar of its source (`blockOpens`, `inlineOpens`: the rules are read
# in place), and only then takes its search out of the rules (`blockSearch`,
# `inlineSearch`). Taking a rule copies it out of the record, which updates a
# reference count per compiled rule the record holds (BEND-054).

# Whether a match of `rule` may begin at the start of a source whose first
# scalar is `first` (never false when one can).
def opensWith(rule: Search,first: Maybe<&2,U32>) -> Bool:
  match rule: case Search{Re.RegExp{_,flags,_,_,_},start}: Re.startsAt(start,flags,None{},first)

type BlockRule is Data:
  BlockBlockquote{}
  BlockCode{}
  BlockDefinition{}
  BlockFences{}
  BlockHeading{}
  BlockHr{}
  BlockHtml{}
  BlockLheading{}
  BlockList{}
  BlockNewline{}
  BlockParagraph{}
  BlockTable{}
  BlockText{}
def blockSearch(value: Block,rule: BlockRule) -> Search:
  match rule value:
    case BlockBlockquote{} Block{found,_,_,_,_,_,_,_,_,_,_,_,_}: found
    case BlockCode{} Block{_,found,_,_,_,_,_,_,_,_,_,_,_}: found
    case BlockDefinition{} Block{_,_,found,_,_,_,_,_,_,_,_,_,_}: found
    case BlockFences{} Block{_,_,_,found,_,_,_,_,_,_,_,_,_}: found
    case BlockHeading{} Block{_,_,_,_,found,_,_,_,_,_,_,_,_}: found
    case BlockHr{} Block{_,_,_,_,_,found,_,_,_,_,_,_,_}: found
    case BlockHtml{} Block{_,_,_,_,_,_,found,_,_,_,_,_,_}: found
    case BlockLheading{} Block{_,_,_,_,_,_,_,found,_,_,_,_,_}: found
    case BlockList{} Block{_,_,_,_,_,_,_,_,found,_,_,_,_}: found
    case BlockNewline{} Block{_,_,_,_,_,_,_,_,_,found,_,_,_}: found
    case BlockParagraph{} Block{_,_,_,_,_,_,_,_,_,_,found,_,_}: found
    case BlockTable{} Block{_,_,_,_,_,_,_,_,_,_,_,found,_}: found
    case BlockText{} Block{_,_,_,_,_,_,_,_,_,_,_,_,found}: found
def blockOpens(value: Block,rule: BlockRule,first: Maybe<&2,U32>) -> Bool:
  match rule value:
    case BlockBlockquote{} Block{found,_,_,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case BlockCode{} Block{_,found,_,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case BlockDefinition{} Block{_,_,found,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case BlockFences{} Block{_,_,_,found,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case BlockHeading{} Block{_,_,_,_,found,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case BlockHr{} Block{_,_,_,_,_,found,_,_,_,_,_,_,_}: opensWith(found,first)
    case BlockHtml{} Block{_,_,_,_,_,_,found,_,_,_,_,_,_}: opensWith(found,first)
    case BlockLheading{} Block{_,_,_,_,_,_,_,found,_,_,_,_,_}: opensWith(found,first)
    case BlockList{} Block{_,_,_,_,_,_,_,_,found,_,_,_,_}: opensWith(found,first)
    case BlockNewline{} Block{_,_,_,_,_,_,_,_,_,found,_,_,_}: opensWith(found,first)
    case BlockParagraph{} Block{_,_,_,_,_,_,_,_,_,_,found,_,_}: opensWith(found,first)
    case BlockTable{} Block{_,_,_,_,_,_,_,_,_,_,_,found,_}: opensWith(found,first)
    case BlockText{} Block{_,_,_,_,_,_,_,_,_,_,_,_,found}: opensWith(found,first)

type InlineRule is Data:
  InlineBackpedal{}
  InlineAutolink{}
  InlineBlockSkip{}
  InlineBr{}
  InlineCode{}
  InlineDelLDelim{}
  InlineDelRDelim{}
  InlineEmStrongLDelim{}
  InlineEmStrongRDelimAst{}
  InlineEmStrongRDelimUnd{}
  InlineEscape{}
  InlineLink{}
  InlineNolink{}
  InlineReflink{}
  InlineReflinkSearch{}
  InlineTag{}
  InlineText{}
  InlineUrl{}
def inlineSearch(value: Inline,rule: InlineRule) -> Search:
  match rule value:
    case InlineBackpedal{} Inline{found,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: found
    case InlineAutolink{} Inline{_,found,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: found
    case InlineBlockSkip{} Inline{_,_,found,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: found
    case InlineBr{} Inline{_,_,_,found,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: found
    case InlineCode{} Inline{_,_,_,_,found,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: found
    case InlineDelLDelim{} Inline{_,_,_,_,_,found,_,_,_,_,_,_,_,_,_,_,_,_,_}: found
    case InlineDelRDelim{} Inline{_,_,_,_,_,_,found,_,_,_,_,_,_,_,_,_,_,_,_}: found
    case InlineEmStrongLDelim{} Inline{_,_,_,_,_,_,_,found,_,_,_,_,_,_,_,_,_,_,_}: found
    case InlineEmStrongRDelimAst{} Inline{_,_,_,_,_,_,_,_,found,_,_,_,_,_,_,_,_,_,_}: found
    case InlineEmStrongRDelimUnd{} Inline{_,_,_,_,_,_,_,_,_,found,_,_,_,_,_,_,_,_,_}: found
    case InlineEscape{} Inline{_,_,_,_,_,_,_,_,_,_,found,_,_,_,_,_,_,_,_}: found
    case InlineLink{} Inline{_,_,_,_,_,_,_,_,_,_,_,found,_,_,_,_,_,_,_}: found
    case InlineNolink{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,found,_,_,_,_,_,_}: found
    case InlineReflink{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,found,_,_,_,_,_}: found
    case InlineReflinkSearch{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,_,found,_,_,_,_}: found
    case InlineTag{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,found,_,_,_}: found
    case InlineText{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,found,_,_}: found
    case InlineUrl{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,found,_}: found
def inlineOpens(value: Inline,rule: InlineRule,first: Maybe<&2,U32>) -> Bool:
  match rule value:
    case InlineBackpedal{} Inline{found,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineAutolink{} Inline{_,found,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineBlockSkip{} Inline{_,_,found,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineBr{} Inline{_,_,_,found,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineCode{} Inline{_,_,_,_,found,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineDelLDelim{} Inline{_,_,_,_,_,found,_,_,_,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineDelRDelim{} Inline{_,_,_,_,_,_,found,_,_,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineEmStrongLDelim{} Inline{_,_,_,_,_,_,_,found,_,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineEmStrongRDelimAst{} Inline{_,_,_,_,_,_,_,_,found,_,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineEmStrongRDelimUnd{} Inline{_,_,_,_,_,_,_,_,_,found,_,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineEscape{} Inline{_,_,_,_,_,_,_,_,_,_,found,_,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineLink{} Inline{_,_,_,_,_,_,_,_,_,_,_,found,_,_,_,_,_,_,_}: opensWith(found,first)
    case InlineNolink{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,found,_,_,_,_,_,_}: opensWith(found,first)
    case InlineReflink{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,found,_,_,_,_,_}: opensWith(found,first)
    case InlineReflinkSearch{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,_,found,_,_,_,_}: opensWith(found,first)
    case InlineTag{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,found,_,_,_}: opensWith(found,first)
    case InlineText{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,found,_,_}: opensWith(found,first)
    case InlineUrl{} Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,found,_}: opensWith(found,first)
def inlineBreaks(value: Inline) -> Bool:
  match value: case Inline{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,breaks}: breaks
