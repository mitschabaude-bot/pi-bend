import Base
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/fetch.bend as Fetch
import ../../../../runtime/src/callback.bend as C
import ../../../../runtime/src/deadline.bend as Deadline
import ../../../../runtime/src/deferred.bend as D
import ../../../../runtime/src/f64.bend as F
import ../../../../runtime/src/number-string.bend as Number
import ../../../../runtime/src/http-response.bend as Response
import ../../../../runtime/src/ref.bend as Ref
import ../../../../runtime/src/sse.bend as SSE
import ../../../../ai/src/api/provider-fetch.bend as Reader
import ../../../../runtime/src/http-message.bend as Headers
import ../../../../runtime/src/json.bend as Json
import ../../../../runtime/src/record.bend as R
import ../../../../runtime/src/schema-value.bend as V
import ../../../../runtime/src/timer.bend as Timer
import ../../../../runtime/src/url.bend as URL
import ../../../../ai/src/api/credential-http.bend as HTTP

# Router management is separate from the OpenAI-compatible inference API.
# Transport is injected so the same client serves login, catalog refresh and
# the /llama UI, with the native fetch and cancellable request deadlines.

type LlamaModelStatus is Data:
  Unloaded{}
  Loading{}
  Loaded{}
  Downloading{}
  Sleeping{}


type FileProgress is Data:
  FileProgress{done: F64, total: F64}

type Status is Data:
  Status{value: LlamaModelStatus, args: Maybe<&2, List<&2, String>>, failed: Maybe<&2, Bool>, exit_code: Maybe<&2, F64>, progress: Maybe<&2, R.Record<FileProgress>>}

type Architecture is Data:
  Architecture{input_modalities: Maybe<&2, List<&2, String>>, output_modalities: Maybe<&2, List<&2, String>>}

type Metadata is Data:
  Metadata{n_ctx: Maybe<&2, F64>, n_ctx_train: Maybe<&2, F64>, size: Maybe<&2, F64>, ftype: Maybe<&2, String>}

type LlamaModelInfo is Data:
  LlamaModelInfo{id: String, aliases: Maybe<&2, List<&2, String>>, status: Status, architecture: Maybe<&2, Architecture>, source: Maybe<&2, String>, meta: Maybe<&2, Metadata>}

type LlamaServerProps is Data:
  LlamaServerProps{models_autoload: Maybe<&2, Bool>, chat_template: Maybe<&2, String>}

type LlamaClient is Data:
  LlamaClient{serverUrl: String, apiKey: Maybe<&2, String>, fetch: Fetch.Fetch(Unit), urlContext: URL.Context}

def leadingSlashes(text: String) -> String:
  match text:
    case SCon{'/', rest}: leadingSlashes(rest)
    case other: other

def trimSlashes(text: String) -> String:
  String.reverse(leadingSlashes(String.reverse(text)))

def managementPath(+path: String) -> String:
  Bool.pick(String, String.ends_with(path, "/v1"), String.take(path, String.length(path) - 3n), path)

def normalized(value: URL.URL) -> Result<&2, &2, String, String>:
  match value:
    case URL.URL{URL.Http{}, user, password, host, port, +path, _, _}:
      Done{trimSlashes(URL.serialize(URL.setPathname(URL.URL{URL.Http{}, user, password, host, port, path, None{}, None{}}, managementPath(trimSlashes(URL.serializePath(path)))), False{}))}
    case URL.URL{URL.Https{}, user, password, host, port, +path, _, _}:
      Done{trimSlashes(URL.serialize(URL.setPathname(URL.URL{URL.Https{}, user, password, host, port, path, None{}, None{}}, managementPath(trimSlashes(URL.serializePath(path)))), False{}))}
    case _: Fail{"Server URL must use http or https"}

def parsedUrl(value: Result<&2, &2, URL.Error, URL.URL>) -> Result<&2, &2, String, String>:
  match value:
    case Fail{_}: Fail{"Invalid server URL"}
    case Done{url}: normalized(url)

def normalizeLlamaServerUrl(context: URL.Context, value: String) -> Result<&2, &2, String, String>:
  parsedUrl(URL.parse(context, String.trim(value)))

def llamaInferenceUrl(context: URL.Context, value: String) -> Result<&2, &2, String, String>:
  Result.map(&2, &2, String, String, String, url => url ++ "/v1", normalizeLlamaServerUrl(context, value))

def create(fetch: Fetch.Fetch(Unit), +context: URL.Context, url: String, key: Maybe<&2, String>) -> Result<&2, &2, String, LlamaClient>:
  Result.map(&2, &2, String, String, LlamaClient, server => LlamaClient{server, key, fetch, context}, normalizeLlamaServerUrl(context, url))

def boolean(value: V.Value) -> Result<&2, &2, Json.Error, Bool>:
  match value:
    case V.Boolean{item}: Done{item}
    case _: Fail{Json.WrongType{Nil{}, "boolean"}}

def strings(value: V.Value) -> Result<&2, &2, Json.Error, List<&2, String>>: Json.list(~String, ~Json.string, value)

def modelStatus(value: V.Value) -> Result<&2, &2, Json.Error, LlamaModelStatus>:
  match value:
    case V.Text{"unloaded"}: Done{Unloaded{}}
    case V.Text{"loading"}: Done{Loading{}}
    case V.Text{"loaded"}: Done{Loaded{}}
    case V.Text{"downloading"}: Done{Downloading{}}
    case V.Text{"sleeping"}: Done{Sleeping{}}
    case _: Fail{Json.InvalidValue{Nil{}, "router model status"}}

def fileProgress(value: V.Value) -> Result<&2, &2, Json.Error, FileProgress>:
  do Result<&2, &2, Json.Error, FileProgress>:
    +fields : R.Record<V.Value> <- Json.object(value)
    done : F64 <- Json.required(F64, fields, "done", Json.number)
    total : F64 <- Json.required(F64, fields, "total", Json.number)
    return FileProgress{done, total}

