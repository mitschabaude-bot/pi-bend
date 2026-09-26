import Base
import ../../../../runtime/src/abort.bend as Abort
import ../../../../runtime/src/fetch.bend as Fetch
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
