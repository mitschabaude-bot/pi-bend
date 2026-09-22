import Base
import ./tls13-handshake.bend as H
import ./tls13-record.bend as R
import ./sha256.bend as SHA
import ./x509.bend as X509

# A connection owns both traffic epochs and its certificate authorizer. The
# authorizer must check the chain and intended identity; there is no implicit
# trust policy. Input is arbitrary socket chunks. TLS records and handshake
# messages are buffered independently with explicit size bounds. Failure consumes the connection and its sequence numbers.
type Error is Data:
  HandshakeFailure{cause: H.Error}
  RecordFailure{cause: R.Error}
  FramingFailure{cause: H.FramingError}
  UnexpectedMessage{}
  PeerAlert{description: U32}

type Authorization is Type:
  Authorization{check: List<&2, X509.Certificate> -> Result<&2, &2, X509.Error, X509.PublicKey>}

type Authentication is Type:
  Extensions{authorization: Authorization}
  Certificate{authorization: Authorization, parameters: H.Parameters}
  Verify{key: X509.PublicKey, parameters: H.Parameters}
  Finished{parameters: H.Parameters}

type Phase is Type:
  Hello{pending: H.Pending, authorization: Authorization}
  Authenticating{handshake: H.Handshake, expected: Authentication}
  Connected{write: Maybe<&1, R.Traffic>, read: Maybe<&1, R.Traffic>, clientSecret: List<&2, U32>, serverSecret: List<&2, U32>, parameters: H.Parameters}

type RecordBuffer is Data:
  RecordHeader{reverse: List<&2, U32>, needed: U32}
  RecordBody{reverse: List<&2, U32>, remaining: U32}

def emptyInput() -> RecordBuffer:
  RecordHeader{Nil{}, 5}

type Client is Type:
  Client{phase: Phase, fragments: H.Buffer, messageLimit: U32, input: RecordBuffer}

type Step is Type:
  Step{client: Client, outgoing: List<&2, List<&2, U32>>, incoming: List<&2, List<&2, U32>>}

def checked(-A: Data, result: Result<&2, &2, H.Error, A>) -> Result<&2, &1, Error, A>:
  match result:
    case Fail{cause}: Fail{HandshakeFailure{cause}}
    case Done{value}: Done{value}

def require(valid: Bool) -> Result<&2, &1, Error, Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{UnexpectedMessage{}}

def started(authorization: Authorization, limit: U32, result: Result<&2, &1, H.Error, H.Started>) -> Result<&2, &1, Error, Step>:
  match result:
    case Fail{cause}: Fail{HandshakeFailure{cause}}
    case Done{H.Started{pending, record}}:
      Done{Step{Client{Hello{pending, authorization}, H.emptyBuffer(), limit, emptyInput()}, record <> Nil{}, Nil{}}}

def initialize(name: Maybe<&2, String>, entropy: List<&2, U32>, authorization: Authorization, limit: U32) -> Result<&2, &1, Error, Step>:
  started(authorization, limit, H.initialize(name, entropy))

def start(name: Maybe<&2, String>, authorization: Authorization, limit: U32) -> IO(Result<&2, &1, Error, Step>):
  do IO<Result<&2, &1, Error, Step>>:
    result : Result<&2, &1, H.Error, H.Started> <- H.start(name)
    IO.pure(Result<&2, &1, Error, Step>, started(authorization, limit, result))

def parsedCertificates(bytes: List<&2, List<&2, U32>>, reversed: List<&2, X509.Certificate>) -> Result<&2, &2, X509.Error, List<&2, X509.Certificate>>:
  match bytes:
    case Nil{}: Done{List.reverse(&2, X509.Certificate, reversed)}
    case head <> rest:
      Result.bind(&2, &2, X509.Error, X509.Certificate, List<&2, X509.Certificate>, X509.parse(head), cert => parsedCertificates(rest, cert <> reversed))

