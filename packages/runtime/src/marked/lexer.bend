import Base
import ../ecma-regex.bend as Re
import ./tokens.bend as T
import ./rules.bend as Rules
import ./helpers.bend as H
import ./tokenizer.bend as Tk

# marked 18.0.11's Lexer (src/Lexer.ts) with a Marked instance's extension
# hooks (src/Instance.ts `use`).
#
# `lex` lexes blocks first, queueing the inline source of each heading,
# paragraph, text and table cell, then lexes the queue in order (reference
# links may be defined after their use) and puts each entry's tokens in
# place. Lexing is iterative: blocks and inline runs are tasks of an
# explicit machine whose frames continue a tokenizer after the content it
# lexed (upstream recurses through the tokenizer and lexer objects).

# Extensions
# ----------
# A Marked instance's tokenizer extensions and tokenizer override, as
# closed functions (a static argument of `lex`). Sources are Unicode
# scalars. An extension tokenizer returns a token (usually `Generic`, whose
# raw text it consumes); `start*` give the index in `src` (upstream passes
# `src.slice(1)`, as here) where an extension token may start, so paragraph
# and text runs stop before it. `del` replaces the tokenizer's del method
# (pi's StrictStrikethroughTokenizer); it returns the span, whose text the
# lexer lexes. Language-driven: extension tokenizers get the source only
# (upstream also passes the token list and a lexer they may call), only
# del can be overridden, and del gets the masked source as a Tk.Masking,
# computed by Tk.maskedCodes when read (upstream masks every inlineTokens
# source eagerly; most never have a delimiter scanned).
type Extensions<-X: Data> is Type:
  Extensions{block: List<&2,U32> -> Maybe<&2,T.Token<X>>,startBlock: List<&2,U32> -> Maybe<&2,Nat>,inline: List<&2,U32> -> Maybe<&2,T.Token<X>>,startInline: List<&2,U32> -> Maybe<&2,Nat>,del: Rules.Inline -> List<&2,U32> -> Tk.Masking -> Maybe<&2,U32> -> Maybe<&2,Tk.Delimited>}
def blockExtension(-X: Data,extensions: Extensions<X>) -> List<&2,U32> -> Maybe<&2,T.Token<X>>:
  match extensions: case Extensions{found,_,_,_,_}: found
def startBlock(-X: Data,extensions: Extensions<X>) -> List<&2,U32> -> Maybe<&2,Nat>:
  match extensions: case Extensions{_,found,_,_,_}: found
def inlineExtension(-X: Data,extensions: Extensions<X>) -> List<&2,U32> -> Maybe<&2,T.Token<X>>:
  match extensions: case Extensions{_,_,found,_,_}: found
def startInline(-X: Data,extensions: Extensions<X>) -> List<&2,U32> -> Maybe<&2,Nat>:
  match extensions: case Extensions{_,_,_,found,_}: found
def delTokenizer(-X: Data,extensions: Extensions<X>) -> Rules.Inline -> List<&2,U32> -> Tk.Masking -> Maybe<&2,U32> -> Maybe<&2,Tk.Delimited>:
  match extensions: case Extensions{_,_,_,_,found}: found

# No extensions: marked's own tokenizer.
def noToken(-X: Data,src: List<&2,U32>) -> Maybe<&2,T.Token<X>>: None{}
def noStart(src: List<&2,U32>) -> Maybe<&2,Nat>: None{}
def defaultDel(rules: Rules.Inline,src: List<&2,U32>,masked: Tk.Masking,previous: Maybe<&2,U32>) -> Maybe<&2,Tk.Delimited>: Tk.del(rules,src,masked,previous)

# The inline queue
# ----------------
# Entries newest first; `count` is the next entry's index.
type Queue is Data: Queue{entries: List<&2,String>,count: Nat}
def queued(+queue: Queue,+src: String) -> Queue:
  match queue: case Queue{entries,count}: Queue{src <> entries,count + 1n}
def nextIndex(+queue: Queue) -> Nat:
  match queue: case Queue{_,count}: count
# `inlineQueue.at(-1).src = src`
def lastSet(+queue: Queue,+src: String) -> Queue:
  match queue:
    case Queue{_ <> older,count}: Queue{src <> older,count}
    case Queue{Nil{},count}: Queue{Nil{},count}
# `inlineQueue.pop()`
def popped(+queue: Queue) -> Queue:
  match queue:
    case Queue{_ <> older,count}: Queue{older,count - 1n}
    case Queue{Nil{},count}: Queue{Nil{},count}
# The newest entry starting with a task checkbox loses it.
def taskReplaced(+entries: List<&2,String>,+reversed: List<&2,String>) -> List<&2,String>:
  match entries:
    case Nil{}: List.reverse(&2,String,reversed)
    case +entry <> +rest: Bool.pick(Unit -> List<&2,String>,Tk.listIsTask(entry),_ => List.append(&2,String,List.reverse(&2,String,Tk.listReplaceTask(entry) <> reversed),rest),_ => taskReplaced(rest,entry <> reversed))(Unit{})
def withoutTask(+queue: Queue) -> Queue:
  match queue: case Queue{entries,count}: Queue{taskReplaced(entries,Nil{}),count}

# Block state: `state.top`, the reference definitions and the queue.
type BlockState is Data: BlockState{top: Bool,links: List<&2,T.LinkDefinition>,queue: Queue}
def withTop(+state: BlockState,+top: Bool) -> BlockState:
  match state: case BlockState{_,links,queue}: BlockState{top,links,queue}
def topOf(+state: BlockState) -> Bool:
  match state: case BlockState{top,_,_}: top
def queueOf(+state: BlockState) -> Queue:
  match state: case BlockState{_,_,queue}: queue
def withQueue(+state: BlockState,+queue: Queue) -> BlockState:
  match state: case BlockState{top,links,_}: BlockState{top,links,queue}
def linksOf(+state: BlockState) -> List<&2,T.LinkDefinition>:
  match state: case BlockState{_,links,_}: links
def enqueued(+state: BlockState,+src: String) -> BlockState:
  match state: case BlockState{top,links,queue}: BlockState{top,links,queued(queue,src)}

# Tokens
# ------

# `token.raw += suffix`
def rawAppended(-X: Data,+token: T.Token<X>,+suffix: String) -> T.Token<X>:
  match token:
    case T.Blockquote{raw,text,tokens}: T.Blockquote{raw ++ suffix,text,tokens}
    case T.Br{raw}: T.Br{raw ++ suffix}
    case T.Checkbox{raw,checked}: T.Checkbox{raw ++ suffix,checked}
    case T.Code{raw,style,lang,text}: T.Code{raw ++ suffix,style,lang,text}
    case T.Codespan{raw,text}: T.Codespan{raw ++ suffix,text}
    case T.Def{raw,tag,href,title}: T.Def{raw ++ suffix,tag,href,title}
    case T.Del{raw,text,tokens}: T.Del{raw ++ suffix,text,tokens}
    case T.Em{raw,text,tokens}: T.Em{raw ++ suffix,text,tokens}
    case T.Escape{raw,text}: T.Escape{raw ++ suffix,text}
    case T.Heading{raw,depth,text,tokens}: T.Heading{raw ++ suffix,depth,text,tokens}
    case T.Hr{raw}: T.Hr{raw ++ suffix}
    case T.HTML{raw,pre,text,block}: T.HTML{raw ++ suffix,pre,text,block}
    case T.Image{raw,href,title,text,tokens}: T.Image{raw ++ suffix,href,title,text,tokens}
    case T.Link{raw,href,title,text,tokens}: T.Link{raw ++ suffix,href,title,text,tokens}
    case T.ListToken{raw,ordered,start,loose,items}: T.ListToken{raw ++ suffix,ordered,start,loose,items}
    case T.ListItem{raw,task,checked,loose,text,tokens}: T.ListItem{raw ++ suffix,task,checked,loose,text,tokens}
    case T.Paragraph{raw,text,tokens}: T.Paragraph{raw ++ suffix,text,tokens}
    case T.Space{raw}: T.Space{raw ++ suffix}
    case T.Strong{raw,text,tokens}: T.Strong{raw ++ suffix,text,tokens}
    case T.Table{raw,align,header,rows}: T.Table{raw ++ suffix,align,header,rows}
    case T.TableCell{text,tokens,header,align}: T.TableCell{text,tokens,header,align}
    case T.Tag{raw,inLink,inRawBlock,text,block}: T.Tag{raw ++ suffix,inLink,inRawBlock,text,block}
    case T.Text{raw,text,tokens,escaped}: T.Text{raw ++ suffix,text,tokens,escaped}
    case T.Generic{name,raw,value}: T.Generic{name,raw ++ suffix,value}
    case T.Queued{index}: T.Queued{index}
def isParagraphOrText(-X: Data,+tokens: List<&2,T.Token<X>>) -> Bool:
  match tokens:
    case T.Paragraph{_,_,_} <> _: True{}
    case T.Text{_,_,_,_} <> _: True{}
    case _: False{}
