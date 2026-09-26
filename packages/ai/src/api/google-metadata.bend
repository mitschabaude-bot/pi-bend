import Base
import ./credential-http.bend as Http
import ../utils/provider-env.bend as Env
import ../../../runtime/src/filesystem.bend as FS
import ../../../runtime/src/json.bend as Decode
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/url.bend as URL
import ../../../runtime/src/utf8.bend as Utf8
import ../../../runtime/src/http-message.bend as Headers
import ../../../runtime/src/record.bend as R

# gcp-metadata 8.1.2 as google-auth-library uses it: whether the process runs
# on Google Cloud (the residency probe, then a ping of the metadata server)
# and metadata values under /computeMetadata/v1. Requests carry
# `Metadata-Flavor: Google` and replies must echo it.

def HOST_ADDRESS() -> String: "http://169.254.169.254"

def SECONDARY_HOST_ADDRESS() -> String: "http://metadata.google.internal."

def BASE_PATH() -> String: "/computeMetadata/v1"

def env(+name: String) -> IO(Maybe<&2, String>): Env.getProviderEnvValue(name, None{})

def nonempty(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{SCon{c, cs}}
    case _: None{}

def schemed(+base: String) -> String:
  Bool.pick(String, String.starts_with(base, "http://") || String.starts_with(base, "https://"), base, "http://" ++ base)

def resolvedBase(+base: String, resolved: Result<&2, &2, URL.ResolveError, URL.URL>) -> String:
  match resolved:
    case Done{url}: URL.serialize(url, False{})
    case Fail{_}: base ++ BASE_PATH()

def baseWith(context: URL.Context, +base: String, parsed: Result<&2, &2, URL.Error, URL.URL>) -> String:
  match parsed:
    case Done{url}: resolvedBase(base, URL.parseResolve(context, url, BASE_PATH()))
    case Fail{_}: base ++ BASE_PATH()

# getBaseUrl: GCE_METADATA_IP, GCE_METADATA_HOST or the link-local address,
# with http:// when no scheme is given, and the path /computeMetadata/v1.
def baseUrlOf(+context: URL.Context, +base: String) -> String: baseWith(context, schemed(base), URL.parse(context, schemed(base)))

def configuredHost() -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    ip : Maybe<&2, String> <- env("GCE_METADATA_IP")
    host : Maybe<&2, String> <- env("GCE_METADATA_HOST")
    return Maybe.or(&2, String, nonempty(ip), nonempty(host))

def decodedText(value: Utf8.Decoded) -> String:
  match value:
    case Utf8.Decoded{_, text}: text

def textOf(bytes: List<&2, U32>) -> String: decodedText(Utf8.decode(Utf8.create(), bytes))

# Residency (gcp-residency.ts)
# ----------------------------

def serverless() -> IO(Bool):
  do IO<Bool>:
    job : Maybe<&2, String> <- env("CLOUD_RUN_JOB")
    function : Maybe<&2, String> <- env("FUNCTION_NAME")
    service : Maybe<&2, String> <- env("K_SERVICE")
    return Maybe.is_some(&2, String, Maybe.or(&2, String, nonempty(job), Maybe.or(&2, String, nonempty(function), nonempty(service))))

def vendorGoogle(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> Bool:
  match bytes:
    case Done{content}: String.contains(textOf(content), "Google")
    case Fail{_}: False{}

def biosVendor(kind: Result<&2, &2, FS.Error, FS.FileKind>) -> IO(Bool):
  match kind:
    case Done{_}:
      do IO<Bool>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile("/sys/class/dmi/id/bios_vendor")
        return vendorGoogle(bytes)
    case Fail{_}: IO.pure(Bool, False{})

# The BIOS of a Compute Engine VM names Google as its vendor.
def computeEngineLinux() -> IO(Bool):
  do IO<Bool>:
    date : Result<&2, &2, FS.Error, FS.FileKind> <- FS.fileKind("/sys/class/dmi/id/bios_date")
    biosVendor(date)

def googleMac(bytes: Result<&2, &2, FS.Error, List<&2, U32>>) -> Bool:
  match bytes:
    case Done{content}: String.starts_with(textOf(content), "42:01")
    case Fail{_}: False{}

def macs(entries: List<&2, FS.DirectoryEntry>) -> IO(Bool):
  match entries:
    case Nil{}: IO.pure(Bool, False{})
    case FS.DirectoryEntry{name, _} <> rest:
      do IO<Bool>:
        bytes : Result<&2, &2, FS.Error, List<&2, U32>> <- FS.readFile("/sys/class/net/" ++ name ++ "/address")
        Bool.pick(Unit -> IO(Bool), googleMac(bytes), _ => IO.pure(Bool, True{}), _ => macs(rest))(Unit{})

def listedMacs(entries: Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>>) -> IO(Bool):
  match entries:
    case Done{list}: macs(list)
    case Fail{_}: IO.pure(Bool, False{})

# A network interface with a Compute Engine MAC address (42:01:...), from
# the interfaces the kernel lists.
def computeEngineMac() -> IO(Bool):
  do IO<Bool>:
    entries : Result<&2, &2, FS.Error, List<&2, FS.DirectoryEntry>> <- FS.readDirectory("/sys/class/net")
    listedMacs(entries)

def orElse(first: Bool, second: IO(Bool)) -> IO(Bool): Bool.pick(IO(Bool), first, IO.pure(Bool, True{}), second)

# detectGCPResidency: a serverless environment or a Compute Engine VM.
def residency() -> IO(Bool):
  do IO<Bool>:
    cloud : Bool <- serverless()
    linux : Bool <- Bool.pick(IO(Bool), cloud, IO.pure(Bool, True{}), computeEngineLinux())
    orElse(linux, computeEngineMac())

# requestTimeout: none on Google Cloud, else three seconds.
def requestTimeout(resident: Bool) -> U32: Bool.pick(U32, resident, Http.NO_TIMEOUT(), 3000)

# Requests
# --------

type MetadataError is Data:
  NoResponse{failure: Http.Failure}
  ErrorStatus{status: U32, message: String}
  WrongFlavor{message: String}

def flavorMessage(value: Maybe<&2, String>) -> String:
  "Invalid response from metadata service: incorrect Metadata-Flavor header. Expected 'Google', got " ++ Maybe.default(&2, String, Maybe.map(&2, String, String, found => "'" ++ found ++ "'", value), "no header")

def flavored(+reply: Http.Reply, flavor: Maybe<&2, String>) -> Result<&2, &2, MetadataError, Http.Reply>:
  match flavor:
    case Some{"Google"}: Done{reply}
    case other: Fail{WrongFlavor{flavorMessage(other)}}

def failedStatus(+status: U32, +body: String) -> String:
  Bool.pick(String, String.is_empty(body), "Request failed with status code " ++ U32.show(status), body)

def checkedReply(+reply: Http.Reply) -> Result<&2, &2, MetadataError, Http.Reply>:
  match reply:
    case Http.Reply{+status, headers, +body}:
      Bool.pick(Result<&2, &2, MetadataError, Http.Reply>, U32.is_ge(status, 200) && U32.is_lt(status, 300), flavored(Http.Reply{status, headers, body}, Http.header(Http.Reply{status, headers, body}, "Metadata-Flavor")), Fail{ErrorStatus{status, failedStatus(status, body)}})

def replied(result: Result<&2, &2, Http.Failure, Http.Reply>) -> Result<&2, &2, MetadataError, Http.Reply>:
  match result:
    case Fail{failure}: Fail{NoResponse{failure}}
    case Done{reply}: checkedReply(reply)

# A metadata request: gaxios retries it (three times on retryable statuses;
# `noResponseRetries` times when no response came).
def attempts(~Reason: Data, +transport: Http.Transport<Reason>, +url: String, +timeout: U32, noResponseRetries: Nat) -> IO(Result<&2, &2, MetadataError, Http.Reply>):
  do IO<Result<&2, &2, MetadataError, Http.Reply>>:
    result : Result<&2, &2, Http.Failure, Http.Reply> <- Http.requestRetrying(~Reason, transport, Http.Retry{3n, noResponseRetries, ["GET", "HEAD", "PUT", "OPTIONS", "DELETE"]}, "GET", url, [R.Property{"Metadata-Flavor", "Google"}], Headers.Absent{}, timeout)
    return replied(result)

# metadataAccessor: one metadata value (`instance/...`, `project/...`)
# under the configured host.
def accessor(~Reason: Data, +transport: Http.Transport<Reason>, +key: String, resident: Bool, retries: Nat) -> IO(Result<&2, &2, MetadataError, Http.Reply>):
  do IO<Result<&2, &2, MetadataError, Http.Reply>>:
    host : Maybe<&2, String> <- configuredHost()
    attempts(~Reason, transport, baseUrlOf(Http.contextOf(Reason, transport), Maybe.default(&2, String, host, HOST_ADDRESS())) ++ "/" ++ key, requestTimeout(resident), retries)

def instance(~Reason: Data, +transport: Http.Transport<Reason>, +property: String, resident: Bool, retries: Nat) -> IO(Result<&2, &2, MetadataError, Http.Reply>):
  accessor(~Reason, transport, "instance" ++ property, resident, retries)

# fastFailMetadataRequest: the link-local address, then the DNS name.
def pinged(~Reason: Data, +transport: Http.Transport<Reason>, +timeout: U32, first: Result<&2, &2, MetadataError, Http.Reply>) -> IO(Bool):
  match first:
    case Done{_}: IO.pure(Bool, True{})
    case Fail{_}:
      do IO<Bool>:
        second : Result<&2, &2, MetadataError, Http.Reply> <- attempts(~Reason, transport, baseUrlOf(Http.contextOf(Reason, transport), SECONDARY_HOST_ADDRESS()) ++ "/instance", timeout, 0n)
        return Result.is_done(&2, &2, MetadataError, Http.Reply, second)

def ping(~Reason: Data, +transport: Http.Transport<Reason>, +resident: Bool, configured: Maybe<&2, String>) -> IO(Bool):
  match configured:
    case Some{host}:
      do IO<Bool>:
        result : Result<&2, &2, MetadataError, Http.Reply> <- attempts(~Reason, transport, baseUrlOf(Http.contextOf(Reason, transport), host) ++ "/instance", requestTimeout(resident), 0n)
        return Result.is_done(&2, &2, MetadataError, Http.Reply, result)
    case None{}:
      do IO<Bool>:
        first : Result<&2, &2, MetadataError, Http.Reply> <- attempts(~Reason, transport, baseUrlOf(Http.contextOf(Reason, transport), HOST_ADDRESS()) ++ "/instance", requestTimeout(resident), 0n)
        pinged(~Reason, transport, requestTimeout(resident), first)

def DETECTION_VALUES() -> String: "assume-present`, `none`, `bios-only`, `ping-only"

def pingAvailable(~Reason: Data, +transport: Http.Transport<Reason>, resident: Bool) -> IO(Result<&2, &2, String, Bool>):
  do IO<Result<&2, &2, String, Bool>>:
    configured : Maybe<&2, String> <- configuredHost()
    available : Bool <- ping(~Reason, transport, resident, configured)
    return Done{available}

# isAvailable, after METADATA_SERVER_DETECTION: assume the server, rule it
# out, trust the residency probe, or ping it (DETECT_GCP_RETRIES is not
# read; the ping is not retried).
def detection(~Reason: Data, +transport: Http.Transport<Reason>, resident: Bool, +mode: Maybe<&2, String>) -> IO(Result<&2, &2, String, Bool>):
  match mode:
    case None{}: pingAvailable(~Reason, transport, resident)
    case Some{"assume-present"}: IO.pure(Result<&2, &2, String, Bool>, Done{True{}})
    case Some{"none"}: IO.pure(Result<&2, &2, String, Bool>, Done{False{}})
    case Some{"bios-only"}: IO.pure(Result<&2, &2, String, Bool>, Done{resident})
    case Some{"ping-only"}: pingAvailable(~Reason, transport, resident)
    case Some{other}: IO.pure(Result<&2, &2, String, Bool>, Fail{"Unknown `METADATA_SERVER_DETECTION` env variable. Got `" ++ other ++ "`, but it should be `" ++ DETECTION_VALUES() ++ "`, or unset"})

def detectionMode(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case Some{SCon{c, cs}}: Some{String.to_lower(String.trim(SCon{c, cs}))}
    case _: None{}

# _checkIsGCE: the residency probe, else isAvailable.
def isGce(~Reason: Data, +transport: Http.Transport<Reason>, +resident: Bool) -> IO(Result<&2, &2, String, Bool>):
  Bool.pick(Unit -> IO(Result<&2, &2, String, Bool>), resident, _ => IO.pure(Result<&2, &2, String, Bool>, Done{True{}}), _ =>
    do IO<Result<&2, &2, String, Bool>>:
      mode : Maybe<&2, String> <- env("METADATA_SERVER_DETECTION")
      detection(~Reason, transport, resident, detectionMode(mode)))(Unit{})
