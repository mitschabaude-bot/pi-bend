import Base
import ../src/api/openrouter-images.bend as OpenRouter
import ../src/api/openai-client.bend as Client
import ../src/images.bend as Images
import ../src/images-models.bend as ImagesModels
import ../src/image-models.bend as Catalog
import ../src/providers/images/register-builtins.bend as Builtins
import ../src/types.bend as T
import ../src/utils/json.bend as JsonWire
import ../../runtime/src/abort.bend as Abort
import ../../runtime/src/callback.bend as C
import ../../runtime/src/connection-driver.bend as Connect
import ../../runtime/src/dns-resolver.bend as DNS
import ../../runtime/src/f64.bend as F
import ../../runtime/src/fetch.bend as Fetch
import ../../runtime/src/http-exchange.bend as HTTP
import ../../runtime/src/http-message.bend as Headers
import ../../runtime/src/http-response.bend as Response
import ../../runtime/src/idna.bend as IDNA
import ../../runtime/src/record.bend as R
import ../../runtime/src/unicode-17-idna-mapping.bend as Mapping
import ../../runtime/src/unicode-17-idna-properties.bend as Properties
import ../../runtime/src/unicode-17-normalization.bend as Normalization
import ../../runtime/src/url.bend as URL

# upstream openrouter-images.test.ts and further request/response cases of
# api/openrouter-images.ts against a loopback server run by
# tests/openrouter_images_check.py: `openrouter-images <case> <baseUrl>`
# generates once through images.ts's generateImages (the built-in images api
# registry) and prints the payload onPayload saw, the onResponse value and
# the result (without its timestamp) as JSON lines. The checker asserts the
# upstream expectations and compares with upstream images.ts driving the
# pinned OpenAI SDK against the same server (openrouter-images-oracle.ts).

def J() -> Data: T.JsonValue

def Error() -> Data: String

def Model() -> Data: T.ImagesModel<J()>

def Options() -> Data: ImagesModels.Options(Error())

def urlContext() -> URL.Context:
  URL.Context{IDNA.Context{Mapping.table(), Normalization.tables(), Properties.table()}, IDNA.Options{IDNA.LabelOptions{False{}, False{}, True{}, IDNA.Nontransitional{}}, True{}, False{}}}

def networkOptions() -> HTTP.Options:
  HTTP.Options{DNS.IPv4First{}, Connect.IPv4First{}, 10000, 16384, Response.Limits{8192n, 65536n, 100n, 8n, Headers.Limits{8192n, 8192n, 65536n, 100n}}}

def render(value: Error()) -> String: value

def zero() -> F64: F.fromU32(0)

def jsonText(value: J()) -> String: Maybe.default(&2, String, JsonWire.stringify(value), "null")

def jstr(value: String) -> J(): T.JsonString{value}

def jnum(value: F64) -> J(): T.JsonNumber{value}

def jobj(fields: List<&2, R.Property<J()>>) -> J(): T.JsonObject{R.Record{fields}}

def prop(name: String, value: J()) -> R.Property<J()>: R.Property{name, value}

# Models
# ------

def cost(input: F64, output: F64, read: F64, write: F64) -> T.ModelCost: T.ModelCost{input, output, read, write, None{}}

def thousandths(value: U32) -> F64: F.divide(F.fromU32(value), F.fromU32(1000))

# The two models of upstream openrouter-images.test.ts.
def geminiImage(baseUrl: String) -> Model():
  T.ImagesModel{"google/gemini-3.1-flash-image-preview", "Gemini 3.1 Flash Image Preview", "openrouter-images", "openrouter", baseUrl, None{}, [T.InputText{}, T.InputImage{}], None{}, cost(thousandths(15), thousandths(30), zero(), zero()), None{}, None{}, Some{R.Record{[R.Property{"HTTP-Referer", "https://example.com"}]}}, [T.InputText{}, T.InputImage{}]}

def flux(baseUrl: String) -> Model():
  T.ImagesModel{"black-forest-labs/flux.2-pro", "FLUX.2 Pro", "openrouter-images", "openrouter", baseUrl, None{}, [T.InputText{}, T.InputImage{}], None{}, cost(thousandths(15), thousandths(30), zero(), zero()), None{}, None{}, None{}, [T.InputImage{}]}

def priced(baseUrl: String) -> Model():
  T.ImagesModel{"priced/image-model", "Priced", "openrouter-images", "openrouter", baseUrl, None{}, [T.InputText{}], None{}, cost(F.fromU32(2), F.fromU32(4), F.divide(F.fromU32(1), F.fromU32(2)), F.divide(F.fromU32(5), F.fromU32(4))), None{}, None{}, None{}, [T.InputImage{}, T.InputText{}]}

