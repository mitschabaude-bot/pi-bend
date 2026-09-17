import Base
import ../types.bend as T
import ../../../runtime/src/ref.bend as Ref
import ../../../runtime/src/record.bend as Record

# The upstream helper accepts every content kind, extracting only text blocks.
type Content<-Arguments: Data> is Data:
  TextBlock{value: T.TextContent}
  ImageBlock{value: T.ImageContent}
  ThinkingBlock{value: T.ThinkingContent}
  ToolCallBlock{value: T.ToolCall<Arguments>}

type ContentInput<-Arguments: Data> is Data:
  ContentString{value: String}
  ContentBlocks{values: List<&2, Content<Arguments>>}

def textBlocks(-A: Data, blocks: List<&2, Content<A>>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case TextBlock{T.TextContent{text, _}} <> rest: text <> textBlocks(A, rest)
    case _ <> rest: textBlocks(A, rest)

def contentText(-A: Data, content: ContentInput<A>, separator: String) -> String:
  match content:
    case ContentString{value}: value
    case ContentBlocks{blocks}: String.join(textBlocks(A, blocks), separator)

def contentTextDefault(-A: Data, content: ContentInput<A>) -> String:
  contentText(A, content, "\n")

def systemBlocks(blocks: List<&2, T.TextContent>) -> List<&2, String>:
  match blocks:
    case Nil{}: Nil{}
    case T.TextContent{text, _} <> rest: text <> systemBlocks(rest)

def systemContentText(content: T.SystemContent) -> String:
  match content:
    case T.SystemText{value}: value
    case T.SystemBlocks{blocks}: String.join(systemBlocks(blocks), "\n")

def sectionEntries(sections: Maybe<&2, Record.Record<Maybe<&2, String>>>) -> List<&2, Record.Property<Maybe<&2, String>>>:
  match sections:
    case None{}: Nil{}
    case Some{record}: Record.entries(Maybe<&2, String>, record)

def sectionValues(properties: List<&2, Record.Property<Maybe<&2, String>>>) -> List<&2, String>:
  match properties:
    case Nil{}: Nil{}
    case Record.Property{_, None{}} <> rest: sectionValues(rest)
    case Record.Property{_, Some{text}} <> rest: text <> sectionValues(rest)

def nonEmpty(parts: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}: Nil{}
    case +head <> rest:
      +tail = nonEmpty(rest)
      Bool.pick(List<&2, String>, String.is_empty(head), tail, head <> tail)

def renderComplete(-P: Data, message: T.SystemMessage<P>) -> String:
  match message:
    case T.SystemMessage{content, sections, _, _, _}: String.join(nonEmpty(systemContentText(content) <> sectionValues(sectionEntries(sections))), "\n\n")

def getSystemMessageText(-P: Data, message: Ref.Ref<T.SystemMessage<P>>) -> IO(String):
  do IO<String>:
    value : T.SystemMessage<P> <- Ref.read(T.SystemMessage<P>, message)
    return renderComplete(P, value)

def sectionUpdates(properties: List<&2, Record.Property<Maybe<&2, String>>>) -> List<&2, String>:
  match properties:
    case Nil{}: Nil{}
    case Record.Property{name, None{}} <> rest: String.join("Removed system prompt section \"" <> name <> "\"." <> Nil{}, "") <> sectionUpdates(rest)
    case Record.Property{name, Some{value}} <> rest: String.join("Updated system prompt section \"" <> name <> "\":\n\n" <> value <> Nil{}, "") <> sectionUpdates(rest)

def renderUpdate(-P: Data, message: T.SystemMessage<P>) -> String:
  match message:
    case T.SystemMessage{content, sections, _, _, _}: String.join(List.append(&2, String, nonEmpty(systemContentText(content) <> Nil{}), sectionUpdates(sectionEntries(sections))), "\n\n")

def renderSystemMessageUpdate(-P: Data, message: Ref.Ref<T.SystemMessage<P>>) -> IO(String):
  do IO<String>:
    value : T.SystemMessage<P> <- Ref.read(T.SystemMessage<P>, message)
    return renderUpdate(P, value)