def isParagraph(-X: Data,+tokens: List<&2,T.Token<X>>) -> Bool:
  match tokens:
    case T.Paragraph{_,_,_} <> _: True{}
    case _: False{}
def isText(-X: Data,+tokens: List<&2,T.Token<X>>) -> Bool:
  match tokens:
    case T.Text{_,_,_,_} <> _: True{}
    case _: False{}
# The last token's text after `lastToken.raw += (lastToken.raw ends with a
# newline ? "" : "\n") + raw; lastToken.text += "\n" + text`, for a last
# paragraph or text.
def separated(+raw: String) -> String: Bool.pick(String,H.endsWithChar(raw,'\n'),"","\n")
def continuedLast(-X: Data,+tokens: List<&2,T.Token<X>>,+raw: String,+text: String) -> List<&2,T.Token<X>>:
  match tokens:
    case T.Paragraph{+last,before,inner} <> rest: T.Paragraph{last ++ separated(last) ++ raw,before ++ "\n" ++ text,inner} <> rest
    case T.Text{+last,before,inner,escaped} <> rest: T.Text{last ++ separated(last) ++ raw,before ++ "\n" ++ text,inner,escaped} <> rest
    case other: other
def lastText(-X: Data,+tokens: List<&2,T.Token<X>>) -> String:
  match tokens:
    case T.Paragraph{_,text,_} <> _: text
    case T.Text{_,text,_,_} <> _: text
    case _: ""
# A space of one newline ends the last token's line instead.
def spaced(-X: Data,+raw: String,+tokens: List<&2,T.Token<X>>) -> List<&2,T.Token<X>>:
  match tokens:
    case +last <> +rest: Bool.pick(Unit -> List<&2,T.Token<X>>,Nat.is_eq(String.length(raw),1n),_ => rawAppended(X,last,"\n") <> rest,_ => T.Space{raw} <> last <> rest)(Unit{})
    case Nil{}: [T.Space{raw}]

# The block machine
# -----------------

type BlockTask<-X: Data> is Data:
  # blockTokens(src, tokens, lastParagraphClipped); tokens newest first.
  Blocks{src: List<&2,U32>,clipped: Bool,tokens: List<&2,T.Token<X>>}
  # The blockquote tokenizer's loop over its remaining lines.
  Quote{lines: List<&2,String>,raw: String,text: String,tokens: List<&2,T.Token<X>>}
  # The list tokenizer lexing its items.
  Items{list: Tk.ListDraft,pending: List<&2,Tk.ItemDraft>,done: List<&2,T.Token<X>>}
type BlockFrame<-X: Data> is Data:
  # blockTokens continues after a blockquote or list token.
  Pushed{src: List<&2,U32>,clipped: Bool,tokens: List<&2,T.Token<X>>}
  # The blockquote continues after lexing a chunk; `top` is state.top to
  # restore.
  Chunked{lines: List<&2,String>,raw: String,text: String,top: Bool}
  # A nested blockquote or list re-read with the continuation lines.
  Requoted{raw: String,text: String,old: T.Token<X>,tokens: List<&2,T.Token<X>>}
  Relisted{raw: String,text: String,old: T.Token<X>,newText: String,tokens: List<&2,T.Token<X>>}
  ItemLexed{list: Tk.ListDraft,item: Tk.ItemDraft,pending: List<&2,Tk.ItemDraft>,done: List<&2,T.Token<X>>}
type Given<-X: Data> is Data:
  GivenTokens{tokens: List<&2,T.Token<X>>}
  GivenToken{token: T.Token<X>}
  GivenNone{}
type BlockMode<-X: Data> is Data:
  RunBlock{task: BlockTask<X>}
  GiveBlock{given: Given<X>}
type BlockMachine<-X: Data> is Data: BlockMachine{state: BlockState,frames: List<&2,BlockFrame<X>>,mode: BlockMode<X>}

def runBlock(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+task: BlockTask<X>) -> BlockMachine<X>: BlockMachine{state,frames,RunBlock{task}}
def giveBlock(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+given: Given<X>) -> BlockMachine<X>: BlockMachine{state,frames,GiveBlock{given}}

# One iteration of blockTokens: its position and surroundings.
type Here<-X: Data> is Data: Here{src: List<&2,U32>,clipped: Bool,tokens: List<&2,T.Token<X>>,state: BlockState,frames: List<&2,BlockFrame<X>>}
def hereSrc(-X: Data,+here: Here<X>) -> List<&2,U32>:
  match here: case Here{src,_,_,_,_}: src
def hereState(-X: Data,+here: Here<X>) -> BlockState:
  match here: case Here{_,_,_,state,_}: state
# The iteration consumed `raw`, leaving `tokens` and `state`.
def consumed(-X: Data,+here: Here<X>,+raw: String,+tokens: List<&2,T.Token<X>>,+state: BlockState) -> BlockMachine<X>:
  match here: case Here{src,clipped,_,_,frames}: runBlock(X,state,frames,Blocks{Tk.drop(src,Tk.lengthOf(raw)),clipped,tokens})
def pushed(-X: Data,+here: Here<X>,+token: T.Token<X>) -> BlockMachine<X>:
  match here: case Here{src,clipped,tokens,state,frames}: runBlock(X,state,frames,Blocks{Tk.drop(src,Tk.lengthOf(T.rawOf(X,token))),clipped,token <> tokens})
# No tokenizer applies (upstream throws "Infinite loop on byte"): the tokens
# so far.
def stopped(-X: Data,+here: Here<X>) -> BlockMachine<X>:
  match here: case Here{_,_,tokens,state,frames}: giveBlock(X,withTop(state,True{}),frames,GivenTokens{tokens})

# blockTokens
# -----------
# One iteration tries the extension and then each tokenizer in marked's
# order; each `after*` step takes the previous tokenizer's result.

# A merged paragraph or text: the queue's last entry takes its text.
def textMerged(-X: Data,+src: List<&2,U32>,+clipped: Bool,+tokens: List<&2,T.Token<X>>,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+raw: String) -> BlockMachine<X>:
  runBlock(X,withQueue(state,lastSet(queueOf(state),lastText(X,tokens))),frames,Blocks{Tk.drop(src,Tk.lengthOf(raw)),clipped,tokens})
def headed(-X: Data,+here: Here<X>,+raw: String,+depth: Nat,+text: String) -> BlockMachine<X>:
  match here:
    case Here{src,clipped,tokens,+state,frames}:
      runBlock(X,enqueued(state,text),frames,Blocks{Tk.drop(src,Tk.lengthOf(raw)),clipped,T.Heading{raw,depth,text,[T.Queued{nextIndex(queueOf(state))}]} <> tokens})
# The paragraph merges into a paragraph before it when the previous
# paragraph was cut short at an extension's start.
def paragraphFound(-X: Data,+here: Here<X>,+raw: String,+text: String,+clippedNext: Bool) -> BlockMachine<X>:
  match here:
    case Here{+src,+clipped,+tokens,+state,+frames}:
      Bool.pick(Unit -> BlockMachine<X>,clipped && isParagraph(X,tokens),
        _ => textMerged(X,src,clippedNext,continuedLast(X,tokens,raw,text),state,frames,raw),
        _ => runBlock(X,enqueued(state,text),frames,Blocks{Tk.drop(src,Tk.lengthOf(raw)),clippedNext,T.Paragraph{raw,text,[T.Queued{nextIndex(queueOf(state))}]} <> tokens}))(Unit{})
def textFound(-X: Data,+here: Here<X>,+raw: String,+text: String) -> BlockMachine<X>:
  match here:
    case Here{+src,+clipped,+tokens,+state,+frames}:
      Bool.pick(Unit -> BlockMachine<X>,isText(X,tokens),
        _ => textMerged(X,src,clipped,continuedLast(X,tokens,raw,text),state,frames,raw),
        _ => runBlock(X,enqueued(state,text),frames,Blocks{Tk.drop(src,Tk.lengthOf(raw)),clipped,T.Text{raw,text,[T.Queued{nextIndex(queueOf(state))}],False{}} <> tokens}))(Unit{})
def afterText(-X: Data,+here: Here<X>,+found: Maybe<&2,Tk.Texted>) -> BlockMachine<X>:
  match found:
    case Some{Tk.Texted{raw,text}}: textFound(X,here,raw,text)
    case None{}: stopped(X,here)
# `cutSrc`: the source up to an extension's start after the first character,
# and whether that cut anything off.
type Cut is Data: Cut{src: List<&2,U32>,clipped: Bool}
def cutClipped(+cut: Cut) -> Bool:
  match cut: case Cut{_,clipped}: clipped
def afterParagraph(-X: Data,+rules: Rules.Block,+here: Here<X>,+cut: Cut,+found: Maybe<&2,Tk.Texted>) -> BlockMachine<X>:
  match found:
    case Some{Tk.Texted{raw,text}}: paragraphFound(X,here,raw,text,cutClipped(cut))
    case None{}: afterText(X,here,Tk.blockText(rules,hereSrc(X,here)))