def progressFields(fields: List<&2, R.Property<V.Value>>) -> Result<&2, &2, Json.Error, List<&2, R.Property<FileProgress>>>:
  match fields:
    case Nil{}: Done{Nil{}}
    case R.Property{+key, value} <> tail:
      do Result<&2, &2, Json.Error, List<&2, R.Property<FileProgress>>>:
        item : FileProgress <- Json.located(FileProgress, fileProgress(value), Json.Field{key})
        rest : List<&2, R.Property<FileProgress>> <- progressFields(tail)
        return R.Property{key, item} <> rest

def progress(value: V.Value) -> Result<&2, &2, Json.Error, R.Record<FileProgress>>:
  do Result<&2, &2, Json.Error, R.Record<FileProgress>>:
    fields : R.Record<V.Value> <- Json.object(value)
    entries : List<&2, R.Property<FileProgress>> <- progressFields(R.entries(V.Value, fields))
    return R.Record{entries}

def status(value: V.Value) -> Result<&2, &2, Json.Error, Status>:
  do Result<&2, &2, Json.Error, Status>:
    +fields : R.Record<V.Value> <- Json.object(value)
    state : LlamaModelStatus <- Json.required(LlamaModelStatus, fields, "value", modelStatus)
    args : Maybe<&2, List<&2, String>> <- Json.optional(List<&2, String>, fields, "args", strings)
    failed : Maybe<&2, Bool> <- Json.optional(Bool, fields, "failed", boolean)
    exit : Maybe<&2, F64> <- Json.optional(F64, fields, "exit_code", Json.number)
    files : Maybe<&2, R.Record<FileProgress>> <- Json.optional(R.Record<FileProgress>, fields, "progress", progress)
    return Status{state, args, failed, exit, files}

def architecture(value: V.Value) -> Result<&2, &2, Json.Error, Architecture>:
  do Result<&2, &2, Json.Error, Architecture>:
    +fields : R.Record<V.Value> <- Json.object(value)
    input : Maybe<&2, List<&2, String>> <- Json.optional(List<&2, String>, fields, "input_modalities", strings)
    output : Maybe<&2, List<&2, String>> <- Json.optional(List<&2, String>, fields, "output_modalities", strings)
    return Architecture{input, output}

def metadata(value: V.Value) -> Result<&2, &2, Json.Error, Metadata>:
  do Result<&2, &2, Json.Error, Metadata>:
    +fields : R.Record<V.Value> <- Json.object(value)
    ctx : Maybe<&2, F64> <- Json.optional(F64, fields, "n_ctx", Json.number)
    train : Maybe<&2, F64> <- Json.optional(F64, fields, "n_ctx_train", Json.number)
    size : Maybe<&2, F64> <- Json.optional(F64, fields, "size", Json.number)
    kind : Maybe<&2, String> <- Json.optional(String, fields, "ftype", Json.string)
    return Metadata{ctx, train, size, kind}

def modelInfo(value: V.Value) -> Result<&2, &2, Json.Error, LlamaModelInfo>:
  do Result<&2, &2, Json.Error, LlamaModelInfo>:
    +fields : R.Record<V.Value> <- Json.object(value)
    id : String <- Json.required(String, fields, "id", Json.string)
    aliases : Maybe<&2, List<&2, String>> <- Json.optional(List<&2, String>, fields, "aliases", strings)
    state : Status <- Json.required(Status, fields, "status", status)
    arch : Maybe<&2, Architecture> <- Json.optional(Architecture, fields, "architecture", architecture)
    source : Maybe<&2, String> <- Json.optional(String, fields, "source", Json.string)
    meta : Maybe<&2, Metadata> <- Json.optional(Metadata, fields, "meta", metadata)
    return LlamaModelInfo{id, aliases, state, arch, source, meta}

def modelList(value: V.Value) -> Result<&2, &2, Json.Error, List<&2, LlamaModelInfo>>: Json.list(~LlamaModelInfo, ~modelInfo, value)

def catalogResult(value: Result<&2, &2, Json.Error, List<&2, LlamaModelInfo>>) -> Result<&2, &2, String, List<&2, LlamaModelInfo>>:
  match value:
    case Done{models}: Done{models}
    case Fail{_}: Fail{"Server is not running in llama.cpp router mode"}

def catalogData(value: Maybe<&2, V.Value>) -> Result<&2, &2, String, List<&2, LlamaModelInfo>>:
  match value:
    case Some{V.ArrayValue{items}}: catalogResult(Json.items(~LlamaModelInfo, ~modelInfo, items, 0n))
    case _: Fail{"llama.cpp returned an invalid model catalog"}

def catalog(value: V.Value) -> Result<&2, &2, String, List<&2, LlamaModelInfo>>:
  match value:
    case V.ObjectValue{fields}: catalogData(R.get(V.Value, fields, "data"))
    case _: Fail{"llama.cpp returned an invalid model catalog"}

def decoded(-A: Data, value: Result<&2, &2, Json.Error, A>) -> Result<&2, &2, String, A>:
  match value:
    case Done{item}: Done{item}
    case Fail{error}: Fail{Json.describe(error)}

def propsValue(value: V.Value) -> Result<&2, &2, String, LlamaServerProps>:
  match value:
    case V.ObjectValue{+fields}:
      do Result<&2, &2, String, LlamaServerProps>:
        auto : Maybe<&2, Bool> <- decoded(Maybe<&2, Bool>, Json.optional(Bool, fields, "models_autoload", boolean))
        template : Maybe<&2, String> <- decoded(Maybe<&2, String>, Json.optional(String, fields, "chat_template", Json.string))
        return LlamaServerProps{auto, template}
    case _: Done{LlamaServerProps{None{}, None{}}}

def authorization(key: Maybe<&2, String>) -> List<&2, R.Property<String>>:
  match key:
    case Some{SCon{c, cs}}: [R.Property{"Authorization", "Bearer " ++ SCon{c, cs}}]
    case _: Nil{}