def withBase(model: Maybe<&2, Model()>, baseUrl: String) -> Model():
  match model:
    case Some{T.ImagesModel{id, name, api, provider, _, levels, input, limits, price, cache, sampling, headers, output}}: T.ImagesModel{id, name, api, provider, baseUrl, levels, input, limits, price, cache, sampling, headers, output}
    case None{}: flux(baseUrl)

# The catalog entry, pointed at the loopback server.
def catalogModel(baseUrl: String) -> Model(): withBase(Catalog.getImageModel("openrouter", "google/gemini-2.5-flash-image"), baseUrl)

# Contexts
# --------

def prompt(text: String) -> T.ImagesContext: T.ImagesContext{[T.TextImageText{T.TextContent{text, None{}}}]}

def dog() -> T.ImagesContext: prompt("Generate a dog")

def withImage() -> T.ImagesContext: T.ImagesContext{[T.TextImageText{T.TextContent{"Make it blue", None{}}}, T.TextImageImage{T.ImageContent{"aGVsbG8=", "image/png"}}]}

# Options
# -------

def options(key: Maybe<&2, String>, signal: Maybe<&2, Abort.AbortSignal<Unit>>, onPayload: Maybe<&2, T.PayloadCallback(J(), Model(), Error())>, onResponse: Maybe<&2, T.ResponseCallback(Model(), Error())>, headers: Maybe<&2, T.ProviderHeaders()>, maxRetries: Maybe<&2, F64>) -> Options():
  T.ImagesOptions{signal, None{}, key, None{}, None{}, onPayload, onResponse, headers, None{}, maxRetries, None{}, None{}}

def keyed(key: String) -> Options(): options(Some{key}, None{}, None{}, None{}, None{}, None{})

def headerFields(entries: List<&2, R.Property<String>>) -> List<&2, R.Property<J()>>:
  match entries:
    case Nil{}: Nil{}
    case R.Property{name, value} <> rest: R.Property{name, jstr(value)} <> headerFields(rest)

def responseJson(value: T.ProviderResponse) -> J():
  match value:
    case T.ProviderResponse{status, R.Record{headers}}: jobj([prop("status", jnum(status)), prop("headers", jobj(headerFields(headers)))])

def capture(unused: Unit, input: T.PayloadInput<J(), Model()>) -> IO(Result<&2, &2, Error(), Maybe<&2, J()>>):
  match input:
    case T.PayloadInput{+payload, _}:
      do IO<Result<&2, &2, Error(), Maybe<&2, J()>>>:
        IO.print("payload " ++ jsonText(payload))
        return Done{None{}}

# onPayload replaces the params: a different prompt and an extra member.
def replacement() -> J():
  jobj([prop("model", jstr("black-forest-labs/flux.2-pro")), prop("messages", T.JsonArray{[jobj([prop("role", jstr("user")), prop("content", jstr("replaced prompt"))])]}), prop("stream", T.JsonBoolean{False{}}), prop("modalities", T.JsonArray{[jstr("image")]}), prop("seed", jnum(F.fromU32(7)))])

def replace(unused: Unit, input: T.PayloadInput<J(), Model()>) -> IO(Result<&2, &2, Error(), Maybe<&2, J()>>):
  match input:
    case T.PayloadInput{+payload, _}:
      do IO<Result<&2, &2, Error(), Maybe<&2, J()>>>:
        IO.print("payload " ++ jsonText(payload))
        return Done{Some{replacement()}}

def observe(unused: Unit, input: T.ResponseInput<Model()>) -> IO(Result<&2, &2, Error(), Unit>):
  match input:
    case T.ResponseInput{response, _}:
      do IO<Result<&2, &2, Error(), Unit>>:
        IO.print("response " ++ jsonText(responseJson(response)))
        return Done{Unit{}}

# Reporting
# ---------

def contentJson(item: T.TextImageContent) -> J():
  match item:
    case T.TextImageText{T.TextContent{text, _}}: jobj([prop("type", jstr("text")), prop("text", jstr(text))])
    case T.TextImageImage{T.ImageContent{data, mimeType}}: jobj([prop("type", jstr("image")), prop("mimeType", jstr(mimeType)), prop("data", jstr(data))])

def contentList(items: List<&2, T.TextImageContent>) -> List<&2, J()>:
  match items:
    case Nil{}: Nil{}
    case item <> rest: contentJson(item) <> contentList(rest)

def costJson(value: T.UsageCost) -> J():
  match value:
    case T.UsageCost{input, output, read, write, total}: jobj([prop("input", jnum(input)), prop("output", jnum(output)), prop("cacheRead", jnum(read)), prop("cacheWrite", jnum(write)), prop("total", jnum(total))])