def authorized(authorization: Authorization, chain: List<&2, List<&2, U32>>) -> Result<&2, &1, Error, X509.PublicKey>:
  match authorization:
    case Authorization{check}:
      checked(X509.PublicKey, H.certificateResult(X509.PublicKey,
        Result.bind(&2, &2, X509.Error, List<&2, X509.Certificate>, X509.PublicKey, parsedCertificates(chain, Nil{}), check)))

def parametersAccepted(authorization: Authorization, result: Result<&2, &1, H.Error, H.ServerParameters>) -> Result<&2, &1, Error, Phase>:
  match result:
    case Fail{cause}: Fail{HandshakeFailure{cause}}
    case Done{H.ServerParameters{handshake, parameters}}: Done{Authenticating{handshake, Certificate{authorization, parameters}}}

# Only these transitions update the transcript. In particular, untrusted
# certificates and failed signatures cannot advance to Finished.
def authenticate(handshake: H.Handshake, expected: Authentication, +wire: List<&2, U32>) -> Result<&2, &1, Error, Phase>:
  match handshake expected:
    case handshake Extensions{authorization}:
      parametersAccepted(authorization, H.acceptEncryptedExtensions(handshake, wire))
    case H.Handshake{name, +transcript, secret, client, server, write, read} Certificate{authorization, parameters}:
      Result.bind(&2, &1, Error, List<&2, List<&2, U32>>, Phase, checked(List<&2, List<&2, U32>>, H.certificates(wire)), chain =>
        Result.bind(&2, &1, Error, X509.PublicKey, Phase, authorized(authorization, chain), key =>
          Result.bind(&2, &1, Error, SHA.State, Phase, checked(SHA.State, H.hashResult(SHA.State, SHA.update(wire, transcript))), updated =>
            Done{Authenticating{H.Handshake{name, updated, secret, client, server, write, read}, Verify{key, parameters}}})))
    case H.Handshake{name, transcript, secret, client, server, write, read} Verify{key, parameters}:
      Result.bind(&2, &1, Error, SHA.State, Phase, checked(SHA.State, H.verifyCertificateSignature(key, transcript, wire)), updated =>
        Done{Authenticating{H.Handshake{name, updated, secret, client, server, write, read}, Finished{parameters}}})
    case _ Finished{_}: Fail{UnexpectedMessage{}}

# The client Finished is protected with the handshake writer. Application
# keys are installed only after the server Finished has been verified.
def connected(parameters: H.Parameters, secrets: H.Secrets, limit: U32, result: Result<&2, &1, R.Error, R.Sent>) -> Result<&2, &1, Error, Step>:
  match secrets result:
    case _ Fail{cause}: Fail{RecordFailure{cause}}
    case H.Secrets{_, _, client, server, H.TrafficKey{wk, wi}, H.TrafficKey{rk, ri}} Done{R.Sent{_, record}}:
      Done{Step{Client{Connected{Some{R.create(wk, wi)}, Some{R.create(rk, ri)}, client, server, parameters}, H.emptyBuffer(), limit, emptyInput()}, record <> Nil{}, Nil{}}}

def finish(handshake: H.Handshake, parameters: H.Parameters, wire: List<&2, U32>, limit: U32) -> Result<&2, &1, Error, Step>:
  match handshake:
    case H.Handshake{_, transcript, secret, client, server, write, _}:
      Result.bind(&2, &1, Error, SHA.State, Step, checked(SHA.State, H.verifyFinished(server, transcript, wire)), +updated =>
        Result.bind(&2, &1, Error, H.Secrets, Step, checked(H.Secrets, H.applicationSecrets(SHA.toBytes(secret), updated)), secrets =>
          Result.bind(&2, &1, Error, List<&2, U32>, Step, checked(List<&2, U32>, H.clientFinished(client, updated)), finished =>
            connected(parameters, secrets, limit, R.send(write, R.Content{R.Handshake{}, finished}, 0n)))))