def requestHeaders(key: Maybe<&2, String>, body: Headers.Input) -> List<&2, R.Property<String>>:
  match body:
    case Headers.Absent{}: authorization(key)
    case _: R.Property{"Content-Type", "application/json"} <> authorization(key)

def errorMessage(value: Maybe<&2, V.Value>, fallback: String) -> String:
  match value:
    case Some{V.Text{SCon{c, cs}}}: SCon{c, cs}
    case _: fallback

def errorObject(value: Maybe<&2, V.Value>, fallback: String) -> String:
  match value:
    case Some{V.ObjectValue{fields}}: errorMessage(R.get(V.Value, fields, "message"), fallback)
    case _: fallback

def responseError(value: V.Value, fallback: String) -> String:
  match value:
    case V.ObjectValue{fields}: errorObject(R.get(V.Value, fields, "error"), fallback)
    case _: fallback

def reply(value: Result<&2, &2, HTTP.Failure, HTTP.Reply>) -> Result<&2, &2, String, V.Value>:
  match value:
    case Fail{error}: Fail{HTTP.failureText(error)}
    case Done{HTTP.Reply{+code, _, body}}:
      +parsed = Maybe.default(&2, V.Value, HTTP.jsonOf(Json.parse(body)), V.Null{})
      Bool.pick(Result<&2, &2, String, V.Value>, U32.is_ge(code, 200) && U32.is_lt(code, 300), Done{parsed}, Fail{responseError(parsed, "llama.cpp returned HTTP " ++ U32.show(code))})

def request(client: LlamaClient, path: String, method: String, +body: Headers.Input, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, V.Value>):
  match client:
    case LlamaClient{url, key, fetch, context}:
      do IO<Result<&2, &2, String, V.Value>>:
        received : Result<&2, &2, HTTP.Failure, HTTP.Reply> <- HTTP.request(~Unit, HTTP.Transport{fetch, context, signal}, method, url ++ path, requestHeaders(key, body), body, 15000)
        return reply(received)

def list(client: LlamaClient, reload: Bool, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, List<&2, LlamaModelInfo>>):
  do IO<Result<&2, &2, String, List<&2, LlamaModelInfo>>>:
    payload : Result<&2, &2, String, V.Value> <- request(client, Bool.pick(String, reload, "/models?reload=1", "/models"), "GET", Headers.Absent{}, signal)
    return Result.bind(&2, &2, String, V.Value, List<&2, LlamaModelInfo>, payload, catalog)

def propsQuery(model: Maybe<&2, String>) -> String:
  match model:
    case Some{SCon{c, cs}}: "?" ++ URL.serializeSearchParams([URL.Entry{"model", SCon{c, cs}}, URL.Entry{"autoload", "false"}])
    case _: ""

def props(client: LlamaClient, model: Maybe<&2, String>, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, LlamaServerProps>):
  do IO<Result<&2, &2, String, LlamaServerProps>>:
    payload : Result<&2, &2, String, V.Value> <- request(client, "/props" ++ propsQuery(model), "GET", Headers.Absent{}, signal)
    return Result.bind(&2, &2, String, V.Value, LlamaServerProps, payload, propsValue)

def command(client: LlamaClient, path: String, model: String, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    payload : Result<&2, &2, String, V.Value> <- request(client, path, "POST", Headers.Text{"{\"model\":" ++ Json.quote(model) ++ "}"}, signal)
    return Result.map(&2, &2, String, V.Value, Unit, _ => Unit{}, payload)

def load(client: LlamaClient, model: String, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Unit>): command(client, "/models/load", model, signal)

def unload(client: LlamaClient, model: String, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Unit>): command(client, "/models/unload", model, signal)

def download(client: LlamaClient, model: String, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Unit>): command(client, "/models", model, signal)

# Polling observes server state and ends on cancellation even if the router
# never finishes unloading. Every iteration releases its response before sleep.

def unloading(models: List<&2, LlamaModelInfo>, +model: String) -> Bool:
  match models:
    case Nil{}: False{}
    case LlamaModelInfo{id, _, Status{Unloaded{}, _, _, _, _}, _, _, _} <> rest:
      Bool.not(String.eq(id, model)) && unloading(rest, model)
    case LlamaModelInfo{id, _, _, _, _, _} <> rest: String.eq(id, model) || unloading(rest, model)

@unsafe
def unloadPoll(+client: LlamaClient, +model: String, +signal: Abort.AbortSignal<Unit>, result: Result<&2, &2, String, List<&2, LlamaModelInfo>>) -> IO(Result<&2, &2, String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{models}:
      Bool.pick(Unit -> IO(Result<&2, &2, String, Unit>), unloading(models, model), _ => do IO<Result<&2, &2, String, Unit>>:
        waited : Result<&2, &2, Abort.AbortReason<Unit>, Unit> <- Timer.sleep(Unit, 100, signal)
        # The next fetch checks the signal; an aborted wait cannot send.
        next : Result<&2, &2, String, List<&2, LlamaModelInfo>> <- list(client, False{}, signal)
        unloadPoll(client, model, signal, next)
      , _ => IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}}))(Unit{})

