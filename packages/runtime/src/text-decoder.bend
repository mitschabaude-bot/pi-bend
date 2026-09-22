import Base
import ./utf8.bend as Utf8
import ./utf16.bend as Utf16

# Incremental file-text decoding: UTF-8 by default, UTF-16 only with a BOM.
# Surrogates and partial sequences are validated even when a consumer already
# found its requested match. Output is emitted as soon as a scalar completes.
type Mode is Data:
  Starting{}
  Probe{first: U32}
  UTF8{pending: Utf8.Pending,bomSeen: Bool}
  UTF16{little: Bool,byte: Maybe<&2,U32>,high: Maybe<&2,U32>}
type Decoder is Data:
  Decoder{mode: Mode,offset: Nat}
type Error is Data:
  InvalidByte{offset: Nat,value: U32}
  InvalidEncoding{offset: Nat}
  IncompleteEncoding{offset: Nat}
type Fragment is Data:
  Fragment{mode: Mode,point: Maybe<&2,Char>}
type Step is Data:
  Step{decoder: Decoder,point: Maybe<&2,Char>}
type Decoded is Data:
  Decoded{decoder: Decoder,text: String}

def create() -> Decoder: Decoder{Starting{},Zero{}}

def utf8Emitted(step: Utf8.ByteStep,+bomSeen: Bool) -> Fragment:
  match step:
    case Utf8.ByteStep{pending,+point <> Nil{}}: Fragment{UTF8{pending,True{}},Bool.pick(Maybe<&2,Char>,Bool.not(bomSeen) && U32.is_eq(point,65279),None{},Some{Chr{point}})}
    case Utf8.ByteStep{pending,_}: Fragment{UTF8{pending,bomSeen},None{}}
def utf8(+pending: Utf8.Pending,bomSeen: Bool,+byte: U32) -> Result<&2,&2,Unit,Fragment>:
  Bool.pick(Result<&2,&2,Unit,Fragment>,Utf8.valid(pending,byte),Done{utf8Emitted(Utf8.consume(pending,byte),bomSeen)},Fail{Unit{}})

def unit(+little: Bool,high: Maybe<&2,U32>,+value: U32) -> Result<&2,&2,Unit,Fragment>:
  match high:
    case None{}:
      Bool.pick(Unit -> Result<&2,&2,Unit,Fragment>,Utf16.lowSurrogate(value),_ => Fail{Unit{}},
        _ => Done{Bool.pick(Unit -> Fragment,Utf16.highSurrogate(value),_ => Fragment{UTF16{little,None{},Some{value}},None{}},_ => Fragment{UTF16{little,None{},None{}},Some{Chr{value}}})(Unit{})})(Unit{})
    case Some{high}:
      Bool.pick(Unit -> Result<&2,&2,Unit,Fragment>,Utf16.lowSurrogate(value),_ => Done{Fragment{UTF16{little,None{},None{}},Some{Chr{(65536 + (high - 55296) * 1024 + value - 56320 : U32)}}}},_ => Fail{Unit{}})(Unit{})

def consume(mode: Mode,+byte: U32) -> Result<&2,&2,Unit,Fragment>:
  match mode:
    case Starting{}:
      Bool.pick(Unit -> Result<&2,&2,Unit,Fragment>,U32.is_eq(byte,255) || U32.is_eq(byte,254),_ => Done{Fragment{Probe{byte},None{}}},_ => utf8(Utf8.Ready{},False{},byte))(Unit{})
    case Probe{+first}:
      Bool.pick(Result<&2,&2,Unit,Fragment>,U32.is_eq((first + byte : U32),509) && Bool.not(U32.is_eq(first,byte)),Done{Fragment{UTF16{U32.is_eq(first,255),None{},None{}},None{}}},Fail{Unit{}})
    case UTF8{pending,bomSeen}: utf8(pending,bomSeen,byte)
    case UTF16{little,None{},high}: Done{Fragment{UTF16{little,Some{byte},high},None{}}}
    case UTF16{+little,Some{+first},high}: unit(little,high,Bool.pick(U32,little,(first + U32.shln(byte,8n) : U32),(U32.shln(first,8n) + byte : U32)))

def consumed(offset: Nat,result: Result<&2,&2,Unit,Fragment>) -> Result<&2,&2,Error,Step>:
  match result:
    case Fail{_}: Fail{InvalidEncoding{offset}}
    case Done{Fragment{mode,point}}: Done{Step{Decoder{mode,Succ{offset}},point}}
def step(decoder: Decoder,+byte: U32) -> Result<&2,&2,Error,Step>:
  match decoder:
    case Decoder{mode,+offset}: Bool.pick(Unit -> Result<&2,&2,Error,Step>,U32.is_le(byte,255),_ => consumed(offset,consume(mode,byte)),_ => Fail{InvalidByte{offset,byte}})(Unit{})

def finish(decoder: Decoder) -> Result<&2,&2,Error,Unit>:
  match decoder:
    case Decoder{Starting{},_}: Done{Unit{}}
    case Decoder{UTF8{Utf8.Ready{},_},_}: Done{Unit{}}
    case Decoder{UTF16{_,None{},None{}},_}: Done{Unit{}}
    case Decoder{_,offset}: Fail{IncompleteEncoding{offset}}

def prepend(point: Maybe<&2,Char>,reversed: String) -> String:
  match point:
    case None{}: reversed
    case Some{char}: SCon{char,reversed}

def chunk(bytes: List<&2,U32>,result: Result<&2,&2,Error,Step>,reversed: String) -> Result<&2,&2,Error,Decoded>:
  match bytes result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{Step{decoder,point}}: Done{Decoded{decoder,String.reverse(prepend(point,reversed))}}
    case byte <> rest Done{Step{decoder,point}}: chunk(rest,step(decoder,byte),prepend(point,reversed))

def feed(bytes: List<&2,U32>,decoder: Decoder) -> Result<&2,&2,Error,Decoded>:
  chunk(bytes,Done{Step{decoder,None{}}},"")