def serverHello(authorization: Authorization, limit: U32, result: Result<&2, &1, H.Error, H.Handshake>) -> Result<&2, &1, Error, Step>:
  match result:
    case Fail{cause}: Fail{HandshakeFailure{cause}}
    case Done{handshake}: Done{Step{Client{Authenticating{handshake, Extensions{authorization}}, H.emptyBuffer(), limit, emptyInput()}, Nil{}, Nil{}}}

def keyUpdateSent(client: Client, result: Result<&2, &1, R.Error, R.Sent>) -> Result<&2, &1, Error, Step>:
  match result:
    case Fail{cause}: Fail{RecordFailure{cause}}
    case Done{R.Sent{_, record}}: Done{Step{client, record <> Nil{}, Nil{}}}

# Send under the old key, then reset the writer's sequence under the next key.
# This also serves peer requests: the reply never requests another update.
def updateWriter(read: Maybe<&1, R.Traffic>, ss: List<&2, U32>, parameters: H.Parameters, buffer: H.Buffer, limit: U32, input: RecordBuffer, next: List<&2, U32>, material: H.TrafficKey, result: Result<&2, &1, R.Error, R.Sent>) -> Result<&2, &1, Error, Step>:
  match material:
    case H.TrafficKey{key, iv}: keyUpdateSent(Client{Connected{Some{R.create(key, iv)}, read, next, ss, parameters}, buffer, limit, input}, result)

def update(client: Client, requestPeer: Bool) -> Result<&2, &1, Error, Step>:
  match client:
    case Client{Connected{Some{write}, read, cs, ss, parameters}, buffer, limit, input}:
      Result.bind(&2, &1, Error, List<&2, U32>, Step, checked(List<&2, U32>, H.updateSecret(cs)), +next =>
        Result.bind(&2, &1, Error, H.TrafficKey, Step, checked(H.TrafficKey, H.deriveKey(next)), material =>
          updateWriter(read, ss, parameters, buffer, limit, input, next, material,
            R.send(write, R.Content{R.Handshake{}, 24 <> 0 <> 0 <> 1 <> Bool.pick(U32, requestPeer, 1, 0) <> Nil{}}, 0n))))
    case _: Fail{UnexpectedMessage{}}

def updateReply(requested: Bool, client: Client) -> Result<&2, &1, Error, Step>:
  match requested client:
    case True{} Client{Connected{Some{write}, read, cs, ss, parameters}, buffer, limit, input}:
      update(Client{Connected{Some{write}, read, cs, ss, parameters}, buffer, limit, input}, False{})
    case _ client: Done{Step{client, Nil{}, Nil{}}}

def updatedReader(requested: Bool, write: Maybe<&1, R.Traffic>, cs: List<&2, U32>, ss: List<&2, U32>, parameters: H.Parameters, buffer: H.Buffer, limit: U32, material: H.TrafficKey) -> Result<&2, &1, Error, Step>:
  match material:
    case H.TrafficKey{key, iv}: updateReply(requested, Client{Connected{write, Some{R.create(key, iv)}, cs, ss, parameters}, buffer, limit, emptyInput()})

def updateReader(requested: Bool, phase: Phase, buffer: H.Buffer, limit: U32) -> Result<&2, &1, Error, Step>:
  match phase:
    case Connected{write, Some{_}, cs, ss, parameters}:
      Result.bind(&2, &1, Error, List<&2, U32>, Step, checked(List<&2, U32>, H.updateSecret(ss)), +next =>
        Result.bind(&2, &1, Error, H.TrafficKey, Step, checked(H.TrafficKey, H.deriveKey(next)), material =>
          updatedReader(requested, write, cs, next, parameters, buffer, limit, material)))
    case _: Fail{UnexpectedMessage{}}

def isTicket(wire: List<&2, U32>) -> Bool:
  match wire:
    case kind <> _: U32.is_eq(kind, 4)
    case Nil{}: False{}