def cutSource(+start: Maybe<&2,Nat>,+src: List<&2,U32>) -> Cut:
  match start:
    case Some{+index}: Cut{Tk.take(src,index + 1n),Bool.not(List.is_empty(&2,U32,Tk.drop(src,index + 1n)))}
    case None{}: Cut{src,False{}}
def cutCodes(+cut: Cut) -> List<&2,U32>:
  match cut: case Cut{codes,_}: codes
def topParagraph(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>) -> BlockMachine<X>:
  +cut = cutSource(startBlock(X,ext)(Tk.drop(hereSrc(X,here),1n)),hereSrc(X,here))
  afterParagraph(X,rules,here,cut,Tk.paragraph(rules,cutCodes(cut)))
# Paragraphs only at the top level (`state.top`); text otherwise.
def paragraphs(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>) -> BlockMachine<X>:
  Bool.pick(Unit -> BlockMachine<X>,topOf(hereState(X,here)),_ => topParagraph(~X,~ext,rules,here),_ => afterText(X,here,Tk.blockText(rules,hereSrc(X,here))))(Unit{})
def afterLheading(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,Tk.Titled>) -> BlockMachine<X>:
  match found:
    case Some{Tk.Titled{raw,depth,text}}: headed(X,here,raw,depth,text)
    case None{}: paragraphs(~X,~ext,rules,here)

# Table cells, queued in order.
type Cells<-X: Data> is Data: Cells{cells: List<&2,T.Token<X>>,state: BlockState}
def alignFirst(+aligns: List<&2,Maybe<&2,T.Align>>) -> Maybe<&2,T.Align>:
  match aligns:
    case align <> _: align
    case Nil{}: None{}
def alignRest(+aligns: List<&2,Maybe<&2,T.Align>>) -> List<&2,Maybe<&2,T.Align>>:
  match aligns:
    case _ <> rest: rest
    case Nil{}: Nil{}
def cellsQueued(-X: Data,+texts: List<&2,String>,+aligns: List<&2,Maybe<&2,T.Align>>,+header: Bool,+state: BlockState,+reversed: List<&2,T.Token<X>>) -> Cells<X>:
  match texts:
    case Nil{}: Cells{List.reverse(&2,T.Token<X>,reversed),state}
    case +text <> rest: cellsQueued(X,rest,alignRest(aligns),header,enqueued(state,text),T.TableCell{text,[T.Queued{nextIndex(queueOf(state))}],header,alignFirst(aligns)} <> reversed)
# Rows hold as many cells as the header.
@unsafe def rowsOf(-X: Data,+cells: List<&2,T.Token<X>>,+count: Nat,+reversed: List<&2,List<&2,T.Token<X>>>) -> List<&2,List<&2,T.Token<X>>>:
  match cells:
    case Nil{}: List.reverse(&2,List<&2,T.Token<X>>,reversed)
    case +cell <> +rest: rowsOf(X,List.drop(&2,T.Token<X>,rest,count - 1n),count,List.take(&2,T.Token<X>,cell <> rest,count) <> reversed)
def repeated(+aligns: List<&2,Maybe<&2,T.Align>>,+count: Nat) -> List<&2,Maybe<&2,T.Align>>:
  match count:
    case Zero{}: Nil{}
    case Succ{more}: List.append(&2,Maybe<&2,T.Align>,aligns,repeated(aligns,more))
def tableQueued(-X: Data,+here: Here<X>,+raw: String,+align: List<&2,Maybe<&2,T.Align>>,+header: List<&2,T.Token<X>>,+count: Nat,+rows: Cells<X>) -> BlockMachine<X>:
  match here rows:
    case Here{src,clipped,tokens,_,frames} Cells{cells,state}: runBlock(X,state,frames,Blocks{Tk.drop(src,Tk.lengthOf(raw)),clipped,T.Table{raw,align,header,rowsOf(X,cells,count,Nil{})} <> tokens})
def tableRowsQueued(-X: Data,+here: Here<X>,+raw: String,+align: List<&2,Maybe<&2,T.Align>>,+rows: List<&2,List<&2,String>>,+header: Cells<X>) -> BlockMachine<X>:
  match header:
    case Cells{+cells,state}: tableQueued(X,here,raw,align,cells,List.length(&2,T.Token<X>,cells),cellsQueued(X,List.concat(&2,String,rows),repeated(align,List.length(&2,List<&2,String>,rows)),False{},state,Nil{}))
def afterTable(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,Tk.TableDraft>) -> BlockMachine<X>:
  match found:
    case Some{Tk.TableDraft{raw,+align,header,rows}}: tableRowsQueued(X,here,raw,align,rows,cellsQueued(X,header,align,True{},hereState(X,here),Nil{}))
    case None{}: afterLheading(~X,~ext,rules,here,Tk.lheading(rules,hereSrc(X,here)))

def linked(-X: Data,+state: BlockState,+token: T.Token<X>) -> BlockState:
  match state token:
    case BlockState{top,links,queue} T.Def{_,tag,href,title}: BlockState{top,T.LinkDefinition{tag,href,title} <> links,queue}
    case state _: state
# A definition after a paragraph or text continues it; otherwise the first
# definition of a label counts.
def defined(-X: Data,+here: Here<X>,+token: T.Token<X>,+raw: String,+tag: String) -> BlockMachine<X>:
  match here:
    case Here{+src,+clipped,+tokens,+state,+frames}:
      Bool.pick(Unit -> BlockMachine<X>,isParagraphOrText(X,tokens),_ => textMerged(X,src,clipped,continuedLast(X,tokens,raw,raw),state,frames,raw),
        _ => Bool.pick(Unit -> BlockMachine<X>,Tk.hasDefinition(linksOf(state),tag),_ => runBlock(X,state,frames,Blocks{Tk.drop(src,Tk.lengthOf(raw)),clipped,tokens}),
          _ => runBlock(X,linked(X,state,token),frames,Blocks{Tk.drop(src,Tk.lengthOf(raw)),clipped,token <> tokens}))(Unit{}))(Unit{})
def afterDefinition(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,T.Token<X>>) -> BlockMachine<X>:
  match found:
    case Some{T.Def{raw,tag,href,title}}: defined(X,here,T.Def{raw,tag,href,title},raw,tag)
    case _: afterTable(~X,~ext,rules,here,Tk.table(rules,hereSrc(X,here)))
def afterHtml(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,T.Token<X>>) -> BlockMachine<X>:
  match found:
    case Some{token}: pushed(X,here,token)
    case None{}: afterDefinition(~X,~ext,rules,here,Tk.definition(X,rules,hereSrc(X,here)))
def itemsOf(+draft: Tk.ListDraft) -> List<&2,Tk.ItemDraft>:
  match draft: case Tk.ListDraft{_,_,_,_,items}: items
def listStarted(-X: Data,+here: Here<X>,+draft: Tk.ListDraft) -> BlockMachine<X>:
  match here:
    case Here{src,clipped,tokens,state,frames}: runBlock(X,state,Pushed{src,clipped,tokens} <> frames,Items{draft,itemsOf(draft),Nil{}})
def afterList(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,Tk.ListDraft>) -> BlockMachine<X>:
  match found:
    case Some{draft}: listStarted(X,here,draft)
    case None{}: afterHtml(~X,~ext,rules,here,Tk.html(X,rules,hereSrc(X,here)))
def quoteStarted(-X: Data,+here: Here<X>,+raw: String) -> BlockMachine<X>:
  match here:
    case Here{src,clipped,tokens,state,frames}: runBlock(X,state,Pushed{src,clipped,tokens} <> frames,Quote{H.linesOf(H.rtrim(raw,'\n')),"","",Nil{}})
def afterBlockquote(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,String>) -> BlockMachine<X>:
  match found:
    case Some{raw}: quoteStarted(X,here,raw)
    case None{}: afterList(~X,~ext,rules,here,Tk.list(rules,hereSrc(X,here)))
def afterHr(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,T.Token<X>>) -> BlockMachine<X>:
  match found:
    case Some{token}: pushed(X,here,token)
    case None{}: afterBlockquote(~X,~ext,rules,here,Tk.blockquote(rules,hereSrc(X,here)))
def afterHeading(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,Tk.Titled>) -> BlockMachine<X>:
  match found:
    case Some{Tk.Titled{raw,depth,text}}: headed(X,here,raw,depth,text)
    case None{}: afterHr(~X,~ext,rules,here,Tk.hr(X,rules,hereSrc(X,here)))
def afterFences(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,T.Token<X>>) -> BlockMachine<X>:
  match found:
    case Some{token}: pushed(X,here,token)
    case None{}: afterHeading(~X,~ext,rules,here,Tk.heading(rules,hereSrc(X,here)))