def unloadingStarted(+client: LlamaClient, +model: String, +signal: Abort.AbortSignal<Unit>, result: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, Unit>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, String, Unit>>:
        models : Result<&2, &2, String, List<&2, LlamaModelInfo>> <- list(client, False{}, signal)
        unloadPoll(client, model, signal, models)

def unloadAndWait(+client: LlamaClient, +model: String, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Unit>):
  do IO<Result<&2, &2, String, Unit>>:
    result : Result<&2, &2, String, Unit> <- unload(client, model, signal)
    unloadingStarted(client, model, signal, result)

# Event payloads are open protocol data; catalogs and UI progress remain typed.
type LlamaModelEvent is Data:
  LlamaModelEvent{model: String, event: String, data: Maybe<&2, V.Value>}

type LlamaProgress is Data:
  LlamaProgress{message: String, ratio: Maybe<&2, F64>, detail: Maybe<&2, String>}

type DownloadBytes is Data:
  DownloadBytes{done: F64, total: F64}

def textField(value: Maybe<&2, V.Value>) -> Maybe<&2, String>:
  match value:
    case Some{V.Text{item}}: Some{item}
    case _: None{}

def numberField(value: Maybe<&2, V.Value>) -> Maybe<&2, F64>:
  match value:
    case Some{V.Number{item}}: Some{item}
    case _: None{}

def objectField(value: Maybe<&2, V.Value>) -> Maybe<&2, R.Record<V.Value>>:
  match value:
    case Some{V.ObjectValue{item}}: Some{item}
    case _: None{}

def clamp(+ratio: F64) -> F64:
  Bool.pick(F64, F64.is_lt(ratio, F.fromU32(0)), F.fromU32(0), Bool.pick(F64, F64.is_gt(ratio, F.fromU32(1)), F.fromU32(1), ratio))

def textItems(values: List<&2, V.Value>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case V.Text{text} <> rest: text <> textItems(rest)
    case _ <> rest: textItems(rest)

def stageNames(value: Maybe<&2, V.Value>) -> List<&2, String>:
  match value:
    case Some{V.ArrayValue{items}}: textItems(items)
    case _: Nil{}

def stageIndex(stages: List<&2, String>, +stage: String, +index: Nat) -> Maybe<&2, Nat>:
  match stages:
    case Nil{}: None{}
    case name <> rest:
      Bool.pick(Unit -> Maybe<&2, Nat>, String.eq(name, stage), _ => Some{index}, _ => stageIndex(rest, stage, index + 1n))(Unit{})

def combinedRatio(index: Maybe<&2, Nat>, count: Nat, +ratio: Maybe<&2, F64>) -> Maybe<&2, F64>:
  match index:
    case None{}: ratio
    case Some{value}: Some{F.divide(F.add(F.fromNat(value), Maybe.default(&2, F64, ratio, F.fromU32(0))), F.fromNat(count))}

def loadStage(stage: Maybe<&2, String>, +stages: List<&2, String>, ratio: Maybe<&2, F64>) -> LlamaProgress:
  match stage:
    case None{}: LlamaProgress{"Loading model", ratio, None{}}
    case Some{+name}: LlamaProgress{"Loading " ++ String.join(String.split(name, '_'), " "), combinedRatio(stageIndex(stages, name, 0n), List.length(&2, String, stages), ratio), None{}}

def parseLoadFields(+fields: R.Record<V.Value>) -> LlamaProgress:
  +stage = textField(R.get(V.Value, fields, "current"))
  loadStage(Maybe.or(&2, String, stage, textField(R.get(V.Value, fields, "stage"))), stageNames(R.get(V.Value, fields, "stages")), Maybe.map(&2, F64, F64, ratio => clamp(ratio), numberField(R.get(V.Value, fields, "value"))))

def parseLoadObject(fields: Maybe<&2, R.Record<V.Value>>) -> Maybe<&2, LlamaProgress>:
  match fields:
    case Some{item}: Some{parseLoadFields(item)}
    case None{}: None{}

def parseLoadProgress(data: V.Value) -> Maybe<&2, LlamaProgress>:
  match data:
    case V.ObjectValue{fields}: parseLoadObject(objectField(R.get(V.Value, fields, "progress")))
    case _: None{}

def byteUnit(units: List<&2, String>, +bytes: F64) -> String:
  match units:
    case Nil{}: ""
    case unit <> Nil{}: Maybe.default(&2, String, Number.formatFixed(bytes, Bool.pick(Nat, F64.is_ge(bytes, F.fromU32(10)), 1n, 2n)), "0") ++ " " ++ unit
    case unit <> rest:
      Bool.pick(Unit -> String, F64.is_ge(bytes, F.fromU32(1024)), _ => byteUnit(rest, F.divide(bytes, F.fromU32(1024))), _ => Maybe.default(&2, String, Number.formatFixed(bytes, Bool.pick(Nat, F64.is_ge(bytes, F.fromU32(10)), 1n, 2n)), "0") ++ " " ++ unit)(Unit{})

def formatBytes(+bytes: F64) -> String:
  Bool.pick(Unit -> String, F64.is_lt(bytes, F.fromU32(1024)), _ => F64.show(bytes) ++ " B", _ => byteUnit(["KiB", "MiB", "GiB", "TiB"], F.divide(bytes, F.fromU32(1024))))(Unit{})

def addCounts(done: Maybe<&2, F64>, total: Maybe<&2, F64>, current: DownloadBytes) -> DownloadBytes:
  match done total current:
    case Some{a} Some{b} DownloadBytes{c, d}: DownloadBytes{F.add(a, c), F.add(b, d)}
    case _ _ other: other

def addFile(value: V.Value, current: DownloadBytes) -> DownloadBytes:
  match value current:
    case V.ObjectValue{+fields} DownloadBytes{done, total}:
      addCounts(numberField(R.get(V.Value, fields, "done")), numberField(R.get(V.Value, fields, "total")), DownloadBytes{done, total})
    case _ other: other

def sumFiles(values: List<&2, R.Property<V.Value>>, current: DownloadBytes) -> DownloadBytes:
  match values:
    case Nil{}: current
    case R.Property{_, value} <> rest: sumFiles(rest, addFile(value, current))

def byteProgress(+done: F64, +total: F64) -> Maybe<&2, LlamaProgress>:
  Bool.pick(Maybe<&2, LlamaProgress>, F64.is_gt(total, F.fromU32(0)), Some{LlamaProgress{"Downloading model", Some{F.divide(done, total)}, Some{formatBytes(done) ++ " / " ++ formatBytes(total)}}}, None{})

def downloadTotals(value: DownloadBytes) -> Maybe<&2, LlamaProgress>:
  match value:
    case DownloadBytes{done, total}: byteProgress(done, total)

def downloadFiles(fields: R.Record<V.Value>) -> Maybe<&2, LlamaProgress>:
  downloadTotals(sumFiles(R.entries(V.Value, fields), DownloadBytes{F.fromU32(0), F.fromU32(0)}))

def parseDownloadProgress(data: V.Value) -> Maybe<&2, LlamaProgress>:
  match data:
    case V.ObjectValue{+fields}: downloadFiles(Maybe.default(&2, R.Record<V.Value>, objectField(R.get(V.Value, fields, "progress")), fields))
    case _: None{}

def modelEvent(value: V.Value) -> Result<&2, &2, Json.Error, LlamaModelEvent>:
  do Result<&2, &2, Json.Error, LlamaModelEvent>:
    +fields : R.Record<V.Value> <- Json.object(value)
    model : String <- Json.required(String, fields, "model", Json.string)
    event : String <- Json.required(String, fields, "event", Json.string)
    return LlamaModelEvent{model, event, R.get(V.Value, fields, "data")}

def eventDecoded(value: Result<&2, &2, Json.Error, LlamaModelEvent>) -> Maybe<&2, LlamaModelEvent>:
  match value:
    case Fail{_}: None{}
    case Done{item}: Some{item}

# Catalog polling remains authoritative if a server sends unrelated or
# malformed events. Each cursor has one reader; all exit paths release it.
def eventJson(value: Result<&2, &2, Json.ParseError, V.Value>) -> Maybe<&2, LlamaModelEvent>:
  match value:
    case Fail{_}: None{}
    case Done{item}: eventDecoded(modelEvent(item))

def eventFrame(value: SSE.ServerSentEvent) -> Maybe<&2, LlamaModelEvent>:
  match value:
    case SSE.ServerSentEvent{_, data, _}: eventJson(Json.parse(data))

def notifyEvent(callback: C.Callback<LlamaModelEvent, Unit>, value: Maybe<&2, LlamaModelEvent>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit, Unit{})
    case Some{event}: C.call(LlamaModelEvent, Unit, callback, event)

@unsafe
def watchNext(+onEvent: C.Callback<LlamaModelEvent, Unit>, next: SSE.Next<Reader.ReadError(Unit)>) -> IO(Result<&2, &2, String, Unit>):
  match next:
    case SSE.Next{_, Fail{_}}: IO.pure(Result<&2, &2, String, Unit>, Fail{"llama.cpp event stream failed"})
    case SSE.Next{_, Done{None{}}}: IO.pure(Result<&2, &2, String, Unit>, Done{Unit{}})
    case SSE.Next{cursor, Done{Some{frame}}}:
      do IO<Result<&2, &2, String, Unit>>:
        notifyEvent(onEvent, eventFrame(frame))
        following : SSE.Next<Reader.ReadError(Unit)> <- SSE.nextReader(Reader.ReadError(Unit), cursor)
        watchNext(onEvent, following)

def watched(onEvent: C.Callback<LlamaModelEvent, Unit>, pair: Reader.Owner(Unit) & Reader.Source(Unit)) -> IO(Result<&2, &2, String, Unit>):
  match pair:
    case (owner, source):
      do IO<Result<&2, &2, String, Unit>>:
        first : SSE.Next<Reader.ReadError(Unit)> <- SSE.nextReader(Reader.ReadError(Unit), SSE.createReader(Reader.ReadError(Unit), source))
        result : Result<&2, &2, String, Unit> <- watchNext(onEvent, first)
        Reader.release(~Unit, owner)
        return result

def rejectedWatch(code: U32, pair: Reader.Owner(Unit) & Reader.Source(Unit)) -> IO(Result<&2, &2, String, Unit>):
  match pair:
    case (owner, _):
      do IO<Result<&2, &2, String, Unit>>:
        Reader.release(~Unit, owner)
        return Fail{"llama.cpp SSE returned HTTP " ++ U32.show(code)}

def watchStatus(+onEvent: C.Callback<LlamaModelEvent, Unit>, +code: U32, pair: Reader.Owner(Unit) & Reader.Source(Unit)) -> IO(Result<&2, &2, String, Unit>):
  Bool.pick((Reader.Owner(Unit) & Reader.Source(Unit)) -> IO(Result<&2, &2, String, Unit>), U32.is_ge(code, 200) && U32.is_lt(code, 300), owned => watched(onEvent, owned), owned => rejectedWatch(code, owned))(pair)

def watchResponse(onEvent: C.Callback<LlamaModelEvent, Unit>, response: Fetch.Result_(Unit)) -> IO(Result<&2, &2, String, Unit>):
  match response:
    case Fail{_}: IO.pure(Result<&2, &2, String, Unit>, Fail{"fetch failed"})
    case Done{Response.Response{metadata, body}}:
      do IO<Result<&2, &2, String, Unit>>:
        pair : Reader.Owner(Unit) & Reader.Source(Unit) <- Reader.reader(~Unit, body)
        watchStatus(onEvent, Response.metadataStatus(metadata), pair)

def watchBorrowed(fetch: Fetch.Fetch(Unit), onEvent: C.Callback<LlamaModelEvent, Unit>, url: URL.URL, headers: Headers.Headers, pair: Deadline.Scope<Unit> & Fetch.Signal(Unit)) -> IO(Result<&2, &2, String, Unit>):
  match pair:
    case (scope, signal):
      do IO<Result<&2, &2, String, Unit>>:
        response : Fetch.Result_(Unit) <- C.call(Fetch.Input<Unit>, Fetch.Result_(Unit), fetch, Fetch.Input{url, "GET", headers, Headers.Absent{}, signal})
        result : Result<&2, &2, String, Unit> <- watchResponse(onEvent, response)
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Unit>>> <- Deadline.close(Unit, scope)
        return result

def watchAddress(client: LlamaClient, onEvent: C.Callback<LlamaModelEvent, Unit>, scope: Deadline.Scope<Unit>, url: Result<&2, &2, URL.Error, URL.URL>, headers: Result<&2, &2, Headers.HeaderSyntaxError, Headers.Headers>) -> IO(Result<&2, &2, String, Unit>):
  match client url headers:
    case LlamaClient{_, _, fetch, _} Done{address} Done{fields}:
      watchBorrowed(fetch, onEvent, address, fields, Deadline.borrow(Unit, scope))
    case _ _ _:
      do IO<Result<&2, &2, String, Unit>>:
        closed : Maybe<&2, Abort.AbortReason<Deadline.Cause<Unit>>> <- Deadline.close(Unit, scope)
        return Fail{"Invalid event stream request"}

def watch(+client: LlamaClient, onEvent: C.Callback<LlamaModelEvent, Unit>, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Unit>):
  match client:
    case LlamaClient{+url, key, _, +context}:
      do IO<Result<&2, &2, String, Unit>>:
        timed : Deadline.Scope<Unit> <- Deadline.create(Unit, HTTP.NO_TIMEOUT(), signal)
        scope : Deadline.Scope<Unit> <- Deadline.disarm(Unit, timed)
        watchAddress(client, onEvent, scope, URL.parse(context, url ++ "/models/sse"), Reader.headerList(authorization(key)))

# One immutable operation state is shared between the catalog poller and its
# event observer. The observer never publishes a catalog itself.
type Operation is Data:
  LoadingOperation{loaded: Bool, failure: Maybe<&2, String>}
  DownloadOperation{finished: Bool, failure: Maybe<&2, String>, downloading: Bool, polls: Nat}

type Observer is Data:
  Observer{model: String, operation: Ref.Ref<Operation>, progress: C.Callback<LlamaProgress, Unit>}

# The only owners are the forwarding task and the event task. Stop cancels
# their observation and child signal, joins both, then disposes callback/state.
type Watching is Type:
  Watching{controller: Abort.AbortController<Unit>, link: D.Cancellation<Abort.AbortReason<Unit>>, forwarding: Chan(Unit), worker: Chan(Result<&2, &2, String, Unit>), callback: C.Callback<LlamaModelEvent, Unit>}


type PollResult is Data:
  LoadedResult{model: LlamaModelInfo}
  DownloadedResult{models: List<&2, LlamaModelInfo>}


type PollDecision is Data:
  Complete{result: PollResult}
  Refresh{}
  Pending{sleep: U32, progress: Maybe<&2, LlamaProgress>}
  Failed{message: String}

def eventStatus(data: V.Value) -> Maybe<&2, String>:
  match data:
    case V.ObjectValue{fields}: textField(R.get(V.Value, fields, "status"))
    case _: None{}

def loadEvent(+loaded: Bool, +failure: Maybe<&2, String>, +data: V.Value) -> Operation & Maybe<&2, LlamaProgress>:
  +status = eventStatus(data)
  (LoadingOperation{loaded || String.eq(Maybe.default(&2, String, status, ""), "loaded"), Bool.pick(Maybe<&2, String>, String.eq(Maybe.default(&2, String, status, ""), "unloaded"), Some{"Model failed to load"}, failure)}, parseLoadProgress(data))

def observedEvent(operation: Operation, event: String, +data: V.Value) -> Operation & Maybe<&2, LlamaProgress>:
  match operation event:
    case LoadingOperation{loaded, failure} "model_status": loadEvent(loaded, failure, data)
    case LoadingOperation{loaded, failure} "status_change": loadEvent(loaded, failure, data)
    case DownloadOperation{_, failure, downloading, polls} "download_finished": (DownloadOperation{True{}, failure, downloading, polls}, None{})
    case DownloadOperation{finished, _, downloading, polls} "download_failed": (DownloadOperation{finished, Some{responseError(data, "Download failed")}, downloading, polls}, None{})
    case DownloadOperation{finished, failure, _, polls} "download_progress": (DownloadOperation{finished, failure, True{}, polls}, parseDownloadProgress(data))
    case other _: (other, None{})

def modelObserved(operation: Operation, +model: String, event: LlamaModelEvent) -> Operation & Maybe<&2, LlamaProgress>:
  match event:
    case LlamaModelEvent{id, kind, data}:
      Bool.pick(Operation -> (Operation & Maybe<&2, LlamaProgress>), String.eq(id, model), current => observedEvent(current, kind, Maybe.default(&2, V.Value, data, V.Null{})), current => (current, None{}))(operation)

def reportProgress(callback: C.Callback<LlamaProgress, Unit>, progress: Maybe<&2, LlamaProgress>) -> IO(Unit):
  match progress:
    case None{}: IO.pure(Unit, Unit{})
    case Some{value}: C.call(LlamaProgress, Unit, callback, value)

def observeOperation(observer: Observer, event: LlamaModelEvent) -> IO(Unit):
  match observer:
    case Observer{model, operation, callback}:
      do IO<Unit>:
        progress : Maybe<&2, LlamaProgress> <- Ref.modify(Operation, Maybe<&2, LlamaProgress>, operation, current => modelObserved(current, model, event))
        reportProgress(callback, progress)

def forwardAbort(controller: Abort.AbortController<Unit>, reason: Maybe<&2, Abort.AbortReason<Unit>>) -> IO(Unit):
  match reason:
    case None{}: IO.pure(Unit, Unit{})
    case Some{Abort.DefaultAbort{}}:
      do IO<Unit>:
        changed : Bool <- Abort.abort(Unit, controller, None{})
        return Unit{}
    case Some{Abort.Supplied{value}}:
      do IO<Unit>:
        changed : Bool <- Abort.abort(Unit, controller, Some{value})
        return Unit{}

def forwardParent(controller: Abort.AbortController<Unit>, ticket: D.Ticket<Maybe<&2, Abort.AbortReason<Unit>>>) -> IO(Unit):
  do IO<Unit>:
    reason : Maybe<&2, Abort.AbortReason<Unit>> <- D.wait(Maybe<&2, Abort.AbortReason<Unit>>, ticket)
    forwardAbort(controller, reason)

def startWatching(+client: LlamaClient, +observer: Observer, +controller: Abort.AbortController<Unit>, observation: D.Observation<Abort.AbortReason<Unit>>) -> IO(Watching):
  match observation:
    case D.Observation{ticket, cancellation}:
      do IO<Watching>:
        +callback : C.Callback<LlamaModelEvent, Unit> <- C.create(~Observer, ~LlamaModelEvent, ~Unit, ~observeOperation, observer)
        parent : Chan(Unit) <- IO.fork(Unit, forwardParent(controller, ticket))
        worker : Chan(Result<&2, &2, String, Unit>) <- IO.fork(Result<&2, &2, String, Unit>, watch(client, callback, Abort.signal(Unit, controller)))
        return Watching{controller, cancellation, parent, worker, callback}

def watchOperation(client: LlamaClient, observer: Observer, +signal: Abort.AbortSignal<Unit>) -> IO(Watching):
  do IO<Watching>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    parent : D.Observation<Abort.AbortReason<Unit>> <- Abort.observe(Unit, signal)
    ready : Maybe<&2, Abort.AbortReason<Unit>> <- Abort.reason(Unit, signal)
    forwardAbort(controller, ready)
    startWatching(client, observer, controller, parent)

def stopWatching(watching: Watching) -> IO(Unit):
  match watching:
    case Watching{+controller, link, parent, worker, callback}:
      do IO<Unit>:
        removed : Bool <- D.cancel(Abort.AbortReason<Unit>, link)
        aborted : Bool <- Abort.abort(Unit, controller, None{})
        IO.join(Unit, parent)
        result : Result<&2, &2, String, Unit> <- IO.join(Result<&2, &2, String, Unit>, worker)
        C.dispose(LlamaModelEvent, Unit, callback)
        Abort.dispose(Unit, controller)
        return Unit{}

def findModel(models: List<&2, LlamaModelInfo>, +model: String) -> Maybe<&2, LlamaModelInfo>:
  match models:
    case Nil{}: None{}
    case LlamaModelInfo{+id, aliases, status, arch, source, meta} <> rest:
      Bool.pick(Unit -> Maybe<&2, LlamaModelInfo>, String.eq(id, model), _ => Some{LlamaModelInfo{id, aliases, status, arch, source, meta}}, _ => findModel(rest, model))(Unit{})

def loadFailure(code: Maybe<&2, F64>, failure: Maybe<&2, String>) -> String:
  match code:
    case Some{value}: "Model exited with code " ++ F64.show(value)
    case None{}: Maybe.default(&2, String, failure, "Model failed to load")

def loadedModel(model: String) -> LlamaModelInfo:
  LlamaModelInfo{model, None{}, Status{Loaded{}, None{}, None{}, None{}, None{}}, None{}, None{}, None{}}

def loadedDecision(model: String, loaded: Bool, +failure: Maybe<&2, String>, entry: Maybe<&2, LlamaModelInfo>) -> PollDecision:
  match entry:
    case Some{LlamaModelInfo{id, aliases, Status{Loaded{}, args, failed, exit, progress}, arch, source, meta}}:
      Complete{LoadedResult{LlamaModelInfo{id, aliases, Status{Loaded{}, args, failed, exit, progress}, arch, source, meta}}}
    case None{}:
      Bool.pick(PollDecision, loaded, Complete{LoadedResult{loadedModel(model)}}, Bool.pick(PollDecision, Maybe.is_none(&2, String, failure), Pending{250, None{}}, Failed{Maybe.default(&2, String, failure, "Model failed to load")}))
    case Some{LlamaModelInfo{_, _, Status{_, _, failed, exit, _}, _, _, _}}:
      Bool.pick(PollDecision, Maybe.default(&2, Bool, failed, False{}) || Bool.not(Maybe.is_none(&2, String, failure)), Failed{loadFailure(exit, failure)}, Pending{250, None{}})

def fileTotals(values: List<&2, R.Property<FileProgress>>, done: F64, total: F64) -> DownloadBytes:
  match values:
    case Nil{}: DownloadBytes{done, total}
    case R.Property{_, FileProgress{a, b}} <> rest: fileTotals(rest, F.add(done, a), F.add(total, b))

def catalogProgress(files: Maybe<&2, R.Record<FileProgress>>) -> Maybe<&2, LlamaProgress>:
  match files:
    case None{}: None{}
    case Some{fields}: downloadTotals(fileTotals(R.entries(FileProgress, fields), F.fromU32(0), F.fromU32(0)))

def downloadDecision(finished: Bool, failure: Maybe<&2, String>, downloading: Bool, polls: Nat, entry: Maybe<&2, LlamaModelInfo>) -> PollDecision:
  match failure entry:
    case Some{error} _: Failed{error}
    case None{} Some{LlamaModelInfo{_, _, Status{Downloading{}, _, _, _, files}, _, _, _}}: Pending{500, catalogProgress(files)}
    case None{} Some{_}: Bool.pick(PollDecision, finished || downloading || Nat.is_ge(polls, 2n), Refresh{}, Pending{500, None{}})
    case None{} None{}: Bool.pick(PollDecision, finished, Refresh{}, Pending{500, None{}})

def isDownloading(entry: Maybe<&2, LlamaModelInfo>) -> Bool:
  match entry:
    case Some{LlamaModelInfo{_, _, Status{Downloading{}, _, _, _, _}, _, _, _}}: True{}
    case _: False{}

# Polling is bounded by caller cancellation and by server terminal state.
# Responses are consumed before sleeping; event callbacks share only Ref data.
def downloadPolled(+finished: Bool, +failure: Maybe<&2, String>, +downloading: Bool, +polls: Nat, +entry: Maybe<&2, LlamaModelInfo>) -> Operation & PollDecision:
  (DownloadOperation{finished, failure, downloading || isDownloading(entry), polls}, downloadDecision(finished, failure, downloading, polls, entry))

def polled(operation: Operation, +model: String, +models: List<&2, LlamaModelInfo>) -> Operation & PollDecision:
  match operation:
    case LoadingOperation{+loaded, +failure}: (LoadingOperation{loaded, failure}, loadedDecision(model, loaded, failure, findModel(models, model)))
    case DownloadOperation{+finished, +failure, +downloading, +polls}:
      downloadPolled(finished, failure, downloading, polls + 1n, findModel(models, model))

def reportOperation(observer: Observer, progress: Maybe<&2, LlamaProgress>) -> IO(Unit):
  match observer:
    case Observer{_, _, callback}: reportProgress(callback, progress)

def decidePoll(observer: Observer, models: Result<&2, &2, String, List<&2, LlamaModelInfo>>) -> IO(PollDecision):
  match observer models:
    case _ Fail{error}: IO.pure(PollDecision, Failed{error})
    case Observer{model, operation, _} Done{items}: Ref.modify(Operation, PollDecision, operation, current => polled(current, model, items))

def operationState(observer: Observer) -> IO(Operation):
  match observer:
    case Observer{_, operation, _}: Ref.read(Operation, operation)

def allowedPoll(+client: LlamaClient, +observer: Observer, +signal: Abort.AbortSignal<Unit>, aborted: Bool, operation: Operation) -> IO(PollDecision):
  match aborted operation:
    case True{} _: IO.pure(PollDecision, Failed{"This operation was aborted"})
    case False{} DownloadOperation{_, Some{failure}, _, _}: IO.pure(PollDecision, Failed{failure})
    case _ _:
      do IO<PollDecision>:
        models : Result<&2, &2, String, List<&2, LlamaModelInfo>> <- list(client, False{}, signal)
        decidePoll(observer, models)

def readPoll(+client: LlamaClient, +observer: Observer, +signal: Abort.AbortSignal<Unit>) -> IO(PollDecision):
  do IO<PollDecision>:
    aborted : Bool <- Abort.aborted(Unit, signal)
    operation : Operation <- operationState(observer)
    allowedPoll(client, observer, signal, aborted, operation)

@unsafe
def pollOperation(+client: LlamaClient, +observer: Observer, +signal: Abort.AbortSignal<Unit>, decision: PollDecision) -> IO(Result<&2, &2, String, PollResult>):
  match decision:
    case Complete{result}: IO.pure(Result<&2, &2, String, PollResult>, Done{result})
    case Failed{message}: IO.pure(Result<&2, &2, String, PollResult>, Fail{message})
    case Refresh{}:
      do IO<Result<&2, &2, String, PollResult>>:
        models : Result<&2, &2, String, List<&2, LlamaModelInfo>> <- list(client, True{}, signal)
        return Result.map(&2, &2, String, List<&2, LlamaModelInfo>, PollResult, items => DownloadedResult{items}, models)
    case Pending{sleep, progress}:
      do IO<Result<&2, &2, String, PollResult>>:
        reportOperation(observer, progress)
        pause : Result<&2, &2, Abort.AbortReason<Unit>, Unit> <- Timer.sleep(Unit, sleep, signal)
        next : PollDecision <- readPoll(client, observer, signal)
        pollOperation(client, observer, signal, next)

def operationMessage(operation: Operation) -> String:
  match operation:
    case LoadingOperation{_, _}: "Loading model"
    case DownloadOperation{_, _, _, _}: "Downloading model"

def beginOperation(+client: LlamaClient, +observer: Observer, +signal: Abort.AbortSignal<Unit>, result: Result<&2, &2, String, Unit>) -> IO(Result<&2, &2, String, PollResult>):
  match result:
    case Fail{error}: IO.pure(Result<&2, &2, String, PollResult>, Fail{error})
    case Done{_}:
      do IO<Result<&2, &2, String, PollResult>>:
        initial : Operation <- operationState(observer)
        reportOperation(observer, Some{LlamaProgress{operationMessage(initial), None{}, None{}}})
        decision : PollDecision <- readPoll(client, observer, signal)
        pollOperation(client, observer, signal, decision)

def issueOperation(+client: LlamaClient, +model: String, operation: Operation, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, Unit>):
  match operation:
    case LoadingOperation{_, _}: load(client, model, signal)
    case DownloadOperation{_, _, _, _}: download(client, model, signal)

def runOperation(+client: LlamaClient, +model: String, +operation: Operation, callback: C.Callback<LlamaProgress, Unit>, +signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, PollResult>):
  do IO<Result<&2, &2, String, PollResult>>:
    +state : Ref.Ref<Operation> <- Ref.new(Operation, operation)
    +observer : Observer <- IO.pure(Observer, Observer{model, state, callback})
    watcher : Watching <- watchOperation(client, observer, signal)
    requested : Result<&2, &2, String, Unit> <- issueOperation(client, model, operation, signal)
    result : Result<&2, &2, String, PollResult> <- beginOperation(client, observer, signal, requested)
    stopWatching(watcher)
    final : Operation <- Ref.dispose(Operation, state)
    return result

def loadResult(result: Result<&2, &2, String, PollResult>) -> Result<&2, &2, String, LlamaModelInfo>:
  match result:
    case Fail{error}: Fail{error}
    case Done{LoadedResult{model}}: Done{model}
    case _: Fail{"Unexpected download result"}

def downloadResult(result: Result<&2, &2, String, PollResult>) -> Result<&2, &2, String, List<&2, LlamaModelInfo>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{DownloadedResult{models}}: Done{models}
    case _: Fail{"Unexpected load result"}

def loadAndWait(client: LlamaClient, model: String, progress: C.Callback<LlamaProgress, Unit>, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, LlamaModelInfo>):
  do IO<Result<&2, &2, String, LlamaModelInfo>>:
    result : Result<&2, &2, String, PollResult> <- runOperation(client, model, LoadingOperation{False{}, None{}}, progress, signal)
    return loadResult(result)

def downloadAndWait(client: LlamaClient, model: String, progress: C.Callback<LlamaProgress, Unit>, signal: Abort.AbortSignal<Unit>) -> IO(Result<&2, &2, String, List<&2, LlamaModelInfo>>):
  do IO<Result<&2, &2, String, List<&2, LlamaModelInfo>>>:
    result : Result<&2, &2, String, PollResult> <- runOperation(client, model, DownloadOperation{False{}, None{}, False{}, 0n}, progress, signal)
    return downloadResult(result)
