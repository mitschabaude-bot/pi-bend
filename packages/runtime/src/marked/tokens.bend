import Base

# marked 18.0.11's tokens (src/Tokens.ts) as one data type. Language-driven
# differences:
# - A constructor is the token's `type`; `typeOf` gives marked's name.
#   `ListToken` is marked's "list" (`List` names Bend's list type).
# - Datatypes cannot be mutually recursive, so list items and table cells
#   are constructors here (marked's ListItem is a Token already; TableCell
#   is its own interface, never found in a `tokens` list).
# - `Generic` is an extension token (`Tokens.Generic`): marked's `type` is
#   its `name` (`type` is a Bend keyword) and the extension's own fields are
#   the typed `value`, whose type `X` the extension's user chooses.
# - Optional fields are Maybe; `text` tokens always carry a token list (empty
#   when marked leaves `tokens` undefined, which renders the same).
# - `Queued` exists only while lexing: the lexer's inline queue entry whose
#   tokens replace it before `lex` returns (upstream shares the token array
#   with the queue entry instead).

type Align is Data:
  AlignLeft{}
  AlignCenter{}
  AlignRight{}

type Token<-X: Data> is Data:
  Blockquote{raw: String,text: String,tokens: List<&2,Token<X>>}
  Br{raw: String}
  Checkbox{raw: String,checked: Bool}
  # `codeBlockStyle` is "indented" for indented code, absent for fences.
  Code{raw: String,codeBlockStyle: Maybe<&2,String>,lang: Maybe<&2,String>,text: String}
  Codespan{raw: String,text: String}
  Def{raw: String,tag: String,href: String,title: Maybe<&2,String>}
  Del{raw: String,text: String,tokens: List<&2,Token<X>>}
  Em{raw: String,text: String,tokens: List<&2,Token<X>>}
  Escape{raw: String,text: String}
  Heading{raw: String,depth: Nat,text: String,tokens: List<&2,Token<X>>}
  Hr{raw: String}
  # Block HTML (Tokens.HTML).
  HTML{raw: String,pre: Bool,text: String,block: Bool}
  Image{raw: String,href: String,title: Maybe<&2,String>,text: String,tokens: List<&2,Token<X>>}
  Link{raw: String,href: String,title: Maybe<&2,String>,text: String,tokens: List<&2,Token<X>>}
  # `start` is the first number of an ordered list (marked's "" otherwise).
  ListToken{raw: String,ordered: Bool,start: Maybe<&2,Nat>,loose: Bool,items: List<&2,Token<X>>}
  ListItem{raw: String,task: Bool,checked: Maybe<&2,Bool>,loose: Bool,text: String,tokens: List<&2,Token<X>>}
  Paragraph{raw: String,text: String,tokens: List<&2,Token<X>>}
  Space{raw: String}
  Strong{raw: String,text: String,tokens: List<&2,Token<X>>}
  # `header` holds TableCell tokens, `rows` lists of them.
  Table{raw: String,align: List<&2,Maybe<&2,Align>>,header: List<&2,Token<X>>,rows: List<&2,List<&2,Token<X>>>}
  TableCell{text: String,tokens: List<&2,Token<X>>,header: Bool,align: Maybe<&2,Align>}
  # Inline HTML (Tokens.Tag).
  Tag{raw: String,inLink: Bool,inRawBlock: Bool,text: String,block: Bool}
  Text{raw: String,text: String,tokens: List<&2,Token<X>>,escaped: Bool}
  Generic{name: String,raw: String,value: X}
  Queued{index: Nat}

# marked's `token.type`.
def typeOf(-X: Data,token: Token<X>) -> String:
  match token:
    case Blockquote{_,_,_}: "blockquote"
    case Br{_}: "br"
    case Checkbox{_,_}: "checkbox"
    case Code{_,_,_,_}: "code"
    case Codespan{_,_}: "codespan"
    case Def{_,_,_,_}: "def"
    case Del{_,_,_}: "del"
    case Em{_,_,_}: "em"
    case Escape{_,_}: "escape"
    case Heading{_,_,_,_}: "heading"
    case Hr{_}: "hr"
    case HTML{_,_,_,_}: "html"
    case Image{_,_,_,_,_}: "image"
    case Link{_,_,_,_,_}: "link"
    case ListToken{_,_,_,_,_}: "list"
    case ListItem{_,_,_,_,_,_}: "list_item"
    case Paragraph{_,_,_}: "paragraph"
    case Space{_}: "space"
    case Strong{_,_,_}: "strong"
    case Table{_,_,_,_}: "table"
    case TableCell{_,_,_,_}: "table_cell"
    case Tag{_,_,_,_,_}: "html"
    case Text{_,_,_,_}: "text"
    case Generic{name,_,_}: name
    case Queued{_}: "queued"

# `token.raw` ("" for table cells, which have none).
def rawOf(-X: Data,token: Token<X>) -> String:
  match token:
    case Blockquote{raw,_,_}: raw
    case Br{raw}: raw
    case Checkbox{raw,_}: raw
    case Code{raw,_,_,_}: raw
    case Codespan{raw,_}: raw
    case Def{raw,_,_,_}: raw
    case Del{raw,_,_}: raw
    case Em{raw,_,_}: raw
    case Escape{raw,_}: raw
    case Heading{raw,_,_,_}: raw
    case Hr{raw}: raw
    case HTML{raw,_,_,_}: raw
    case Image{raw,_,_,_,_}: raw
    case Link{raw,_,_,_,_}: raw
    case ListToken{raw,_,_,_,_}: raw
    case ListItem{raw,_,_,_,_,_}: raw
    case Paragraph{raw,_,_}: raw
    case Space{raw}: raw
    case Strong{raw,_,_}: raw
    case Table{raw,_,_,_}: raw
    case TableCell{_,_,_,_}: ""
    case Tag{raw,_,_,_,_}: raw
    case Text{raw,_,_,_}: raw
    case Generic{_,raw,_}: raw
    case Queued{_}: ""

# A reference link definition (`tokens.links[tag]`).
type LinkDefinition is Data: LinkDefinition{tag: String,href: String,title: Maybe<&2,String>}
