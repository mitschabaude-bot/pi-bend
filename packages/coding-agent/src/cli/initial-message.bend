import Base
import ../../../ai/src/types.bend as Ai

# upstream cli/initial-message.ts: stdin content, @file text and the first
# CLI message form one initial prompt for non-interactive mode. Upstream
# shifts the first message off `parsed.messages`; the remaining messages are
# returned instead.

type InitialMessage is Data:
  InitialMessage{text: Maybe<&2, String>, images: List<&2, Ai.ImageContent>, remaining: List<&2, String>}

def joined(parts: List<&2, String>) -> Maybe<&2, String>:
  match parts:
    case Nil{}: None{}
    case values: Some{String.join(values, "")}

def optionalPart(value: Maybe<&2, String>, +rest: List<&2, String>) -> List<&2, String>:
  match value:
    case None{}: rest
    case Some{text}: text <> rest

# Empty file text adds nothing (upstream `if (fileText)`); stdin content is
# added whenever it is present.
def nonEmpty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SNil{}}: None{}
    case other: other

def initialFrom(+stdin: Maybe<&2, String>, +file: Maybe<&2, String>, +images: List<&2, Ai.ImageContent>, messages: List<&2, String>) -> InitialMessage:
  match messages:
    case Nil{}: InitialMessage{joined(optionalPart(stdin, optionalPart(file, Nil{}))), images, Nil{}}
    case first <> rest: InitialMessage{joined(optionalPart(stdin, optionalPart(file, [first]))), images, rest}

def buildInitialMessage(stdin: Maybe<&2, String>, fileText: Maybe<&2, String>, images: List<&2, Ai.ImageContent>, messages: List<&2, String>) -> InitialMessage:
  initialFrom(stdin, nonEmpty(fileText), images, messages)