# Messages that change traffic keys must end their record (RFC 8446 5.1).
# A partial following message is just as invalid as a complete following one.
def messages(wires: List<&2, List<&2, U32>>, phase: Phase, +buffer: H.Buffer, +limit: U32) -> Result<&2, &1, Error, Step>:
  match wires phase:
    case Nil{} phase: Done{Step{Client{phase, buffer, limit, emptyInput()}, Nil{}, Nil{}}}
    case +wire <> rest Hello{pending, authorization}:
      Result.bind(&2, &1, Error, Unit, Step, require(List.is_empty(&2, List<&2, U32>, rest) && H.atBoundary(buffer)), unused =>
        serverHello(authorization, limit, H.acceptServerHello(pending, wire)))
    case wire <> rest Authenticating{handshake, Finished{parameters}}:
      Result.bind(&2, &1, Error, Unit, Step, require(List.is_empty(&2, List<&2, U32>, rest) && H.atBoundary(buffer)), unused => finish(handshake, parameters, wire, limit))
    case wire <> rest Authenticating{handshake, expected}:
      Result.bind(&2, &1, Error, Phase, Step, authenticate(handshake, expected, wire), next => messages(rest, next, buffer, limit))
    case +wire <> +rest Connected{write, read, cs, ss, parameters}:
      Bool.pick(Phase -> Result<&2, &1, Error, Step>, isTicket(wire),
        phase => Result.bind(&2, &1, Error, H.NewSessionTicket, Step, checked(H.NewSessionTicket, H.newSessionTicket(wire)), unused => messages(rest, phase, buffer, limit)),
        phase => Result.bind(&2, &1, Error, Unit, Step, require(List.is_empty(&2, List<&2, U32>, rest) && H.atBoundary(buffer)), unused =>
          Result.bind(&2, &1, Error, Bool, Step, checked(Bool, H.keyUpdateRequest(wire)), requested => updateReader(requested, phase, buffer, limit))))(Connected{write, read, cs, ss, parameters})
    case _ _: Fail{UnexpectedMessage{}}

def framed(phase: Phase, limit: U32, result: Result<&2, &2, H.FramingError, H.Batch>) -> Result<&2, &1, Error, Step>:
  match result:
    case Fail{cause}: Fail{FramingFailure{cause}}
    case Done{H.Batch{buffer, wires}}: messages(wires, phase, buffer, limit)

def handshakeRecord(client: Client, bytes: List<&2, U32>) -> Result<&2, &1, Error, Step>:
  match client:
    case Client{phase, buffer, +limit, input}: framed(phase, limit, H.feed(limit, buffer, bytes))

def alert(client: Client, bytes: List<&2, U32>) -> Result<&2, &1, Error, Step>:
  match client bytes:
    case Client{Connected{write, _, cs, ss, parameters}, +buffer, limit, input} _ <> 0 <> Nil{}:
      Result.bind(&2, &1, Error, Unit, Step, require(H.atBoundary(buffer)), unused =>
        Done{Step{Client{Connected{write, None{}, cs, ss, parameters}, buffer, limit, emptyInput()}, Nil{}, Nil{}}})
    case Client{phase, +buffer, limit, input} _ <> 90 <> Nil{}:
      Result.bind(&2, &1, Error, Unit, Step, require(H.atBoundary(buffer)), unused => Done{Step{Client{phase, buffer, limit, emptyInput()}, Nil{}, Nil{}}})
    case _ _ <> description <> Nil{}: Fail{PeerAlert{description}}
    case _ _: Fail{UnexpectedMessage{}}

def content(client: Client, message: R.Content) -> Result<&2, &1, Error, Step>:
  match client message:
    case client R.Content{R.Handshake{}, bytes}: handshakeRecord(client, bytes)
    case client R.Content{R.Alert{}, bytes}: alert(client, bytes)
    case Client{Connected{write, read, cs, ss, parameters}, +buffer, limit, input} R.Content{R.Application{}, bytes}:
      Result.bind(&2, &1, Error, Unit, Step, require(H.atBoundary(buffer)), unused =>
        Done{Step{Client{Connected{write, read, cs, ss, parameters}, buffer, limit, emptyInput()}, Nil{}, bytes <> Nil{}}})
    case _ _: Fail{UnexpectedMessage{}}