# Indented code cannot interrupt a paragraph: it continues one.
def coded(-X: Data,+here: Here<X>,+token: T.Token<X>,+raw: String,+text: String) -> BlockMachine<X>:
  match here:
    case Here{+src,+clipped,+tokens,+state,+frames}:
      Bool.pick(Unit -> BlockMachine<X>,isParagraphOrText(X,tokens),_ => textMerged(X,src,clipped,continuedLast(X,tokens,raw,text),state,frames,raw),
        _ => runBlock(X,state,frames,Blocks{Tk.drop(src,Tk.lengthOf(raw)),clipped,token <> tokens}))(Unit{})
def afterCode(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,T.Token<X>>) -> BlockMachine<X>:
  match found:
    case Some{T.Code{raw,style,lang,text}}: coded(X,here,T.Code{raw,style,lang,text},raw,text)
    case _: afterFences(~X,~ext,rules,here,Tk.fences(X,rules,hereSrc(X,here)))
def spaceFound(-X: Data,+here: Here<X>,+raw: String) -> BlockMachine<X>:
  match here:
    case Here{src,clipped,tokens,state,frames}: runBlock(X,state,frames,Blocks{Tk.drop(src,Tk.lengthOf(raw)),clipped,spaced(X,raw,tokens)})
def afterSpace(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,T.Token<X>>) -> BlockMachine<X>:
  match found:
    case Some{T.Space{raw}}: spaceFound(X,here,raw)
    case _: afterCode(~X,~ext,rules,here,Tk.code(X,rules,hereSrc(X,here)))
# An extension token that consumes nothing would not advance.
def afterExtension(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>,+found: Maybe<&2,T.Token<X>>) -> BlockMachine<X>:
  match found:
    case Some{+token}: Bool.pick(Unit -> BlockMachine<X>,String.is_empty(T.rawOf(X,token)),_ => stopped(X,here),_ => pushed(X,here,token))(Unit{})
    case None{}: afterSpace(~X,~ext,rules,here,Tk.space(X,rules,hereSrc(X,here)))
def blocksStep(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+here: Here<X>) -> BlockMachine<X>:
  match here:
    case Here{Nil{},_,tokens,state,frames}: giveBlock(X,withTop(state,True{}),frames,GivenTokens{tokens})
    case Here{+src,clipped,tokens,state,frames}: afterExtension(~X,~ext,rules,Here{src,clipped,tokens,state,frames},blockExtension(X,ext)(src))

# The blockquote tokenizer
# ------------------------

# Lines up to a continuation: every line until a line without '>' follows
# one with it.
type Chunk is Data: Chunk{current: List<&2,String>,remaining: List<&2,String>}
def chunkOf(+lines: List<&2,String>,+inQuote: Bool,+reversed: List<&2,String>) -> Chunk:
  match lines:
    case Nil{}: Chunk{List.reverse(&2,String,reversed),Nil{}}
    case +line <> +rest:
      Bool.pick(Unit -> Chunk,H.blockquoteStart(line),_ => chunkOf(rest,True{},line <> reversed),
        _ => Bool.pick(Unit -> Chunk,inQuote,_ => Chunk{List.reverse(&2,String,reversed),line <> rest},_ => chunkOf(rest,False{},line <> reversed))(Unit{}))(Unit{})
# `raw ? raw + "\n" + more : more`
def joined(+text: String,+more: String) -> String: Bool.pick(Unit -> String,String.is_empty(text),_ => more,_ => text ++ "\n" ++ more)(Unit{})
def quoteChunked(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+chunk: Chunk,+raw: String,+text: String,+tokens: List<&2,T.Token<X>>) -> BlockMachine<X>:
  match chunk:
    case Chunk{current,remaining}:
      +currentRaw = H.joinLines(current)
      +currentText = H.quoteMarkersRemoved(H.blockquoteSetextReplace(currentRaw))
      runBlock(X,withTop(state,True{}),Chunked{remaining,joined(raw,currentRaw),joined(text,currentText),topOf(state)} <> frames,Blocks{Re.codes(currentText),True{},tokens})
def quoteToken(-X: Data,+raw: String,+text: String,+tokens: List<&2,T.Token<X>>) -> T.Token<X>: T.Blockquote{raw,text,List.reverse(&2,T.Token<X>,tokens)}
def quoteStep(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+lines: List<&2,String>,+raw: String,+text: String,+tokens: List<&2,T.Token<X>>) -> BlockMachine<X>:
  match lines:
    case Nil{}: giveBlock(X,state,frames,GivenToken{quoteToken(X,raw,text,tokens)})
    case line <> rest: quoteChunked(X,state,frames,chunkOf(line <> rest,False{},Nil{}),raw,text,tokens)
def requotedWith(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+found: Maybe<&2,String>) -> BlockMachine<X>:
  match found:
    case Some{raw}: runBlock(X,state,frames,Quote{H.linesOf(H.rtrim(raw,'\n')),"","",Nil{}})
    case None{}: giveBlock(X,state,frames,GivenNone{})
def requoted(-X: Data,+rules: Rules.Block,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+newText: String) -> BlockMachine<X>:
  requotedWith(X,state,frames,Tk.blockquote(rules,Re.codes(newText)))
def relisted(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+found: Maybe<&2,Tk.ListDraft>) -> BlockMachine<X>:
  match found:
    case Some{+draft}: runBlock(X,state,frames,Items{draft,itemsOf(draft),Nil{}})
    case None{}: giveBlock(X,state,frames,GivenNone{})

# After a chunk: a continuation extends a nested blockquote or list, ends
# after code, and continues otherwise.
def quoteContinued(-X: Data,+rules: Rules.Block,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+remaining: List<&2,String>,+raw: String,+text: String,+tokens: List<&2,T.Token<X>>) -> BlockMachine<X>:
  match tokens:
    case T.Code{codeRaw,style,lang,code} <> rest: giveBlock(X,state,frames,GivenToken{quoteToken(X,raw,text,T.Code{codeRaw,style,lang,code} <> rest)})
    case T.Blockquote{oldRaw,oldText,inner} <> rest:
      +continuation = H.joinLines(remaining)
      requoted(X,rules,state,Requoted{raw ++ "\n" ++ continuation,text,T.Blockquote{oldRaw,oldText,inner},rest} <> frames,oldRaw ++ "\n" ++ H.quoteMarkersRemoved(continuation))
    case T.ListToken{oldRaw,ordered,start,loose,items} <> rest:
      +newText = oldRaw ++ "\n" ++ H.joinLines(remaining)
      relisted(X,state,Relisted{raw,text,T.ListToken{oldRaw,ordered,start,loose,items},newText,rest} <> frames,Tk.list(rules,Re.codes(newText)))
    case tokens: runBlock(X,state,frames,Quote{remaining,raw,text,tokens})

# The list tokenizer
# ------------------

def withLoose(+draft: Tk.ListDraft,+loose: Bool) -> Tk.ListDraft:
  match draft: case Tk.ListDraft{raw,ordered,start,_,items}: Tk.ListDraft{raw,ordered,start,loose,items}
def draftLoose(+draft: Tk.ListDraft) -> Bool:
  match draft: case Tk.ListDraft{_,_,_,loose,_}: loose
# A space of two or more newlines inside an item makes the list loose.
def countNewlines(+text: String,+count: Nat) -> Nat:
  match text:
    case SNil{}: count
    case SCon{+char,rest}: countNewlines(rest,Bool.pick(Nat,Char.is_eq(char,'\n'),count + 1n,count))
def multipleLineBreaks(-X: Data,+tokens: List<&2,T.Token<X>>) -> Bool:
  match tokens:
    case Nil{}: False{}
    case T.Space{raw} <> rest: Bool.pick(Unit -> Bool,Nat.is_ge(countNewlines(raw,0n),2n),_ => True{},_ => multipleLineBreaks(X,rest))(Unit{})
    case _ <> rest: multipleLineBreaks(X,rest)
def itemLexed(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+list: Tk.ListDraft,+item: Tk.ItemDraft,+pending: List<&2,Tk.ItemDraft>,+done: List<&2,T.Token<X>>,+tokens: List<&2,T.Token<X>>) -> BlockMachine<X>:
  match item:
    case Tk.ItemDraft{raw,task,text}:
      runBlock(X,state,frames,Items{withLoose(list,draftLoose(list) || multipleLineBreaks(X,tokens)),pending,T.ListItem{raw,task,None{},False{},text,tokens} <> done})

# Task checkboxes: the item's first paragraph or text loses its `[ ]`, as
# does the newest inline queue entry starting with one; the checkbox goes
# into the item (or, in a loose list, into that paragraph).
def taskStripped(-X: Data,+tokens: List<&2,T.Token<X>>) -> List<&2,T.Token<X>>:
  match tokens:
    case T.Paragraph{raw,text,inner} <> rest: T.Paragraph{Tk.listReplaceTask(raw),Tk.listReplaceTask(text),inner} <> rest
    case T.Text{raw,text,inner,escaped} <> rest: T.Text{Tk.listReplaceTask(raw),Tk.listReplaceTask(text),inner,escaped} <> rest
    case other: other