def usageJson(value: T.Usage) -> J():
  match value:
    case T.Usage{input, output, read, write, _, _, total, price}: jobj([prop("input", jnum(input)), prop("output", jnum(output)), prop("cacheRead", jnum(read)), prop("cacheWrite", jnum(write)), prop("totalTokens", jnum(total)), prop("cost", costJson(price))])

def stopName(value: T.ImagesStopReason) -> String:
  match value:
    case T.ImagesStop{}: "stop"
    case T.ImagesError{}: "error"
    case T.ImagesAborted{}: "aborted"

def optional(name: String, value: Maybe<&2, J()>) -> List<&2, R.Property<J()>>:
  match value:
    case Some{item}: [prop(name, item)]
    case None{}: Nil{}

def resultJson(value: T.AssistantImages) -> J():
  match value:
    case T.AssistantImages{api, provider, model, output, responseId, usage, stop, error, _}:
      T.JsonObject{R.Record{List.concat(&2, R.Property<J()>, [[prop("api", jstr(api)), prop("provider", jstr(provider)), prop("model", jstr(model)), prop("output", T.JsonArray{contentList(output)}), prop("stopReason", jstr(stopName(stop)))], optional("responseId", Maybe.map(&2, String, J(), jstr, responseId)), optional("usage", Maybe.map(&2, T.Usage, J(), usageJson, usage)), optional("errorMessage", Maybe.map(&2, String, J(), jstr, error))])}}