def recorded(-A: Type, result: Result<&2, &1, R.Error, A>) -> Result<&2, &1, Error, A>:
  match result:
    case Fail{cause}: Fail{RecordFailure{cause}}
    case Done{value}: Done{value}

def decrypted(result: R.Received, resume: R.Traffic -> Client) -> Result<&2, &1, Error, Step>:
  match result:
    case R.Received{read, message, Nil{}}: content(resume(read), message)
    case _: Fail{UnexpectedMessage{}}

def encrypted(client: Client, wire: List<&2, U32>) -> Result<&2, &1, Error, Step>:
  match client:
    case Client{Authenticating{H.Handshake{name, transcript, secret, cs, ss, write, read}, expected}, buffer, limit, input}:
      Result.bind(&2, &1, Error, R.Received, Step, recorded(R.Received, R.receive(read, wire)), received =>
        decrypted(received, next => Client{Authenticating{H.Handshake{name, transcript, secret, cs, ss, write, next}, expected}, buffer, limit, emptyInput()}))
    case Client{Connected{write, Some{read}, cs, ss, parameters}, buffer, limit, input}:
      Result.bind(&2, &1, Error, R.Received, Step, recorded(R.Received, R.receive(read, wire)), received =>
        decrypted(received, next => Client{Connected{write, Some{next}, cs, ss, parameters}, buffer, limit, emptyInput()}))
    case _: Fail{UnexpectedMessage{}}

def compatibility(client: Client) -> Result<&2, &1, Error, Step>:
  match client:
    case Client{Hello{pending, authorization}, buffer, limit, input}: Done{Step{Client{Hello{pending, authorization}, buffer, limit, input}, Nil{}, Nil{}}}
    case Client{Authenticating{handshake, expected}, buffer, limit, input}: Done{Step{Client{Authenticating{handshake, expected}, buffer, limit, input}, Nil{}, Nil{}}}
    case _: Fail{UnexpectedMessage{}}

def plaintext(client: Client, bytes: List<&2, U32>) -> Result<&2, &1, Error, Step>:
  match client:
    case Client{Hello{pending, authorization}, buffer, limit, input}: handshakeRecord(Client{Hello{pending, authorization}, buffer, limit, input}, bytes)
    case _: Fail{UnexpectedMessage{}}

def plaintextAlert(client: Client, bytes: List<&2, U32>) -> Result<&2, &1, Error, Step>:
  match client:
    case Client{Hello{pending, authorization}, buffer, limit, input}: alert(Client{Hello{pending, authorization}, buffer, limit, input}, bytes)
    case _: Fail{UnexpectedMessage{}}

# legacy_record_version is authenticated as AAD but has no negotiation role.
# RFC 8446 requires receivers to ignore its value, even on plaintext records.
def receiveRecord(client: Client, +wire: List<&2, U32>) -> Result<&2, &1, Error, Step>:
  match wire:
    case 20 <> major <> minor <> 0 <> 1 <> 1 <> Nil{}:
      Result.bind(&2, &1, Error, Unit, Step, require(U32.is_le(major, 255) && U32.is_le(minor, 255)), unused => compatibility(client))
    case 23 <> _ <> _ <> _ <> _ <> _: encrypted(client, wire)
    case 21 <> major <> minor <> 0 <> 2 <> +level <> +description <> Nil{}:
      Result.bind(&2, &1, Error, Unit, Step, require(U32.is_le(major, 255) && U32.is_le(minor, 255) && U32.is_le(level, 255) && U32.is_le(description, 255)), unused => plaintextAlert(client, level <> description <> Nil{}))
    case 22 <> major <> minor <> a <> b <> +bytes:
      Result.bind(&2, &1, Error, Unit, Step, require(U32.is_le(major, 255) && U32.is_le(minor, 255) && Nat.is_eq(R.length(bytes, 0n), U32.to_nat((a * 256 + b : U32))) && U32.is_le(a, 64) && U32.is_le(b, 255) && Nat.is_gt(R.length(bytes, 0n), 0n) && Nat.is_le(R.length(bytes, 0n), 16384n)), unused => plaintext(client, bytes))
    case _: Fail{UnexpectedMessage{}}