def checkboxFirst(-X: Data,+box: T.Token<X>,+boxRaw: String,+loose: Bool,+tokens: List<&2,T.Token<X>>) -> List<&2,T.Token<X>>:
  match loose tokens:
    case False{} tokens: box <> tokens
    case True{} T.Paragraph{raw,text,inner} <> rest: T.Paragraph{boxRaw ++ raw,boxRaw ++ text,box <> inner} <> rest
    case True{} T.Text{raw,text,inner,escaped} <> rest: T.Text{boxRaw ++ raw,boxRaw ++ text,box <> inner,escaped} <> rest
    case True{} tokens: T.Paragraph{boxRaw,boxRaw,[box]} <> tokens
def boxed(-X: Data,+mark: Maybe<&2,Char>,+loose: Bool,+raw: String,+task: Bool,+itemLoose: Bool,+text: String,+tokens: List<&2,T.Token<X>>) -> T.Token<X>:
  match mark:
    case Some{+mark}:
      +boxRaw = "[" ++ SCon{mark,SNil{}} ++ "] "
      +checked = Bool.not(Char.is_eq(mark,' '))
      T.ListItem{raw,task,Some{checked},itemLoose,text,checkboxFirst(X,T.Checkbox{boxRaw,checked},boxRaw,loose,tokens)}
    case None{}: T.ListItem{raw,task,None{},itemLoose,text,tokens}
type Tasked<-X: Data> is Data: Tasked{items: List<&2,T.Token<X>>,queue: Queue}
def tasked(-X: Data,+items: List<&2,T.Token<X>>,+loose: Bool,+queue: Queue,+reversed: List<&2,T.Token<X>>) -> Tasked<X>:
  match items:
    case Nil{}: Tasked{List.reverse(&2,T.Token<X>,reversed),queue}
    case T.ListItem{+raw,+task,checked,+itemLoose,+text,+tokens} <> rest:
      Bool.pick(Unit -> Tasked<X>,task && isParagraphOrText(X,tokens),
        _ => tasked(X,rest,loose,withoutTask(queue),boxed(X,Tk.checkbox(raw),loose,raw,task,itemLoose,Tk.listReplaceTask(text),taskStripped(X,tokens)) <> reversed),
        _ => tasked(X,rest,loose,queue,T.ListItem{raw,False{},checked,itemLoose,text,tokens} <> reversed))(Unit{})
    case item <> rest: tasked(X,rest,loose,queue,item <> reversed)
def paragraphsOf(-X: Data,+tokens: List<&2,T.Token<X>>,+reversed: List<&2,T.Token<X>>) -> List<&2,T.Token<X>>:
  match tokens:
    case Nil{}: List.reverse(&2,T.Token<X>,reversed)
    case T.Text{raw,text,inner,_} <> rest: paragraphsOf(X,rest,T.Paragraph{raw,text,inner} <> reversed)
    case token <> rest: paragraphsOf(X,rest,token <> reversed)
# In a loose list every item is loose and its texts are paragraphs.
def loosened(-X: Data,+items: List<&2,T.Token<X>>,+reversed: List<&2,T.Token<X>>) -> List<&2,T.Token<X>>:
  match items:
    case Nil{}: List.reverse(&2,T.Token<X>,reversed)
    case T.ListItem{raw,task,checked,_,text,tokens} <> rest: loosened(X,rest,T.ListItem{raw,task,checked,True{},text,paragraphsOf(X,tokens,Nil{})} <> reversed)
    case item <> rest: loosened(X,rest,item <> reversed)
def listToken(-X: Data,+draft: Tk.ListDraft,+items: List<&2,T.Token<X>>) -> T.Token<X>:
  match draft:
    case Tk.ListDraft{raw,ordered,start,+loose,_}: T.ListToken{raw,ordered,start,loose,Bool.pick(Unit -> List<&2,T.Token<X>>,loose,_ => loosened(X,items,Nil{}),_ => items)(Unit{})}
def listFinished(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+draft: Tk.ListDraft,+value: Tasked<X>) -> BlockMachine<X>:
  match value:
    case Tasked{items,queue}: giveBlock(X,withQueue(state,queue),frames,GivenToken{listToken(X,draft,items)})
# Each item's text is lexed as blocks with `state.top` off.
def itemsStep(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+list: Tk.ListDraft,+pending: List<&2,Tk.ItemDraft>,+done: List<&2,T.Token<X>>) -> BlockMachine<X>:
  match pending:
    case Nil{}: listFinished(X,state,frames,list,tasked(X,List.reverse(&2,T.Token<X>,done),draftLoose(list),queueOf(state),Nil{}))
    case Tk.ItemDraft{raw,task,+text} <> rest: runBlock(X,withTop(state,False{}),ItemLexed{list,Tk.ItemDraft{raw,task,text},rest,done} <> frames,Blocks{Re.codes(text),False{},Nil{}})

# Running the machine
# -------------------

def executeBlock(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+task: BlockTask<X>) -> BlockMachine<X>:
  match task:
    case Blocks{src,clipped,tokens}: blocksStep(~X,~ext,rules,Here{src,clipped,tokens,state,frames})
    case Quote{lines,raw,text,tokens}: quoteStep(X,state,frames,lines,raw,text,tokens)
    case Items{list,pending,done}: itemsStep(X,state,frames,list,pending,done)
def givenTokens(-X: Data,+given: Given<X>) -> List<&2,T.Token<X>>:
  match given:
    case GivenTokens{tokens}: tokens
    case _: Nil{}
def pushedToken(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+src: List<&2,U32>,+clipped: Bool,+tokens: List<&2,T.Token<X>>,+given: Given<X>) -> BlockMachine<X>:
  match given:
    case GivenToken{+token}: runBlock(X,state,frames,Blocks{Tk.drop(src,Tk.lengthOf(T.rawOf(X,token))),clipped,token <> tokens})
    case _: runBlock(X,state,frames,Blocks{src,clipped,tokens})
def blockquoteText(-X: Data,+token: T.Token<X>) -> String:
  match token:
    case T.Blockquote{_,text,_}: text
    case _: ""
def requotedToken(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+raw: String,+text: String,+old: T.Token<X>,+tokens: List<&2,T.Token<X>>,+given: Given<X>) -> BlockMachine<X>:
  match given:
    case GivenToken{+token}: giveBlock(X,state,frames,GivenToken{quoteToken(X,raw,H.dropEnd(text,String.length(blockquoteText(X,old))) ++ blockquoteText(X,token),token <> tokens)})
    case _: giveBlock(X,state,frames,GivenToken{quoteToken(X,raw,text,old <> tokens)})
def relistedToken(-X: Data,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+raw: String,+text: String,+old: T.Token<X>,+newText: String,+tokens: List<&2,T.Token<X>>,+given: Given<X>) -> BlockMachine<X>:
  match given:
    case GivenToken{+token}:
      +newRaw = T.rawOf(X,token)
      +oldLength = String.length(T.rawOf(X,old))
      runBlock(X,state,frames,Quote{H.linesOf(String.drop(newText,String.length(newRaw))),H.dropEnd(raw,oldLength) ++ newRaw,H.dropEnd(text,oldLength) ++ newRaw,token <> tokens})
    case _: giveBlock(X,state,frames,GivenToken{quoteToken(X,raw,text,old <> tokens)})
def chunkLexed(-X: Data,+rules: Rules.Block,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+remaining: List<&2,String>,+raw: String,+text: String,+top: Bool,+tokens: List<&2,T.Token<X>>) -> BlockMachine<X>:
  match remaining:
    case Nil{}: giveBlock(X,withTop(state,top),frames,GivenToken{quoteToken(X,raw,text,tokens)})
    case line <> rest: quoteContinued(X,rules,withTop(state,top),frames,line <> rest,raw,text,tokens)
def resumeBlock(-X: Data,+rules: Rules.Block,+state: BlockState,+frames: List<&2,BlockFrame<X>>,+frame: BlockFrame<X>,+given: Given<X>) -> BlockMachine<X>:
  match frame:
    case Pushed{src,clipped,tokens}: pushedToken(X,state,frames,src,clipped,tokens,given)
    case Chunked{remaining,raw,text,top}: chunkLexed(X,rules,state,frames,remaining,raw,text,top,givenTokens(X,given))
    case Requoted{raw,text,old,tokens}: requotedToken(X,state,frames,raw,text,old,tokens,given)
    case Relisted{raw,text,old,newText,tokens}: relistedToken(X,state,frames,raw,text,old,newText,tokens,given)
    case ItemLexed{list,item,pending,done}: itemLexed(X,state,frames,list,item,pending,done,List.reverse(&2,T.Token<X>,givenTokens(X,given)))