def reported(result: Result<&2, &2, String, T.AssistantImages>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print("thrown " ++ message)
    case Done{value}: IO.print("result " ++ jsonText(resultJson(value)))

# Cases
# -----

def generated(api: ImagesModels.ProviderImages(Error()), +model: Model(), context: T.ImagesContext, value: Options()) -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, T.AssistantImages> <- Images.generateImages(Error(), Builtins.builtinImagesApiRegistry(Error(), api), model, context, Some{value})
    reported(result)

def hooked(api: ImagesModels.ProviderImages(Error()), +model: Model(), context: T.ImagesContext, key: Maybe<&2, String>, headers: Maybe<&2, T.ProviderHeaders()>, maxRetries: Maybe<&2, F64>) -> IO(Unit):
  do IO<Unit>:
    +payloadHook : T.PayloadCallback(J(), Model(), Error()) <- C.create(~Unit, ~T.PayloadInput<J(), Model()>, ~Result<&2, &2, Error(), Maybe<&2, J()>>, ~capture, Unit{})
    +responseHook : T.ResponseCallback(Model(), Error()) <- C.create(~Unit, ~T.ResponseInput<Model()>, ~Result<&2, &2, Error(), Unit>, ~observe, Unit{})
    generated(api, model, context, options(key, None{}, Some{payloadHook}, Some{responseHook}, headers, maxRetries))
    C.dispose(T.PayloadInput<J(), Model()>, Result<&2, &2, Error(), Maybe<&2, J()>>, payloadHook)
    C.dispose(T.ResponseInput<Model()>, Result<&2, &2, Error(), Unit>, responseHook)

def replaced(api: ImagesModels.ProviderImages(Error()), +model: Model()) -> IO(Unit):
  do IO<Unit>:
    +payloadHook : T.PayloadCallback(J(), Model(), Error()) <- C.create(~Unit, ~T.PayloadInput<J(), Model()>, ~Result<&2, &2, Error(), Maybe<&2, J()>>, ~replace, Unit{})
    generated(api, model, dog(), options(Some{"test"}, None{}, Some{payloadHook}, None{}, None{}, None{}))
    C.dispose(T.PayloadInput<J(), Model()>, Result<&2, &2, Error(), Maybe<&2, J()>>, payloadHook)

def aborted(api: ImagesModels.ProviderImages(Error()), +model: Model()) -> IO(Unit):
  do IO<Unit>:
    +controller : Abort.AbortController<Unit> <- Abort.new(Unit)
    won : Bool <- Abort.abort(Unit, controller, None{})
    generated(api, model, dog(), options(Some{"test"}, Some{Abort.signal(Unit, controller)}, None{}, None{}, None{}, None{}))
    Abort.dispose(Unit, controller)

def present(value: String) -> T.Nullable<String>: T.PresentValue{value}

def headerOverrides() -> T.ProviderHeaders():
  R.Record{[R.Property{"HTTP-Referer", T.NullValue{}}, R.Property{"X-Title", present("pi-bend")}, R.Property{"x-custom", present("value")}]}

def withApi(model: Model(), api: String) -> Model():
  match model:
    case T.ImagesModel{id, name, _, provider, base, levels, input, limits, price, cache, sampling, headers, output}: T.ImagesModel{id, name, api, provider, base, levels, input, limits, price, cache, sampling, headers, output}

def selected(api: ImagesModels.ProviderImages(Error()), +mode: String, baseUrl: String) -> IO(Unit):
  match mode:
    case "text-and-image": hooked(api, geminiImage(baseUrl), dog(), Some{"test"}, None{}, None{})
    case "abort": aborted(api, flux(baseUrl))
    case "flux": generated(api, flux(baseUrl), dog(), keyed("test"))
    case "catalog": hooked(api, catalogModel(baseUrl), withImage(), Some{"test"}, None{}, None{})
    case "usage": generated(api, priced(baseUrl), dog(), keyed("test"))
    case "no-key": generated(api, flux(baseUrl), dog(), options(None{}, None{}, None{}, None{}, None{}, None{}))
    case "headers": hooked(api, geminiImage(baseUrl), dog(), Some{"test"}, Some{headerOverrides()}, None{})
    case "replace": replaced(api, flux(baseUrl))
    case "retry": hooked(api, flux(baseUrl), dog(), Some{"test"}, None{}, Some{F.fromU32(1)})
    case "unregistered": generated(api, withApi(flux(baseUrl), "other-images"), dog(), keyed("test"))
    case _: hooked(api, flux(baseUrl), dog(), Some{"test"}, None{}, None{})

# The generated catalog in upstream IMAGE_MODELS' JSON shape (only the fields
# the pinned catalog uses).
def inputNames(values: List<&2, T.ModelInput>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case T.InputText{} <> rest: jstr("text") <> inputNames(rest)
    case T.InputImage{} <> rest: jstr("image") <> inputNames(rest)

def catalogJson(model: Model()) -> J():
  match model:
    case T.ImagesModel{id, name, api, provider, baseUrl, _, input, _, T.ModelCost{a, b, c, d, _}, _, _, _, output}:
      jobj([prop("id", jstr(id)), prop("name", jstr(name)), prop("api", jstr(api)), prop("provider", jstr(provider)), prop("baseUrl", jstr(baseUrl)), prop("input", T.JsonArray{inputNames(input)}), prop("output", T.JsonArray{inputNames(output)}), prop("cost", jobj([prop("input", jnum(a)), prop("output", jnum(b)), prop("cacheRead", jnum(c)), prop("cacheWrite", jnum(d))]))])

def printModels(models: List<&2, Model()>) -> IO(Unit):
  match models:
    case Nil{}: IO.pure(Unit, Unit{})
    case model <> rest:
      do IO<Unit>:
        IO.print("model " ++ jsonText(catalogJson(model)))
        printModels(rest)

def stringItems(values: List<&2, String>) -> List<&2, J()>:
  match values:
    case Nil{}: Nil{}
    case value <> rest: jstr(value) <> stringItems(rest)

def dumpCatalog() -> IO(Unit):
  do IO<Unit>:
    IO.print("providers " ++ jsonText(T.JsonArray{stringItems(Catalog.getImageProviders())}))
    printModels(Catalog.getImageModels("openrouter"))

def borrowed(mode: String, baseUrl: String, pair: Fetch.Runtime & Fetch.Fetch(Unit)) -> IO(Unit):
  match pair:
    case (owned, +fetch):
      do IO<Unit>:
        +api : ImagesModels.ProviderImages(Error()) <- OpenRouter.openrouterImagesApi(~Error(), ~render, OpenRouter.ImagesTransport{fetch, urlContext(), Client.Defaults{"pi-bend-test", R.new(String), None{}, None{}}})
        selected(api, mode, baseUrl)
        C.dispose(ImagesModels.ImagesRequest<Error()>, T.AssistantImages, api)
        Fetch.retire(Unit, fetch)
        Fetch.dispose(owned)

def active(mode: String, baseUrl: String, runtime: Fetch.Runtime) -> IO(Unit):
  do IO<Unit>:
    pair : Fetch.Runtime & Fetch.Fetch(Unit) <- Fetch.callback(~Unit, runtime)
    borrowed(mode, baseUrl, pair)

def initialized(mode: String, baseUrl: String, result: Result<&2, &1, Fetch.InitError, Fetch.Runtime>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "network initialization failed")
    case Done{runtime}: active(mode, baseUrl, runtime)

def run(mode: String, baseUrl: String) -> IO(Unit):
  do IO<Unit>:
    runtime : Result<&2, &1, Fetch.InitError, Fetch.Runtime> <- Fetch.create(Fetch.linuxFiles(), networkOptions())
    initialized(mode, baseUrl, runtime)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case "catalog-dump" <> Nil{}: dumpCatalog()
    case mode <> baseUrl <> Nil{}: run(mode, baseUrl)
    case _: IO.die(Unit, 1, "usage: openrouter-images <case> <baseUrl>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