def receiveComplete(client: Client, wire: List<&2, U32>) -> Result<&2, &1, Error, Step>:
  match client:
    case Client{Connected{write, None{}, cs, ss, parameters}, buffer, limit, input}:
      Done{Step{Client{Connected{write, None{}, cs, ss, parameters}, buffer, limit, emptyInput()}, Nil{}, Nil{}}}
    case client: receiveRecord(client, wire)

def writer(closing: Bool, traffic: R.Traffic) -> Maybe<&1, R.Traffic>:
  match closing:
    case False{}: Some{traffic}
    case True{}: None{}

def sent(closing: Bool, read: Maybe<&1, R.Traffic>, cs: List<&2, U32>, ss: List<&2, U32>, parameters: H.Parameters, buffer: H.Buffer, limit: U32, input: RecordBuffer, result: Result<&2, &1, R.Error, R.Sent>) -> Result<&2, &1, Error, Step>:
  match result:
    case Fail{cause}: Fail{RecordFailure{cause}}
    case Done{R.Sent{write, record}}: Done{Step{Client{Connected{writer(closing, write), read, cs, ss, parameters}, buffer, limit, input}, record <> Nil{}, Nil{}}}

def send(client: Client, bytes: List<&2, U32>) -> Result<&2, &1, Error, Step>:
  match client:
    case Client{Connected{Some{write}, read, cs, ss, parameters}, buffer, limit, input}: sent(False{}, read, cs, ss, parameters, buffer, limit, input, R.send(write, R.Content{R.Application{}, bytes}, 0n))
    case _: Fail{UnexpectedMessage{}}

# Closing the writer preserves the reader. Peer close_notify closes only the
# reader; the application may still finish pending writes before closing them.
def close(client: Client) -> Result<&2, &1, Error, Step>:
  match client:
    case Client{Connected{Some{write}, read, cs, ss, parameters}, buffer, limit, input}: sent(True{}, read, cs, ss, parameters, buffer, limit, input, R.send(write, R.Content{R.Alert{}, 1 <> 0 <> Nil{}}, 0n))
    case Client{Connected{None{}, read, cs, ss, parameters}, buffer, limit, input}: Done{Step{Client{Connected{None{}, read, cs, ss, parameters}, buffer, limit, input}, Nil{}, Nil{}}}
    case _: Fail{UnexpectedMessage{}}

# Outer framing keeps each byte once in reverse order until its record is
# complete. No append/reparse of a growing socket buffer, and no allocation
# based on an unchecked peer-supplied length.
type BufferedRecord is Data:
  BufferedRecord{buffer: RecordBuffer, record: Maybe<&2, List<&2, U32>>}

def recordBody(size: U32, reverse: List<&2, U32>) -> BufferedRecord:
  match size:
    case 0: BufferedRecord{emptyInput(), Some{List.reverse(&2, U32, reverse)}}
    case size: BufferedRecord{RecordBody{reverse, size}, None{}}

def recordHeader(+reverse: List<&2, U32>) -> Result<&2, &1, Error, BufferedRecord>:
  match reverse:
    case low <> high <> _ <> _ <> +kind <> Nil{}:
      +size = (high * 256 + low : U32)
      maximum = Bool.pick(U32, U32.is_eq(kind, 23), 16640, 16384)
      Result.bind(&2, &1, Error, Unit, BufferedRecord,
        Bool.pick(Result<&2, &1, Error, Unit>, U32.is_le(size, maximum), Done{Unit{}}, Fail{RecordFailure{R.RecordOverflow{}}}), unused =>
          Done{recordBody(size, reverse)})
    case _: Fail{UnexpectedMessage{}}