type BlockDone<-X: Data> is Data: BlockDone{tokens: List<&2,T.Token<X>>,state: BlockState}
# Runs tasks and returns results to frames until the outermost blockTokens
# returns. Every task consumes source or returns to a frame, so the loop
# ends; the termination argument is not mechanized.
@unsafe def driveBlock(~X: Data,~ext: Extensions<X>,+rules: Rules.Block,+machine: BlockMachine<X>) -> BlockDone<X>:
  match machine:
    case BlockMachine{state,Nil{},GiveBlock{given}}: BlockDone{List.reverse(&2,T.Token<X>,givenTokens(X,given)),state}
    case BlockMachine{state,frame <> frames,GiveBlock{given}}: driveBlock(~X,~ext,rules,resumeBlock(X,rules,state,frames,frame,given))
    case BlockMachine{state,frames,RunBlock{task}}: driveBlock(~X,~ext,rules,executeBlock(~X,~ext,rules,state,frames,task))

# The inline machine
# ------------------

type InlineState is Data: InlineState{inLink: Bool,inRawBlock: Bool,linkEmitted: Bool}
# An inlineTokens loop: remaining source and its masked copy, prevChar and
# keepPrevChar, tokens newest first.
type Run<-X: Data> is Data: Run{src: List<&2,U32>,masked: Tk.Masking,previous: Maybe<&2,U32>,keep: Bool,tokens: List<&2,T.Token<X>>}
# The tokenizer an iteration continues with after an outputLink that
# returned nothing.
type Stage is Data:
  FromReflink{}
  FromEmStrong{}
type InlineTask<-X: Data> is Data:
  Iterate{run: Run<X>}
  Resume{stage: Stage,run: Run<X>}
type InlineFrame<-X: Data> is Data:
  # outputLink's text was lexed; restore state and emit or fall back.
  LinkText{run: Run<X>,link: Tk.LinkMatch,text: String,emitted: Bool,rawBlock: Bool,fallback: Stage}
  EmphasisText{run: Run<X>,emphasis: Tk.Emphasis}
  DelText{run: Run<X>,span: Tk.Delimited}
type InlineMode<-X: Data> is Data:
  RunInline{task: InlineTask<X>}
  GiveInline{tokens: List<&2,T.Token<X>>}
type InlineMachine<-X: Data> is Data: InlineMachine{state: InlineState,frames: List<&2,InlineFrame<X>>,mode: InlineMode<X>}

def runInline(-X: Data,+state: InlineState,+frames: List<&2,InlineFrame<X>>,+task: InlineTask<X>) -> InlineMachine<X>: InlineMachine{state,frames,RunInline{task}}
# inlineTokens(text) as a new run.
def lexing(-X: Data,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+text: String) -> Run<X>:
  +src = Re.codes(text)
  Run{src,Tk.Unmasked{src,links,0n},None{},False{},Nil{}}
def runSrc(-X: Data,+run: Run<X>) -> List<&2,U32>:
  match run: case Run{src,_,_,_,_}: src
def runMasked(-X: Data,+run: Run<X>) -> Tk.Masking:
  match run: case Run{_,masked,_,_,_}: masked
def runPrevious(-X: Data,+run: Run<X>) -> Maybe<&2,U32>:
  match run: case Run{_,_,previous,_,_}: previous
def runTokens(-X: Data,+run: Run<X>) -> List<&2,T.Token<X>>:
  match run: case Run{_,_,_,_,tokens}: tokens
# The run after a token of `length` scalars.
def advanced(-X: Data,+run: Run<X>,+length: Nat,+tokens: List<&2,T.Token<X>>) -> Run<X>:
  match run: case Run{src,masked,previous,keep,_}: Run{Tk.drop(src,length),Tk.maskingAdvanced(masked,length),previous,keep,tokens}
def pushedInline(-X: Data,+state: InlineState,+frames: List<&2,InlineFrame<X>>,+run: Run<X>,+token: T.Token<X>) -> InlineMachine<X>:
  runInline(X,state,frames,Iterate{advanced(X,run,Tk.lengthOf(T.rawOf(X,token)),token <> runTokens(X,run))})
def stoppedInline(-X: Data,+state: InlineState,+frames: List<&2,InlineFrame<X>>,+run: Run<X>) -> InlineMachine<X>:
  InlineMachine{state,frames,GiveInline{runTokens(X,run)}}
# Text after text extends it.
def textJoined(-X: Data,+tokens: List<&2,T.Token<X>>,+raw: String,+escaped: Bool) -> List<&2,T.Token<X>>:
  match tokens:
    case T.Text{last,text,inner,before} <> rest: T.Text{last ++ raw,text ++ raw,inner,before} <> rest
    case tokens: T.Text{raw,raw,Nil{},escaped} <> tokens

def inLinkOf(+state: InlineState) -> Bool:
  match state: case InlineState{inLink,_,_}: inLink
def rawBlockOf(+state: InlineState) -> Bool:
  match state: case InlineState{_,rawBlock,_}: rawBlock

# inlineTokens
# ------------
# One iteration tries the extension and then each tokenizer in marked's
# order; links, emphasis and strikethrough push a frame and lex their text
# as a new run.

type At<-X: Data> is Data: At{state: InlineState,frames: List<&2,InlineFrame<X>>,run: Run<X>}
def pushedHere(-X: Data,+here: At<X>,+token: T.Token<X>) -> InlineMachine<X>:
  match here: case At{state,frames,run}: pushedInline(X,state,frames,run,token)
def stoppedHere(-X: Data,+here: At<X>) -> InlineMachine<X>:
  match here: case At{state,frames,run}: stoppedInline(X,state,frames,run)
def hereRun(-X: Data,+here: At<X>) -> Run<X>:
  match here: case At{_,_,run}: run
def hereInline(-X: Data,+here: At<X>) -> InlineState:
  match here: case At{state,_,_}: state

def textRan(-X: Data,+here: At<X>,+raw: String) -> InlineMachine<X>:
  match here:
    case At{+state,frames,Run{src,masked,previous,_,tokens}}:
      +last = Maybe.default(&2,Char,H.lastChar(raw),'_')
      runInline(X,state,frames,Iterate{Run{Tk.drop(src,Tk.lengthOf(raw)),Tk.maskingAdvanced(masked,Tk.lengthOf(raw)),Bool.pick(Maybe<&2,U32>,Char.is_eq(last,'_'),previous,Some{Tk.previousOf(Char.to_u32(last))}),True{},textJoined(X,tokens,raw,rawBlockOf(state))}})
def afterInlineText(-X: Data,+here: At<X>,+found: Maybe<&2,String>) -> InlineMachine<X>:
  match found:
    case Some{raw}: textRan(X,here,raw)
    case None{}: stoppedHere(X,here)
def textStage(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+here: At<X>) -> InlineMachine<X>:
  +src = runSrc(X,hereRun(X,here))
  afterInlineText(X,here,Tk.inlineText(rules,cutCodes(cutSource(startInline(X,ext)(Tk.drop(src,1n)),src))))
def afterUrl(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+here: At<X>,+found: Maybe<&2,T.Token<X>>) -> InlineMachine<X>:
  match found:
    case Some{token}: pushedHere(X,here,token)
    case None{}: textStage(~X,~ext,rules,here)
def urlStage(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+here: At<X>) -> InlineMachine<X>:
  Bool.pick(Unit -> InlineMachine<X>,inLinkOf(hereInline(X,here)),_ => textStage(~X,~ext,rules,here),_ => afterUrl(~X,~ext,rules,here,Tk.url(X,rules,runSrc(X,hereRun(X,here)))))(Unit{})
def afterAutolink(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+here: At<X>,+found: Maybe<&2,T.Token<X>>) -> InlineMachine<X>:
  match found:
    case Some{token}: pushedHere(X,here,token)
    case None{}: urlStage(~X,~ext,rules,here)
def delOpened(-X: Data,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+span: Tk.Delimited) -> InlineMachine<X>:
  match here span:
    case At{state,frames,run} Tk.Delimited{raw,+text}: runInline(X,state,DelText{run,Tk.Delimited{raw,text}} <> frames,Iterate{lexing(X,rules,links,text)})
def afterDel(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+found: Maybe<&2,Tk.Delimited>) -> InlineMachine<X>:
  match found:
    case Some{span}: delOpened(X,rules,links,here,span)
    case None{}: afterAutolink(~X,~ext,rules,here,Tk.autolink(X,rules,runSrc(X,hereRun(X,here))))
def afterBr(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+found: Maybe<&2,T.Token<X>>) -> InlineMachine<X>:
  match found:
    case Some{token}: pushedHere(X,here,token)
    case None{}: afterDel(~X,~ext,rules,links,here,delTokenizer(X,ext)(rules,runSrc(X,hereRun(X,here)),runMasked(X,hereRun(X,here)),runPrevious(X,hereRun(X,here))))
def afterCodespan(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+found: Maybe<&2,T.Token<X>>) -> InlineMachine<X>:
  match found:
    case Some{token}: pushedHere(X,here,token)
    case None{}: afterBr(~X,~ext,rules,links,here,Tk.br(X,rules,runSrc(X,hereRun(X,here))))
def emphasisOpened(-X: Data,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+emphasis: Tk.Emphasis) -> InlineMachine<X>:
  match here emphasis:
    case At{state,frames,run} Tk.Emphasis{strong,raw,+text}: runInline(X,state,EmphasisText{run,Tk.Emphasis{strong,raw,text}} <> frames,Iterate{lexing(X,rules,links,text)})
