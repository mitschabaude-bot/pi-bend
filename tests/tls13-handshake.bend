import Base
import ../packages/runtime/src/tls13-handshake.bend as TLS
import ../packages/runtime/src/string.bend as Split
import ../packages/runtime/src/sha256.bend as SHA
import ../packages/runtime/src/tls13-record.bend as Record
import ../packages/runtime/test/utf8-runner.bend as Decimal
import ./aes128-gcm.bend as Bytes
import ../packages/runtime/src/x509.bend as X509

def name(text: String) -> Maybe<&2, String>:
  match text:
    case "-": None{}
    case text: Some{text}

def error(cause: TLS.Error) -> String:
  match cause:
    case TLS.EntropyFailure{code, _}: "entropy:" ++ U32.show(code)
    case TLS.InvalidRandomness{}: "randomness"
    case TLS.InvalidServerName{}: "name"
    case TLS.KeyExchange{_}: "key"
    case TLS.MalformedServerHello{}: "malformed"
    case TLS.RejectedParameters{}: "parameters"
    case TLS.HelloRetryRequest{}: "retry"
    case TLS.Derivation{_}: "derivation"
    case TLS.InvalidKeyMaterial{}: "material"
    case TLS.MalformedHandshake{}: "handshake"
    case TLS.RejectedExtension{kind}: "extension:" ++ U32.show(kind)
    case TLS.DuplicateExtension{kind}: "duplicate:" ++ U32.show(kind)
    case TLS.CertificateFailure{_}: "certificate"
    case TLS.FinishedMismatch{}: "finished"

def render(result: Result<&2, &1, TLS.Error, TLS.Started>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Started{TLS.Pending{_, _, _, hello}, record}}:
      String.reverse.go(String.reverse(Bytes.show(record)), "|" ++ Bytes.show(hello))

def sent(result: Result<&2, &1, Record.Error, Record.Sent>) -> String:
  match result:
    case Fail{_}: "send-error"
    case Done{Record.Sent{_, wire}}: Bytes.show(wire)

def received(result: Result<&2, &1, Record.Error, Record.Received>) -> String:
  match result:
    case Fail{_}: "receive-error"
    case Done{Record.Received{_, Record.Content{kind, bytes}, _}}: U32.show(Record.code(kind)) ++ ":" ++ Bytes.show(bytes)

def negotiated(encrypted: List<&2, U32>, result: Result<&2, &1, TLS.Error, TLS.Handshake>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Handshake{_, _, secret, client, server, write, read}}:
      Bytes.show(SHA.toBytes(secret)) ++ "|" ++ Bytes.show(client) ++ "|" ++ Bytes.show(server) ++ "|" ++
        sent(Record.send(write, Record.Content{Record.Handshake{}, 20 <> 0 <> 0 <> 0 <> Nil{}}, 0n)) ++ "|" ++ received(Record.receive(read, encrypted))

def accept(serverHello: List<&2, U32>, encrypted: List<&2, U32>, result: Result<&2, &1, TLS.Error, TLS.Started>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Started{pending, _}}: negotiated(encrypted, TLS.acceptServerHello(pending, serverHello))

def showMessages(messages: List<&2, List<&2, U32>>) -> String:
  match messages:
    case Nil{}: ""
    case head <> rest: "|" ++ Bytes.show(head) ++ showMessages(rest)

def framed(result: Result<&2, &2, TLS.FramingError, TLS.Batch>) -> String:
  match result:
    case Fail{TLS.InvalidByte{}}: "byte"
    case Fail{TLS.MessageTooLarge{length, limit}}: "large:" ++ U32.show(length) ++ ":" ++ U32.show(limit)
    case Done{TLS.Batch{buffer, messages}}:
      Bool.pick(String, TLS.atBoundary(buffer), "complete", "partial") ++ showMessages(messages)

def chunks(parts: List<&2, String>, +limit: U32, result: Result<&2, &2, TLS.FramingError, TLS.Batch>, saved: String) -> String:
  match parts result:
    case Nil{} result: saved ++ framed(result)
    case _ Fail{cause}: framed(Fail{cause})
    case part <> rest Done{TLS.Batch{buffer, messages}}:
      chunks(rest, limit, TLS.feed(limit, buffer, Bytes.bytes(part)), saved ++ showMessages(messages))

