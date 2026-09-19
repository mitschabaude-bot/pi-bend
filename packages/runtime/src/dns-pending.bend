import Base
import ./dns-name.bend as Name
import ./dns-message.bend as Message
import ./dns-response.bend as Response

# One table belongs to one transport connection. Tokens are caller-owned
# correlation values, not callbacks or mutable promises.
type Entry<-Token: Data> is Data:
  Entry{transaction: Response.Transaction, token: Token}

type Pending<-Token: Data> is Data:
  Pending{entries: Map<&2, Entry<Token>>}

type RegistrationError is Data:
  InvalidId{}
  DuplicateId{}

type Registered<-Token: Data> is Data:
  Registered{pending: Pending<Token>, result: Result<&2, &2, RegistrationError, Unit>}

type Rejection is Data:
  MissingId{}
  UnknownId{id: U32}
  Mismatch{reason: Response.Rejection}

type Delivery<-Token: Data> is Data:
  Ignored{reason: Rejection}
  Answer{token: Token, message: Message.Message}
  Truncated{token: Token, header: Message.Header}

type Received<-Token: Data> is Data:
  Received{pending: Pending<Token>, delivery: Delivery<Token>}

type Removed<-Token: Data> is Data:
  Removed{pending: Pending<Token>, entry: Maybe<&2, Entry<Token>>}

def new(-Token: Data) -> Pending<Token>:
  Pending{Map.new(&2, Entry<Token>)}

def inserted(-Token: Data, key: String, entry: Entry<Token>, pair: Map<&2, Entry<Token>> & Bool) -> Registered<Token>:
  match pair:
    case (entries, True{}): Registered{Pending{entries}, Fail{DuplicateId{}}}
    case (entries, False{}): Registered{Pending{Map.set(&2, Entry<Token>, entries, key, entry)}, Done{Unit{}}}

def registerId(-Token: Data, valid: Bool, pending: Pending<Token>, +id: U32, entry: Entry<Token>) -> Registered<Token>:
  match valid pending:
    case False{} pending: Registered{pending, Fail{InvalidId{}}}
    case True{} Pending{entries}: inserted(Token, Name.key(id), entry, Map.has(&2, Entry<Token>, entries, Name.key(id)))

# Register before sending. Duplicate IDs never replace an outstanding query.
# Random ID allocation, retries and deadlines belong to the transport driver.
def register(-Token: Data, pending: Pending<Token>, transaction: Response.Transaction, token: Token) -> Registered<Token>:
  match transaction:
    case Response.Transaction{from, to, +id, opcode, question}: registerId(Token, U32.is_le(id, 65535), pending, id, Entry{Response.Transaction{from, to, id, opcode, question}, token})

def removed(-Token: Data, pair: Map<&2, Entry<Token>> & Maybe<&2, Entry<Token>>) -> Removed<Token>:
  match pair:
    case (entries, entry): Removed{Pending{entries}, entry}

def removeId(-Token: Data, valid: Bool, pending: Pending<Token>, id: U32) -> Removed<Token>:
  match valid pending:
    case False{} pending: Removed{pending, None{}}
    case True{} Pending{entries}: removed(Token, Map.pop(&2, Entry<Token>, entries, Name.key(id)))

# The owner serializes registration/removal; an ID alone is not a capability
# for cancelling a later query after that ID has been reused.
def remove(-Token: Data, pending: Pending<Token>, +id: U32) -> Removed<Token>:
  removeId(Token, U32.is_le(id, 65535), pending, id)

def decided(-Token: Data, original: Pending<Token>, remaining: Pending<Token>, token: Token, decision: Response.Decision) -> Received<Token>:
  match decision:
    case Response.Ignore{reason}: Received{original, Ignored{Mismatch{reason}}}
    case Response.Matched{message}: Received{remaining, Answer{token, message}}
    case Response.Truncated{header}: Received{remaining, Truncated{token, header}}

def selected(-Token: Data, original: Pending<Token>, id: U32, source: Response.Endpoint, destination: Response.Endpoint, wire: List<&2, U32>, value: Removed<Token>) -> Received<Token>:
  match value:
    case Removed{_, None{}}: Received{original, Ignored{UnknownId{id}}}
    case Removed{remaining, Some{Entry{transaction, token}}}: decided(Token, original, remaining, token, Response.inspectStream(transaction, source, destination, wire))

def identified(-Token: Data, valid: Bool, +pending: Pending<Token>, +id: U32, source: Response.Endpoint, destination: Response.Endpoint, wire: List<&2, U32>) -> Received<Token>:
  match valid:
    case False{}: Received{pending, Ignored{MissingId{}}}
    case True{}: selected(Token, pending, id, source, destination, wire, remove(Token, pending, id))

# Read only the two ID octets to choose the expected transaction. The existing
# matcher then validates the complete response once. Ignored frames leave the
# table unchanged; accepted replies/truncation settle precisely one entry.
def receive(-Token: Data, pending: Pending<Token>, source: Response.Endpoint, destination: Response.Endpoint, wire: List<&2, U32>) -> Received<Token>:
  match wire:
    case +high <> +low <> rest: identified(Token, U32.is_le(high, 255) && U32.is_le(low, 255), pending, ((high * 256) + low : U32), source, destination, high <> low <> rest)
    case _: Received{pending, Ignored{MissingId{}}}