def afterEmStrong(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+found: Maybe<&2,Tk.Emphasis>) -> InlineMachine<X>:
  match found:
    case Some{emphasis}: emphasisOpened(X,rules,links,here,emphasis)
    case None{}: afterCodespan(~X,~ext,rules,links,here,Tk.codespan(X,rules,runSrc(X,hereRun(X,here))))
# Where an emphasis opener may start, the run keeps its masked source from
# then on.
def maskedHere(-X: Data,+rules: Rules.Inline,+here: At<X>) -> At<X>:
  match here:
    case At{state,frames,Run{+src,masked,previous,keep,tokens}}: At{state,frames,Run{src,Tk.maskingFor(rules,Tk.opensEmphasis(rules,src),masked),previous,keep,tokens}}
def emStrongAt(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>) -> InlineMachine<X>:
  afterEmStrong(~X,~ext,rules,links,here,Tk.emStrong(rules,runSrc(X,hereRun(X,here)),runMasked(X,hereRun(X,here)),runPrevious(X,hereRun(X,here))))
def emStrongStage(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>) -> InlineMachine<X>:
  emStrongAt(~X,~ext,rules,links,maskedHere(X,rules,here))
# outputLink: the text is lexed as in a link (state.inLink) with no link
# emitted yet.
def linkOpened(-X: Data,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+link: Tk.LinkMatch,+fallback: Stage) -> InlineMachine<X>:
  match here link:
    case At{InlineState{_,+rawBlock,emitted},frames,run} Tk.LinkMatch{raw,href,title,label,image}:
      +text = Tk.outputLinkText(label)
      runInline(X,InlineState{True{},rawBlock,False{}},LinkText{run,Tk.LinkMatch{raw,href,title,label,image},text,emitted,rawBlock,fallback} <> frames,Iterate{lexing(X,rules,links,text)})
def textFromReference(-X: Data,+here: At<X>,+raw: String) -> InlineMachine<X>:
  match here:
    case At{state,frames,Run{src,masked,previous,keep,tokens}}: runInline(X,state,frames,Iterate{Run{Tk.drop(src,Tk.lengthOf(raw)),Tk.maskingAdvanced(masked,Tk.lengthOf(raw)),previous,keep,textJoined(X,tokens,raw,False{})}})
def afterReflink(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+found: Maybe<&2,Tk.RefStep>) -> InlineMachine<X>:
  match found:
    case Some{Tk.RefText{raw}}: textFromReference(X,here,raw)
    case Some{Tk.RefLink{link}}: linkOpened(X,rules,links,here,link,FromEmStrong{})
    case None{}: emStrongStage(~X,~ext,rules,links,here)
def reflinkStage(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>) -> InlineMachine<X>:
  afterReflink(~X,~ext,rules,links,here,Tk.reflink(rules,links,runSrc(X,hereRun(X,here))))
def afterLink(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+found: Maybe<&2,Tk.LinkMatch>) -> InlineMachine<X>:
  match found:
    case Some{link}: linkOpened(X,rules,links,here,link,FromReflink{})
    case None{}: reflinkStage(~X,~ext,rules,links,here)
# A tag opens or closes a link (`<a …>`, `</a>`) or a raw block (pre, code,
# kbd, script).
def tagState(+state: InlineState,+raw: String) -> InlineState:
  match state:
    case InlineState{+inLink,+rawBlock,emitted}:
      InlineState{Bool.pick(Unit -> Bool,Bool.not(inLink) && Tk.startATag(raw),_ => True{},_ => Bool.pick(Unit -> Bool,inLink && Tk.endATag(raw),_ => False{},_ => inLink)(Unit{}))(Unit{}),
        Bool.pick(Unit -> Bool,Bool.not(rawBlock) && Tk.startPreScriptTag(raw),_ => True{},_ => Bool.pick(Unit -> Bool,rawBlock && Tk.endPreScriptTag(raw),_ => False{},_ => rawBlock)(Unit{}))(Unit{}),emitted}
def tagged(-X: Data,+here: At<X>,+raw: String) -> InlineMachine<X>:
  match here:
    case At{state,frames,run}:
      +next = tagState(state,raw)
      pushedInline(X,next,frames,run,T.Tag{raw,inLinkOf(next),rawBlockOf(next),raw,False{}})
def afterTag(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+found: Maybe<&2,String>) -> InlineMachine<X>:
  match found:
    case Some{raw}: tagged(X,here,raw)
    case None{}: afterLink(~X,~ext,rules,links,here,Tk.link(rules,runSrc(X,hereRun(X,here))))
def afterEscape(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+found: Maybe<&2,T.Token<X>>) -> InlineMachine<X>:
  match found:
    case Some{token}: pushedHere(X,here,token)
    case None{}: afterTag(~X,~ext,rules,links,here,Tk.tag(rules,runSrc(X,hereRun(X,here))))
def afterInlineExtension(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+here: At<X>,+found: Maybe<&2,T.Token<X>>) -> InlineMachine<X>:
  match found:
    case Some{+token}: Bool.pick(Unit -> InlineMachine<X>,String.is_empty(T.rawOf(X,token)),_ => stoppedHere(X,here),_ => pushedHere(X,here,token))(Unit{})
    case None{}: afterEscape(~X,~ext,rules,links,here,Tk.escape(X,rules,runSrc(X,hereRun(X,here))))
def iterate(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+state: InlineState,+frames: List<&2,InlineFrame<X>>,+run: Run<X>) -> InlineMachine<X>:
  match run:
    case Run{Nil{},_,_,_,tokens}: InlineMachine{state,frames,GiveInline{tokens}}
    case Run{+src,masked,previous,+keep,tokens}: afterInlineExtension(~X,~ext,rules,links,At{state,frames,Run{src,masked,Bool.pick(Maybe<&2,U32>,keep,previous,None{}),False{},tokens}},inlineExtension(X,ext)(src))
def executeInline(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+state: InlineState,+frames: List<&2,InlineFrame<X>>,+task: InlineTask<X>) -> InlineMachine<X>:
  match task:
    case Iterate{run}: iterate(~X,~ext,rules,links,state,frames,run)
    case Resume{FromReflink{},run}: reflinkStage(~X,~ext,rules,links,At{state,frames,run})
    case Resume{FromEmStrong{},run}: emStrongStage(~X,~ext,rules,links,At{state,frames,run})
# outputLink after its text: a link whose text holds a link is none (the
# iteration continues with the next tokenizer).
def linkLexed(-X: Data,+state: InlineState,+frames: List<&2,InlineFrame<X>>,+run: Run<X>,+link: Tk.LinkMatch,+text: String,+emitted: Bool,+rawBlock: Bool,+fallback: Stage,+tokens: List<&2,T.Token<X>>) -> InlineMachine<X>:
  match state link:
    case InlineState{_,current,+hasLink} Tk.LinkMatch{raw,href,title,_,+image}:
      Bool.pick(Unit -> InlineMachine<X>,Bool.not(image) && hasLink,_ => runInline(X,InlineState{False{},rawBlock,emitted},frames,Resume{fallback,run}),
        _ => pushedInline(X,InlineState{False{},current,emitted || Bool.not(image)},frames,run,Bool.pick(Unit -> T.Token<X>,image,_ => T.Image{raw,href,title,text,tokens},_ => T.Link{raw,href,title,text,tokens})(Unit{})))(Unit{})
def resumeInline(-X: Data,+state: InlineState,+frames: List<&2,InlineFrame<X>>,+frame: InlineFrame<X>,+tokens: List<&2,T.Token<X>>) -> InlineMachine<X>:
  match frame:
    case LinkText{run,link,text,emitted,rawBlock,fallback}: linkLexed(X,state,frames,run,link,text,emitted,rawBlock,fallback,tokens)
    case EmphasisText{run,Tk.Emphasis{True{},raw,text}}: pushedInline(X,state,frames,run,T.Strong{raw,text,tokens})
    case EmphasisText{run,Tk.Emphasis{False{},raw,text}}: pushedInline(X,state,frames,run,T.Em{raw,text,tokens})
    case DelText{run,Tk.Delimited{raw,text}}: pushedInline(X,state,frames,run,T.Del{raw,text,tokens})
type InlineDone<-X: Data> is Data: InlineDone{tokens: List<&2,T.Token<X>>,state: InlineState}
# Runs inlineTokens calls until the outermost returns (every task consumes
# source or returns to a frame; not mechanized).
@unsafe def driveInline(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+machine: InlineMachine<X>) -> InlineDone<X>:
  match machine:
    case InlineMachine{state,Nil{},GiveInline{tokens}}: InlineDone{List.reverse(&2,T.Token<X>,tokens),state}
    case InlineMachine{state,frame <> frames,GiveInline{tokens}}: driveInline(~X,~ext,rules,links,resumeInline(X,state,frames,frame,List.reverse(&2,T.Token<X>,tokens)))
    case InlineMachine{state,frames,RunInline{task}}: driveInline(~X,~ext,rules,links,executeInline(~X,~ext,rules,links,state,frames,task))

