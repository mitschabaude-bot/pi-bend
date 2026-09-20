import Base
import ./dns-name.bend as Name
import ./dns-message.bend as Message
import ./dns-response.bend as Response

# One table belongs to one transport connection. Tokens are caller-owned
# correlation values, not callbacks or mutable promises.
# Tickets are scoped to one session history. Serial numbers never wrap;
# an exhausted session must be replaced instead of reusing a cancellation key.
type Ticket is Data:
  Ticket{id: U32, serial: U32}

type Entry<-Token: Data> is Data:
  Entry{transaction: Response.Transaction, token: Token, ticket: Ticket}

type Pending<-Token: Data> is Data:
  Pending{entries: Map<&2, Entry<Token>>, next: Maybe<&2, U32>}

type RegistrationError is Data:
  InvalidId{}
  DuplicateId{}
  Exhausted{}

type Registered<-Token: Data> is Data:
  Registered{pending: Pending<Token>, result: Result<&2, &2, RegistrationError, Ticket>}

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
  Pending{Map.new(&2, Entry<Token>), Some{0}}

def nextSerial(last: Bool, value: U32) -> Maybe<&2, U32>:
  match last:
    case True{}: None{}
    case False{}: Some{(value + 1 : U32)}

def inserted(-Token: Data, +serial: U32, +ticket: Ticket, key: String, entry: Entry<Token>, pair: Map<&2, Entry<Token>> & Bool) -> Registered<Token>:
  match pair:
    case (entries, True{}): Registered{Pending{entries, Some{serial}}, Fail{DuplicateId{}}}
    case (entries, False{}): Registered{Pending{Map.set(&2, Entry<Token>, entries, key, entry), nextSerial(U32.is_eq(serial, 4294967295), serial)}, Done{ticket}}

def registerId(-Token: Data, valid: Bool, pending: Pending<Token>, +id: U32, transaction: Response.Transaction, token: Token) -> Registered<Token>:
  match valid pending:
    case False{} pending: Registered{pending, Fail{InvalidId{}}}
    case True{} Pending{entries, None{}}: Registered{Pending{entries, None{}}, Fail{Exhausted{}}}
    case True{} Pending{entries, Some{+serial}}: inserted(Token, serial, Ticket{id, serial}, Name.key(id), Entry{transaction, token, Ticket{id, serial}}, Map.has(&2, Entry<Token>, entries, Name.key(id)))

# Register before sending. Duplicate IDs never replace an outstanding query.
# Random ID allocation, retries and deadlines belong to the transport driver.
def register(-Token: Data, pending: Pending<Token>, transaction: Response.Transaction, token: Token) -> Registered<Token>:
  match transaction:
    case Response.Transaction{from, to, +id, opcode, question}: registerId(Token, U32.is_le(id, 65535), pending, id, Response.Transaction{from, to, id, opcode, question}, token)

def removed(-Token: Data, next: Maybe<&2, U32>, pair: Map<&2, Entry<Token>> & Maybe<&2, Entry<Token>>) -> Removed<Token>:
  match pair:
    case (entries, entry): Removed{Pending{entries, next}, entry}

def removeId(-Token: Data, valid: Bool, pending: Pending<Token>, id: U32) -> Removed<Token>:
  match valid pending:
    case False{} pending: Removed{pending, None{}}
    case True{} Pending{entries, next}: removed(Token, next, Map.pop(&2, Entry<Token>, entries, Name.key(id)))

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
    case Removed{remaining, Some{Entry{transaction, token, _}}}: decided(Token, original, remaining, token, Response.inspectStream(transaction, source, destination, wire))

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

# Connection-wide settlement returns every still-pending correlation exactly
# once to the driver. Ordering is deliberately not a request-order guarantee.
def values(-Token: Data, entries: List<&2, Sigma<&2, &2, String, _ => Entry<Token>>>, reversed: List<&2, Entry<Token>>) -> List<&2, Entry<Token>>:
  match entries:
    case Nil{}: List.reverse(&2, Entry<Token>, reversed)
    case (_, entry) <> rest: values(Token, rest, entry <> reversed)

def drain(-Token: Data, pending: Pending<Token>) -> List<&2, Entry<Token>>:
  match pending:
    case Pending{entries, _}: values(Token, Map.to_list(&2, Entry<Token>, entries), Nil{})


def cancelMatch(-Token: Data, equal: Bool, original: Pending<Token>, remaining: Pending<Token>, entry: Entry<Token>) -> Removed<Token>:
  match equal:
    case True{}: Removed{remaining, Some{entry}}
    case False{}: Removed{original, None{}}

def cancelled(-Token: Data, original: Pending<Token>, serial: U32, value: Removed<Token>) -> Removed<Token>:
  match value:
    case Removed{_, None{}}: Removed{original, None{}}
    case Removed{remaining, Some{Entry{transaction, token, Ticket{id, +actual}}}}: cancelMatch(Token, U32.is_eq(serial, actual), original, remaining, Entry{transaction, token, Ticket{id, actual}})

# Stale or repeated cancellation is a no-op, including after ID reuse. This
# does not retract bytes already sent or prevent an indistinguishable delayed
# DNS reply after wire-ID reuse; the higher-level transport owns reuse policy.
def cancel(-Token: Data, +pending: Pending<Token>, ticket: Ticket) -> Removed<Token>:
  match ticket:
    case Ticket{id, serial}: cancelled(Token, pending, serial, remove(Token, pending, id))