def inputByte(buffer: RecordBuffer, byte: U32) -> Result<&2, &1, Error, BufferedRecord>:
  match buffer:
    case RecordHeader{reverse, 1}: recordHeader(byte <> reverse)
    case RecordHeader{reverse, needed}: Done{BufferedRecord{RecordHeader{byte <> reverse, (needed - 1 : U32)}, None{}}}
    case RecordBody{reverse, 1}: Done{BufferedRecord{emptyInput(), Some{List.reverse(&2, U32, byte <> reverse)}}}
    case RecordBody{reverse, remaining}: Done{BufferedRecord{RecordBody{byte <> reverse, (remaining - 1 : U32)}, None{}}}

def buffered(client: Client, record: BufferedRecord) -> Result<&2, &1, Error, Step>:
  match client record:
    case Client{phase, fragments, limit, _} BufferedRecord{input, None{}}: Done{Step{Client{phase, fragments, limit, input}, Nil{}, Nil{}}}
    case Client{phase, fragments, limit, _} BufferedRecord{_, Some{wire}}: receiveComplete(Client{phase, fragments, limit, emptyInput()}, wire)

# Accepted records are observable even if a later record in this same socket
# chunk fails. Otherwise transport chunk boundaries would decide which valid
# application bytes or generated replies the caller gets to see.
type Reception is Type:
  Reception{client: Result<&2, &1, Error, Client>, outgoing: List<&2, List<&2, U32>>, incoming: List<&2, List<&2, U32>>}

def finishInput(outgoing: List<&2, List<&2, U32>>, incoming: List<&2, List<&2, U32>>, result: Result<&2, &1, Error, Step>) -> Reception:
  match result:
    case Fail{cause}: Reception{Fail{cause}, List.reverse(&2, List<&2, U32>, outgoing), List.reverse(&2, List<&2, U32>, incoming)}
    case Done{Step{client, outbound, inbound}}:
      Reception{Done{client}, List.reverse(&2, List<&2, U32>, List.reverse.go(&2, List<&2, U32>, outbound, outgoing)), List.reverse(&2, List<&2, U32>, List.reverse.go(&2, List<&2, U32>, inbound, incoming))}

def feed(bytes: List<&2, U32>, result: Result<&2, &1, Error, Step>, outgoing: List<&2, List<&2, U32>>, incoming: List<&2, List<&2, U32>>) -> Reception:
  match bytes result:
    case Nil{} result: finishInput(outgoing, incoming, result)
    case _ Fail{cause}: finishInput(outgoing, incoming, Fail{cause})
    case _ Done{Step{Client{Connected{write, None{}, cs, ss, parameters}, fragments, limit, input}, outbound, inbound}}:
      finishInput(outgoing, incoming, Done{Step{Client{Connected{write, None{}, cs, ss, parameters}, fragments, limit, input}, outbound, inbound}})
    case +byte <> rest Done{Step{Client{phase, fragments, limit, input}, outbound, inbound}}:
      feed(rest,
        Result.bind(&2, &1, Error, Unit, Step,
          Bool.pick(Result<&2, &1, Error, Unit>, U32.is_le(byte, 255), Done{Unit{}}, Fail{RecordFailure{R.InvalidByte{}}}), unused =>
            Result.bind(&2, &1, Error, BufferedRecord, Step, inputByte(input, byte), record =>
              buffered(Client{phase, fragments, limit, emptyInput()}, record))),
        List.reverse.go(&2, List<&2, U32>, outbound, outgoing), List.reverse.go(&2, List<&2, U32>, inbound, incoming))

def receive(client: Client, bytes: List<&2, U32>) -> Reception:
  feed(bytes, Done{Step{client, Nil{}, Nil{}}}, Nil{}, Nil{})