# lex
# ---

# The queue's entries lexed in order, the state carrying over; `previous`
# is the entry before (the first is a placeholder).
def lexQueue(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+links: List<&2,T.LinkDefinition>,+entries: List<&2,String>,+previous: InlineDone<X>,+reversed: List<&2,List<&2,T.Token<X>>>) -> List<&2,List<&2,T.Token<X>>>:
  match entries previous:
    case Nil{} InlineDone{tokens,_}: List.drop(&2,List<&2,T.Token<X>>,List.reverse(&2,List<&2,T.Token<X>>,tokens <> reversed),1n)
    case entry <> rest InlineDone{tokens,state}: lexQueue(~X,~ext,rules,links,rest,driveInline(~X,~ext,rules,links,runInline(X,state,Nil{},Iterate{lexing(X,rules,links,entry)})),tokens <> reversed)

# Queue entries by index.
type Lexed<-X: Data> is Data:
  Leaf{}
  Node{left: Lexed<X>,index: Nat,tokens: List<&2,T.Token<X>>,right: Lexed<X>}
@unsafe def lexedTree(-X: Data,+entries: List<&2,List<&2,T.Token<X>>>,+first: Nat,+count: Nat) -> Lexed<X>:
  match count:
    case Zero{}: Leaf{}
    case Succ{_}:
      +middle = Nat.div(count,2n)
      +rest = List.drop(&2,List<&2,T.Token<X>>,entries,middle)
      Node{lexedTree(X,List.take(&2,List<&2,T.Token<X>>,entries,middle),first,middle),first + middle,Maybe.default(&2,List<&2,T.Token<X>>,List.head(&2,List<&2,T.Token<X>>,rest),Nil{}),lexedTree(X,List.drop(&2,List<&2,T.Token<X>>,rest,1n),first + middle + 1n,count - middle - 1n)}
def lexedAt(-X: Data,+tree: Lexed<X>,+index: Nat) -> List<&2,T.Token<X>>:
  match tree:
    case Leaf{}: Nil{}
    case Node{left,+at,tokens,right}: Bool.pick(Unit -> List<&2,T.Token<X>>,Nat.is_eq(index,at),_ => tokens,_ => Bool.pick(Unit -> List<&2,T.Token<X>>,Nat.is_lt(index,at),_ => lexedAt(X,left,index),_ => lexedAt(X,right,index))(Unit{}))(Unit{})

# Table rows as one list of cells and back.
def rowLengths(-X: Data,+rows: List<&2,List<&2,T.Token<X>>>) -> List<&2,Nat>:
  match rows:
    case Nil{}: Nil{}
    case row <> rest: List.length(&2,T.Token<X>,row) <> rowLengths(X,rest)
def regrouped(-X: Data,+lengths: List<&2,Nat>,+cells: List<&2,T.Token<X>>,+reversed: List<&2,List<&2,T.Token<X>>>) -> List<&2,List<&2,T.Token<X>>>:
  match lengths:
    case Nil{}: List.reverse(&2,List<&2,T.Token<X>>,reversed)
    case +length <> rest: regrouped(X,rest,List.drop(&2,T.Token<X>,cells,length),List.take(&2,T.Token<X>,cells,length) <> reversed)
def prependAll(-X: Data,+tokens: List<&2,T.Token<X>>,+reversed: List<&2,T.Token<X>>) -> List<&2,T.Token<X>>:
  match tokens:
    case Nil{}: reversed
    case token <> rest: prependAll(X,rest,token <> reversed)
# Each queued placeholder becomes its entry's tokens.
@unsafe def resolved(-X: Data,+lexed: Lexed<X>,+tokens: List<&2,T.Token<X>>,+reversed: List<&2,T.Token<X>>) -> List<&2,T.Token<X>>:
  match tokens:
    case Nil{}: List.reverse(&2,T.Token<X>,reversed)
    case T.Queued{index} <> rest: resolved(X,lexed,rest,prependAll(X,lexedAt(X,lexed,index),reversed))
    case T.Blockquote{raw,text,inner} <> rest: resolved(X,lexed,rest,T.Blockquote{raw,text,resolved(X,lexed,inner,Nil{})} <> reversed)
    case T.Heading{raw,depth,text,inner} <> rest: resolved(X,lexed,rest,T.Heading{raw,depth,text,resolved(X,lexed,inner,Nil{})} <> reversed)
    case T.ListToken{raw,ordered,start,loose,items} <> rest: resolved(X,lexed,rest,T.ListToken{raw,ordered,start,loose,resolved(X,lexed,items,Nil{})} <> reversed)
    case T.ListItem{raw,task,checked,loose,text,inner} <> rest: resolved(X,lexed,rest,T.ListItem{raw,task,checked,loose,text,resolved(X,lexed,inner,Nil{})} <> reversed)
    case T.Paragraph{raw,text,inner} <> rest: resolved(X,lexed,rest,T.Paragraph{raw,text,resolved(X,lexed,inner,Nil{})} <> reversed)
    case T.Table{raw,align,header,+rows} <> rest: resolved(X,lexed,rest,T.Table{raw,align,resolved(X,lexed,header,Nil{}),regrouped(X,rowLengths(X,rows),resolved(X,lexed,List.concat(&2,T.Token<X>,rows),Nil{}),Nil{})} <> reversed)
    case T.TableCell{text,inner,header,align} <> rest: resolved(X,lexed,rest,T.TableCell{text,resolved(X,lexed,inner,Nil{}),header,align} <> reversed)
    case T.Text{raw,text,inner,escaped} <> rest: resolved(X,lexed,rest,T.Text{raw,text,resolved(X,lexed,inner,Nil{}),escaped} <> reversed)
    case token <> rest: resolved(X,lexed,rest,token <> reversed)

def queueEntries(+queue: Queue) -> List<&2,String>:
  match queue: case Queue{entries,_}: List.reverse(&2,String,entries)
# `lex`'s result: the tokens and the document's reference definitions
# (marked's TokensList and its `links`).
type TokensList<-X: Data> is Data: TokensList{tokens: List<&2,T.Token<X>>,links: List<&2,T.LinkDefinition>}
def lexedBlocks(~X: Data,~ext: Extensions<X>,+rules: Rules.Inline,+done: BlockDone<X>) -> TokensList<X>:
  match done:
    case BlockDone{tokens,BlockState{_,+links,queue}}:
      +lexed = lexQueue(~X,~ext,rules,links,queueEntries(queue),InlineDone{Nil{},InlineState{False{},False{},False{}}},Nil{})
      TokensList{resolved(X,lexedTree(X,lexed,0n,List.length(&2,List<&2,T.Token<X>>,lexed)),tokens,Nil{}),List.reverse(&2,T.LinkDefinition,links)}
# The source's scalars after other.carriageReturn, `/\r\n|\r/g` → "\n".
def newlines(text: String,+reversed: List<&2,U32>) -> List<&2,U32>:
  match text:
    case SNil{}: List.reverse(&2,U32,reversed)
    case SCon{'\r',SCon{'\n',rest}}: newlines(rest,10 <> reversed)
    case SCon{'\r',rest}: newlines(rest,10 <> reversed)
    case SCon{Chr{code},rest}: newlines(rest,code <> reversed)

# A Marked instance (the grammar compiled once) and its lexer,
# `marked.lexer(src)`. Of marked's options only `breaks` varies here: GFM is
# on, pedantic mode off (marked's defaults).
type MarkedOptions is Data: MarkedOptions{breaks: Bool}
type Marked is Data: Marked{rules: Rules.Rules}
def withOptions(options: MarkedOptions) -> Marked:
  match options: case MarkedOptions{breaks}: Marked{Rules.rules(breaks)}
def new() -> Marked: withOptions(MarkedOptions{False{}})
def lex(~X: Data,~ext: Extensions<X>,+marked: Marked,+src: String) -> TokensList<X>:
  match marked:
    case Marked{Rules.Rules{+block,inline}}:
      lexedBlocks(~X,~ext,inline,driveBlock(~X,~ext,block,runBlock(X,BlockState{True{},Nil{},Queue{Nil{},0n}},Nil{},Blocks{newlines(src,Nil{}),False{},Nil{}})))
def inlineTokensOf(-X: Data,done: InlineDone<X>) -> List<&2,T.Token<X>>:
  match done: case InlineDone{tokens,_}: tokens
# `lexer.inlineTokens(src)` with the given reference definitions.
def lexInline(~X: Data,~ext: Extensions<X>,marked: Marked,+links: List<&2,T.LinkDefinition>,src: String) -> List<&2,T.Token<X>>:
  match marked:
    case Marked{Rules.Rules{_,+inline}}: inlineTokensOf(X,driveInline(~X,~ext,inline,links,runInline(X,InlineState{False{},False{},False{}},Nil{},Iterate{lexing(X,inline,links,src)})))
