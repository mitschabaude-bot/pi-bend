import Base
import ./http-head.bend as Head
import ./http-body.bend as Body
import ./http-chunked-body.bend as Chunked
import ./http-response-policy.bend as Policy
import ./http-header.bend as H
import ./http-response-termination.bend as Termination

type Limits is Data:
  Limits{headLineBytes: Nat, headBytes: Nat, headFields: Nat, informationalHeads: Nat, body: Chunked.Limits}

type Context is Data:
  Context{method: String, limits: Limits, remainingInformational: Nat, resetEOF: Bool}

type Phase is Data:
  ReadingHead{reader: Head.Reader}
  ReadingBody{reader: Body.Reader, expose: Bool}

type Reader is Data:
  Reader{phase: Phase, context: Context}

type Event is Data:
  InformationalHead{head: Head.ResponseHead}
  FinalHead{head: Head.ResponseHead, exposeBody: Bool}
  BodyData{bytes: List<&2, U32>}
  Completed{trailers: List<&2, H.Header>}

type ReadError is Data:
  HeadError{error: Head.ReadError}
  PolicyError{error: Policy.PolicyError}
  BodyError{error: Body.BodyError}
  TooManyInformational{}
  IncompleteResponse{}

type ReadResult is Data:
  More{reader: Reader, events: List<&2, Event>}
  Complete{events: List<&2, Event>, rest: List<&2, U32>}
  Failed{error: ReadError, events: List<&2, Event>}

def headReader(limits: Limits) -> Head.Reader:
  match limits:
    case Limits{line, bytes, fields, _, _}: Head.new(line, bytes, fields)

def bodyReader(framing: Body.Framing, limits: Limits) -> Body.Reader:
  match limits:
    case Limits{_, _, _, _, body}: Body.new(framing, body)

def new(method: String, +limits: Limits) -> Reader:
  match limits:
    case Limits{_, _, _, info, _}: Reader{ReadingHead{headReader(limits)}, Context{method, limits, info, False{}}}

type ScanState is Data:
  Running{reader: Reader, reversed: List<&2, Event>}
  Broken{error: ReadError, reversed: List<&2, Event>}

def informational(head: Head.ResponseHead, context: Context, reversed: List<&2, Event>) -> ScanState:
  match context:
    case Context{_, _, Zero{}, _}: Broken{TooManyInformational{}, reversed}
    case Context{method, +limits, Succ{remaining}, _}:
      Running{Reader{ReadingHead{headReader(limits)}, Context{method, limits, remaining, False{}}}, InformationalHead{head} <> reversed}

def planned(result: Result<&2, &2, Policy.PolicyError, Policy.ResponsePlan>, +head: Head.ResponseHead, context: Context, reversed: List<&2, Event>) -> ScanState:
  match result context:
    case Fail{error} _: Broken{PolicyError{error}, reversed}
    case Done{Policy.Informational{}} value: informational(head, value, reversed)
    case Done{Policy.Final{+framing, +expose}} Context{method, +limits, remaining, _}:
      Running{Reader{ReadingBody{bodyReader(framing, limits), expose}, Context{method, limits, remaining, Termination.allowsReset(framing, head)}}, FinalHead{head, expose} <> reversed}

def completedHead(+head: Head.ResponseHead, context: Context, reversed: List<&2, Event>) -> ScanState:
  match context:
    case Context{+method, limits, remaining, _}:
      planned(Policy.plan(method, head), head, Context{method, limits, remaining, False{}}, reversed)

def consumedHead(result: Head.ReadResult, context: Context, reversed: List<&2, Event>) -> ScanState:
  match result:
    case Head.Failed{error}: Broken{HeadError{error}, reversed}
    case Head.More{reader}: Running{Reader{ReadingHead{reader}, context}, reversed}
    # This helper receives only one byte, so a completed head has no remainder.
    case Head.Complete{head, _}: completedHead(head, context, reversed)

def emitted(expose: Bool, bytes: List<&2, U32>, reversed: List<&2, Event>) -> List<&2, Event>:
  match expose bytes:
    case False{} _: reversed
    case True{} Nil{}: reversed
    case True{} head <> rest: BodyData{head <> rest} <> reversed

def consumedBody(result: Body.ReadResult, +expose: Bool, context: Context, reversed: List<&2, Event>) -> ReadResult:
  match result:
    case Body.More{reader, bytes}: More{Reader{ReadingBody{reader, expose}, context}, List.reverse(&2, Event, emitted(expose, bytes, reversed))}
    case Body.Complete{bytes, trailers, rest}: Complete{List.reverse(&2, Event, Completed{trailers} <> emitted(expose, bytes, reversed)), rest}
    case Body.Failed{error, bytes}: Failed{BodyError{error}, List.reverse(&2, Event, emitted(expose, bytes, reversed))}

# Heads advance bytewise to allow informational resets. Once a body starts,
# hand the whole remaining chunk to its decoder, avoiding per-byte data events.
def collect(bytes: List<&2, U32>, state: ScanState) -> ReadResult:
  match bytes state:
    case _ Broken{error, reversed}: Failed{error, List.reverse(&2, Event, reversed)}
    case input Running{Reader{ReadingBody{reader, expose}, context}, reversed}: consumedBody(Body.read(reader, input), expose, context, reversed)
    case Nil{} Running{reader, reversed}: More{reader, List.reverse(&2, Event, reversed)}
    case byte <> rest Running{Reader{ReadingHead{reader}, context}, reversed}:
      collect(rest, consumedHead(Head.read(reader, byte <> Nil{}), context, reversed))

def read(reader: Reader, bytes: List<&2, U32>) -> ReadResult:
  collect(bytes, Running{reader, Nil{}})

def bodyEOF(result: Result<&2, &2, Body.BodyError, Unit>) -> ReadResult:
  match result:
    case Done{_}: Complete{Completed{Nil{}} <> Nil{}, Nil{}}
    case Fail{error}: Failed{BodyError{error}, Nil{}}

# Finish on clean EOF or a reset admitted by the retained HTTP framing policy.
# Abort and unrelated transport errors must remain failures.
def finish(reader: Reader) -> ReadResult:
  match reader:
    case Reader{ReadingHead{_}, _}: Failed{IncompleteResponse{}, Nil{}}
    case Reader{ReadingBody{body, _}, _}: bodyEOF(Body.finish(body))

# Computed once when the final head is parsed, not by rescanning headers for
# each body chunk. Before a final response head, reset cannot finish a message.
def permitsResetEOF(reader: Reader) -> Bool:
  match reader:
    case Reader{_, Context{_, _, _, allowed}}: allowed
