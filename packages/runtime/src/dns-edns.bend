import Base
import ./dns-message.bend as Message
import ./dns-tcp-frame.bend as Frame

# EDNS(0) request fields. Unknown option codes and duplicate options are
# preserved in order; interpreting individual option payloads is separate.
type Option is Data:
  Option{code: U32, data: List<&2, U32>}

type Query is Data:
  Query{payloadSize: U32, dnssecOk: Bool, options: List<&2, Option>}

type Error is Data:
  InvalidField{}
  InvalidByte{value: U32}
  TooLong{}
  Message{error: Message.Error}

type Buffer is Data:
  Buffer{size: U32, reversed: List<&2, U32>}

def measured(result: Result<&2, &2, Frame.Error, U32>) -> Result<&2, &2, Error, U32>:
  match result:
    case Done{size}: Done{size}
    case Fail{Frame.InvalidByte{value}}: Fail{InvalidByte{value}}
    case Fail{_}: Fail{TooLong{}}

def prepend(reversed: List<&2, U32>, tail: List<&2, U32>) -> List<&2, U32>:
  match reversed:
    case Nil{}: tail
    case byte <> rest: prepend(rest, byte <> tail)

# Inputs to append have already been measured and checked as octets.
def append(bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: reversed
    case byte <> rest: append(rest, byte <> reversed)

def optionFits(fits: Bool, code: U32, +length: U32, data: List<&2, U32>, size: U32, reversed: List<&2, U32>) -> Result<&2, &2, Error, Buffer>:
  match fits:
    case False{}: Fail{TooLong{}}
    case True{}: Done{Buffer{(size + length + 4 : U32), append(data, append(Message.u16(code, Message.u16(length, Nil{})), reversed))}}

def optionSize(code: U32, data: List<&2, U32>, buffer: Buffer, result: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, Buffer>:
  match buffer result:
    case _ Fail{error}: Fail{error}
    case Buffer{+size, reversed} Done{+length}: optionFits(U32.is_le((size + length + 4 : U32), 65535), code, length, data, size, reversed)

def optionCode(valid: Bool, code: U32, +data: List<&2, U32>, buffer: Buffer) -> Result<&2, &2, Error, Buffer>:
  match valid:
    case False{}: Fail{InvalidField{}}
    case True{}: optionSize(code, data, buffer, measured(Frame.count(data, Done{0})))

def add(option: Option, buffer: Buffer) -> Result<&2, &2, Error, Buffer>:
  match option:
    case Option{+code, data}: optionCode(U32.is_le(code, 65535), code, data, buffer)

def options(values: List<&2, Option>, result: Result<&2, &2, Error, Buffer>) -> Result<&2, &2, Error, Buffer>:
  match values result:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case value <> rest Done{buffer}: options(rest, add(value, buffer))

def record(payloadSize: U32, dnssecOk: Bool, result: Result<&2, &2, Error, Buffer>) -> Result<&2, &2, Error, List<&2, U32>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Buffer{size, reversed}}:
      Done{0 <> 0 <> 41 <> Message.u16(payloadSize, 0 <> 0 <> Bool.pick(U32, dnssecOk, 128, 0) <> 0 <> Message.u16(size, List.reverse(&2, U32, reversed)))}

def recordFields(valid: Bool, payloadSize: U32, dnssecOk: Bool, values: List<&2, Option>) -> Result<&2, &2, Error, List<&2, U32>>:
  match valid:
    case False{}: Fail{InvalidField{}}
    case True{}: record(payloadSize, dnssecOk, options(values, Done{Buffer{0, Nil{}}}))

# OPT uses the root owner, type 41, advertised payload in CLASS, version zero,
# zero extended RCODE and no reserved flag bits. Only the DO bit is settable.
def encode(value: Query) -> Result<&2, &2, Error, List<&2, U32>>:
  match value:
    case Query{+payloadSize, dnssecOk, values}: recordFields(U32.is_le(payloadSize, 65535), payloadSize, dnssecOk, values)

def bounded(bytes: List<&2, U32>, size: Result<&2, &2, Error, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match size:
    case Fail{error}: Fail{error}
    case Done{_}: Done{bytes}

def counted(+bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  bounded(bytes, measured(Frame.count(bytes, Done{0})))

# Input is the validated single-question message emitted by Message.query.
# Replace ARCOUNT, append one OPT record and enforce the full message bound.
def attach(remaining: Nat, bytes: List<&2, U32>, reversed: List<&2, U32>, opt: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match remaining bytes:
    case Zero{} _ <> _ <> body: counted(prepend(reversed, 0 <> 1 <> prepend(List.reverse(&2, U32, body), opt)))
    case Succ{rest} byte <> tail: attach(rest, tail, byte <> reversed, opt)
    case _ _: Fail{InvalidField{}}

def encoded(message: Result<&2, &2, Message.Error, List<&2, U32>>, opt: Result<&2, &2, Error, List<&2, U32>>) -> Result<&2, &2, Error, List<&2, U32>>:
  match message opt:
    case Fail{error} _: Fail{Message{error}}
    case Done{_} Fail{error}: Fail{error}
    case Done{bytes} Done{optBytes}: attach(10n, bytes, Nil{}, optBytes)

def query(id: U32, flags: U32, question: Message.Question, extension: Query) -> Result<&2, &2, Error, List<&2, U32>>:
  encoded(Message.query(id, flags, question), encode(extension))