def parameters(result: Result<&2, &2, TLS.Error, TLS.Parameters>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Parameters{ack, None{}}}: Bool.pick(String, ack, "sni", "none") ++ ":none"
    case Done{TLS.Parameters{ack, Some{protocol}}}: Bool.pick(String, ack, "sni", "none") ++ ":" ++ protocol

def transcriptDigest(result: Result<&2, &2, SHA.Error, SHA.Digest>) -> String:
  match result:
    case Fail{_}: "hash-error"
    case Done{value}: Bytes.show(SHA.toBytes(value))

def parameterResult(result: Result<&2, &1, TLS.Error, TLS.ServerParameters>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.ServerParameters{TLS.Handshake{_, transcript, _, _, _, _, _}, values}}:
      parameters(Done{values}) ++ "|" ++ transcriptDigest(SHA.finish(transcript))

def acceptParameters(wire: List<&2, U32>, result: Result<&2, &1, TLS.Error, TLS.Handshake>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{state}: parameterResult(TLS.acceptEncryptedExtensions(state, wire))

def startParameters(hello: List<&2, U32>, wire: List<&2, U32>, result: Result<&2, &1, TLS.Error, TLS.Started>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Started{pending, _}}: acceptParameters(wire, TLS.acceptServerHello(pending, hello))

def certificateResult(result: Result<&2, &2, TLS.Error, List<&2, List<&2, U32>>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{values}: "certificates" ++ showMessages(values)

def scheme(value: TLS.SignatureScheme) -> String:
  match value:
    case TLS.EcdsaP256Sha256{}: "1027"
    case TLS.EcdsaP384Sha384{}: "1283"
    case TLS.RsaPssRsaeSha256{}: "2052"

def signatureResult(result: Result<&2, &2, TLS.Error, TLS.CertificateSignature>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.CertificateSignature{algorithm, signature, input}}:
      scheme(algorithm) ++ "|" ++ Bytes.show(signature) ++ "|" ++ Bytes.show(input)

def signatureTranscript(wire: List<&2, U32>, result: Result<&2, &2, SHA.Error, SHA.State>) -> String:
  match result:
    case Fail{_}: "hash-error"
    case Done{transcript}: signatureResult(TLS.certificateSignature(transcript, wire))

def checkedTranscript(result: Result<&2, &2, TLS.Error, SHA.State>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{transcript}: transcriptDigest(SHA.finish(transcript))

def verifyCertificate(cert: List<&2, U32>, bytes: List<&2, U32>, wire: List<&2, U32>) -> Result<&2, &2, TLS.Error, SHA.State>:
  Result.bind(&2, &2, TLS.Error, X509.Certificate, SHA.State, TLS.certificateResult(X509.Certificate, X509.parse(cert)), certificate =>
    Result.bind(&2, &2, TLS.Error, X509.PublicKey, SHA.State, TLS.certificateResult(X509.PublicKey, X509.publicKey(certificate)), key =>
      Result.bind(&2, &2, TLS.Error, SHA.State, SHA.State, TLS.hashResult(SHA.State, SHA.update(bytes,SHA.create())), transcript => TLS.verifyCertificateSignature(key,transcript,wire))))

def verifyFinished(secret: List<&2, U32>, bytes: List<&2, U32>, wire: List<&2, U32>) -> Result<&2, &2, TLS.Error, SHA.State>:
  Result.bind(&2, &2, TLS.Error, SHA.State, SHA.State, TLS.hashResult(SHA.State, SHA.update(bytes,SHA.create())), transcript => TLS.verifyFinished(secret,transcript,wire))

def sealResult(kind: Record.ContentType, bytes: List<&2, U32>, result: Result<&2, &2, TLS.Error, TLS.TrafficKey>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.TrafficKey{key,iv}}: sent(Record.send(Record.create(key,iv),Record.Content{kind,bytes},0n))

def seal(key: List<&2, U32>, kind: Record.ContentType, bytes: List<&2, U32>) -> String:
  sealResult(kind,bytes,TLS.deriveKey(key))

def finishRecord(secret: List<&2, U32>, result: Result<&2, &2, TLS.Error, List<&2, U32>>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{wire}: seal(secret,Record.Handshake{},wire)

def applicationResult(+clientHandshake: List<&2, U32>, incoming: List<&2, U32>, result: Result<&2, &2, TLS.Error, TLS.Secrets>) -> String:
  match result:
    case Fail{cause}: error(cause)
    case Done{TLS.Secrets{transcript,master,+client,server,_,TLS.TrafficKey{key,iv}}}:
      finished = TLS.clientFinished(clientHandshake,transcript)
      Bytes.show(SHA.toBytes(master)) ++ "|" ++ Bytes.show(client) ++ "|" ++ Bytes.show(server) ++ "|" ++
        finishRecord(clientHandshake,finished) ++ "|" ++ seal(client,Record.Application{},TLS.ascii("ping")) ++ "|" ++ received(Record.receive(Record.create(key,iv),incoming))

def application(secret: List<&2, U32>, client: List<&2, U32>, incoming: List<&2, U32>, result: Result<&2, &2, SHA.Error, SHA.State>) -> String:
  match result:
    case Fail{_}: "hash-error"
    case Done{transcript}: applicationResult(client,incoming,TLS.applicationSecrets(secret,transcript))

def run(parts: List<&2, String>) -> IO(Unit):
  match parts:
    case "application" <> secret <> client <> transcript <> incoming <> Nil{}: IO.print(application(Bytes.bytes(secret),Bytes.bytes(client),Bytes.bytes(incoming),SHA.update(Bytes.bytes(transcript),SHA.create())))
    case "verify" <> cert <> transcript <> wire <> Nil{}: IO.print(checkedTranscript(verifyCertificate(Bytes.bytes(cert),Bytes.bytes(transcript),Bytes.bytes(wire))))
    case "finished" <> secret <> transcript <> wire <> Nil{}: IO.print(checkedTranscript(verifyFinished(Bytes.bytes(secret),Bytes.bytes(transcript),Bytes.bytes(wire))))
    case "cert" <> wire <> Nil{}: IO.print(certificateResult(TLS.certificates(Bytes.bytes(wire))))
    case "cv" <> transcript <> wire <> Nil{}: IO.print(signatureTranscript(Bytes.bytes(wire), SHA.update(Bytes.bytes(transcript), SHA.create())))
    case "ep" <> host <> seed <> hello <> wire <> Nil{}: IO.print(startParameters(Bytes.bytes(hello), Bytes.bytes(wire), TLS.initialize(name(host), Bytes.bytes(seed))))
    case "ee" <> offered <> wire <> Nil{}: IO.print(parameters(TLS.encryptedExtensions(String.eq(offered, "yes"), Bytes.bytes(wire))))
    case "f" <> limit <> input <> Nil{}: IO.print(chunks(Split.split(input, '/'), Decimal.decimal(limit, 0), Done{TLS.Batch{TLS.emptyBuffer(), Nil{}}}, ""))
    case "n" <> host <> seed <> hello <> encrypted <> Nil{}: IO.print(accept(Bytes.bytes(hello), Bytes.bytes(encrypted), TLS.initialize(name(host), Bytes.bytes(seed))))
    case "d" <> host <> seed <> Nil{}: IO.print(render(TLS.initialize(name(host), Bytes.bytes(seed))))
    case "os" <> host <> Nil{}:
      do IO<Unit>:
        started : Result<&2, &1, TLS.Error, TLS.Started> <- TLS.start(name(host))
        IO.print(render(started))
    case "e" <> code <> Nil{}: IO.print(render(TLS.fromEntropy(None{}, Fail{Tuple{Decimal.decimal(code, 0), "test source failure"}})))
    case _: IO.print("invalid")

def arguments(values: List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case head <> rest:
      do IO<Unit>:
        run(Split.split(head, ':'))
        arguments(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    values : List<String> <- IO.args()
    arguments(values)
